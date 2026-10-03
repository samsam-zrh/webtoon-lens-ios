(() => {
  "use strict";
  const container = document.getElementById("pages");
  let generation = "";
  let original = false;
  const pages = new Map();
  let frame = 0;
  function hash(text) {
    let value = 2166136261;
    for (const character of String(text || "")) value = Math.imul(value ^ character.codePointAt(0), 16777619);
    return (value >>> 0).toString(16);
  }

  function emit() {
    const rendered = [];
    for (const [index, page] of pages) {
      for (const bubble of page.element.querySelectorAll(".bubble")) {
        if (!bubble.hidden && bubble.dataset.fit === "true") {
          const segment = page.segments.find(item => item.id === bubble.dataset.segmentId);
          rendered.push({ page: index, id: bubble.dataset.segmentId,
            fontSize: Number(bubble.dataset.fontSize), width: Number(bubble.dataset.textWidth),
            maxLineWidth: Number(bubble.dataset.maxLineWidth), height: Number(bubble.dataset.textHeight),
            usedHeight: Number(bubble.dataset.usedHeight),
            sourceLength: String(segment?.sourceText || "").length,
            translationLength: String(segment?.translatedText || "").length,
            sourceHash: hash(segment?.sourceText), translationHash: hash(segment?.translatedText) });
        }
      }
    }
    window.webkit.messageHandlers.publicChapter.postMessage({
      generation, type: "metrics", pageCount: pages.size, rendered,
      visiblePage: Array.from(pages.entries()).find(([, page]) => {
        const rect = page.element.getBoundingClientRect();
        return rect.top <= innerHeight / 2 && rect.bottom > innerHeight / 2;
      })?.[0] ?? 0,
      pages: Array.from(pages.entries()).map(([index, page]) => ({
        index, width: page.width, height: page.height, publicURL: page.publicURL,
        loaded: page.element.querySelector("img").naturalWidth > 0,
        errors: Array.from(page.element.querySelectorAll(".page-error")).map(item => item.textContent)
      })),
      mountedImages: Array.from(pages.values()).filter(page => page.mounted).length,
      original
    });
  }

  function render(page) {
    const overlay = page.element.querySelector(".overlay");
    WebtoonLayout.clear(overlay);
    if (page.mounted) {
      for (const segment of page.segments) WebtoonLayout.render(overlay, segment);
      for (const failure of page.failures) WebtoonLayout.renderError(overlay, failure.source, failure.message);
    }
    emit();
  }

  function updateMounted() {
    frame = 0;
    const candidates = Array.from(pages.values()).sort((a, b) => {
      const distance = page => {
        const rect = page.element.getBoundingClientRect();
        return rect.top < innerHeight && rect.bottom > 0 ? 0 : Math.min(Math.abs(rect.top - innerHeight), Math.abs(rect.bottom));
      };
      return distance(a) - distance(b);
    });
    const mounted = new Set(candidates.slice(0, 3));
    for (const page of pages.values()) {
      const img = page.element.querySelector("img");
      if (mounted.has(page) && !page.mounted) {
        page.mounted = true;
        page.element.classList.remove("evicted");
        img.src = page.source;
      } else if (!mounted.has(page) && page.mounted) {
        page.mounted = false;
        page.element.classList.add("evicted");
        img.removeAttribute("src");
        WebtoonLayout.clear(page.element.querySelector(".overlay"));
      }
    }
    emit();
  }

  function scheduleMounted() {
    if (!frame) frame = requestAnimationFrame(updateMounted);
  }

  function addPage(command) {
    const article = document.createElement("article");
    article.className = "reader-page";
    article.dataset.page = command.index;
    const label = document.createElement("h2");
    label.className = "page-label";
    label.textContent = `Page ${command.index + 1}`;
    const image = document.createElement("img");
    image.alt = `Page de chapitre ${command.index + 1}`;
    image.width = command.width;
    image.height = command.height;
    image.style.aspectRatio = `${command.width} / ${command.height}`;
    image.decoding = "async";
    const overlay = document.createElement("div");
    overlay.className = "overlay";
    article.append(label, image, overlay);
    container.append(article);
    const page = { element: article, source: command.source, width: command.width, height: command.height,
      publicURL: command.publicURL, segments: [], failures: [], mounted: false };
    pages.set(command.index, page);
    const position = () => {
      overlay.style.top = `${image.offsetTop}px`;
      overlay.style.height = `${image.clientHeight}px`;
    };
    new ResizeObserver(position).observe(image);
    image.addEventListener("load", () => { position(); render(page); });
    image.addEventListener("error", () => {
      window.webkit.messageHandlers.publicChapter.postMessage({ generation, type: "imageError", index: command.index });
    });
    scheduleMounted();
  }

  window.PublicChapterReader = {
    update(command) {
      if (command.type === "reset") {
        for (const page of pages.values()) WebtoonLayout.clear(page.element.querySelector(".overlay"));
        pages.clear();
        container.replaceChildren();
        generation = command.generation;
        original = false;
        document.body.classList.remove("original");
        return;
      }
      if (command.generation !== generation) return;
      if (command.type === "page") {
        if (!pages.has(command.index)) addPage(command);
      } else if (command.type === "translation") {
        const page = pages.get(command.index);
        if (!page) throw new Error("Page de traduction absente.");
        for (const segment of command.segments) {
          page.segments = page.segments.filter(previous => previous.id !== segment.id);
          page.segments.push(segment);
        }
        for (const failure of command.failures) {
          page.failures = page.failures.filter(previous => previous.source.id !== failure.source.id);
          page.failures.push(failure);
        }
        render(page);
      } else if (command.type === "pageError") {
        const page = pages.get(command.index);
        if (!page) throw new Error("Page en erreur absente.");
        let message = page.element.querySelector(".page-error");
        if (!message) {
          message = document.createElement("p");
          message.className = "page-error";
          message.setAttribute("role", "alert");
          page.element.append(message);
          const retry = document.createElement("button");
          retry.className = "page-retry";
          retry.textContent = `Reessayer la page ${command.index + 1}`;
          retry.addEventListener("click", () => {
            window.webkit.messageHandlers.publicChapter.postMessage({ generation, type: "retry", index: command.index });
          });
          page.element.append(retry);
        }
        message.textContent = command.message;
      } else if (command.type === "recovered") {
        const page = pages.get(command.index);
        page?.element.querySelector(".page-error")?.remove();
        page?.element.querySelector(".page-retry")?.remove();
      } else if (command.type === "original") {
        original = command.original;
        document.body.classList.toggle("original", original);
        emit();
      } else if (command.type === "scroll") {
        pages.get(command.index)?.element.scrollIntoView({ block: "start", behavior: "auto" });
        scheduleMounted();
      } else if (command.type === "dialogue") {
        const page = pages.get(command.index);
        const bubble = Array.from(page?.element.querySelectorAll(".bubble") || [])
          .find(element => !element.hidden && element.dataset.fit === "true");
        bubble?.scrollIntoView({ block: "center", behavior: "auto" });
        scheduleMounted();
      }
    },
    metrics() {
      emit();
    }
  };
  window.addEventListener("scroll", scheduleMounted, { passive: true });
  window.addEventListener("resize", () => { scheduleMounted(); emit(); }, { passive: true });
  window.webkit.messageHandlers.publicChapter.postMessage({ generation, type: "ready" });
})();
