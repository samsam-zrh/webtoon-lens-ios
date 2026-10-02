/* Mesure réelle du texte ; un échec préserve l'image et renvoie au texte intégral. */
window.WebtoonLayout = (() => {
  const measure = document.createElement("canvas").getContext("2d");
  const family = '"Comic Sans MS", "Trebuchet MS", Arial, sans-serif';
  const displayFamily = 'Impact, "Arial Narrow", Arial, sans-serif';
  const observers = new WeakMap();

  function wrap(text, width) {
    const lines = [];
    let line = "";
    for (const word of text.split(/\s+/)) {
      if (measure.measureText(word).width > width) {
        if (line) lines.push(line);
        line = "";
        for (const char of Array.from(word)) {
          if (line && measure.measureText(line + char).width > width) {
            lines.push(line);
            line = char;
          } else line += char;
        }
      } else if (line && measure.measureText(`${line} ${word}`).width > width) {
        lines.push(line);
        line = word;
      } else line = line ? `${line} ${word}` : word;
    }
    if (line) lines.push(line);
    return lines;
  }

  function fit(text, width, height, preferred, weight = "700", typeface = family, fontStyle = "normal") {
    const ceiling = Math.floor(Math.min(preferred, height/1.2, width)*2)/2;
    for (let size = ceiling; size >= 10; size -= 0.5) {
      measure.font = `${fontStyle} ${weight} ${size}px ${typeface}`;
      const lines = wrap(text, Math.max(1, width - 2));
      const maxWidth = Math.max(0, ...lines.map(line => measure.measureText(line).width));
      const lineHeight = size * 1.2;
      if (maxWidth <= width - 2 && lines.length * lineHeight <= height - 4) {
        return { lines, size, lineHeight, maxWidth, totalHeight: lines.length * lineHeight };
      }
    }
    return null;
  }

  function dialogueDetails(target) {
    let details = target.parentElement.querySelector(".dialogue-list");
    if (!details) {
      details = document.createElement("details");
      details.className = "dialogue-list";
      const summary = document.createElement("summary");
      summary.textContent = "Lire les dialogues et leur original";
      details.append(summary);
      target.parentElement.append(details);
    }
    return details;
  }

  function removeDialogueItem(details, id) {
    Array.from(details.querySelectorAll(".dialogue-entry, .dialogue-error"))
      .find(entry => entry.dataset.segmentId === id)?.remove();
  }

  function renderError(target, segment, message) {
    const details = dialogueDetails(target);
    removeDialogueItem(details, segment.id);
    const item = document.createElement("div");
    item.className = "dialogue-error";
    item.dataset.segmentId = segment.id;
    const original = document.createElement("p");
    original.textContent = segment.sourceText || segment.text || "";
    const error = document.createElement("p");
    error.setAttribute("role", "alert");
    error.textContent = `Traduction indisponible : ${message}. Les autres dialogues continuent.`;
    item.append(original, error);
    details.append(item);
    details.open = true;
  }

  function render(target, segment) {
    const box = segment.boundingBox;
    const raw = segment.rawBoundingBox || box;
    if (!box || !raw) throw new Error("Coordonnées de bulle manquantes.");
    const old = Array.from(target.querySelectorAll(".bubble")).find(b => b.dataset.segmentId === segment.id);
    if (old) old.remove();
    const bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.dataset.segmentId = segment.id;
    for (const key of ["x", "y", "width", "height"]) bubble.dataset[key] = box[key];
    bubble.style.left = `${box.x * 100}%`;
    bubble.style.top = `${box.y * 100}%`;
    bubble.style.width = `${box.width * 100}%`;
    bubble.style.height = `${box.height * 100}%`;
    const fill = document.createElement("div");
    fill.className = "bubble-fill";
    fill.style.background = segment.style?.fillColor || "#fff";
    if (segment.replacementData) {
      fill.style.backgroundColor = "transparent";
      fill.style.backgroundImage = `url("${segment.replacementData}")`;
      fill.style.backgroundSize = "100% 100%";
    }
    if (segment.maskData) {
      fill.style.maskImage = `url("${segment.maskData}")`;
      fill.style.webkitMaskImage = `url("${segment.maskData}")`;
    }
    const text = document.createElement("div");
    text.className = "bubble-text";
    const textBox = segment.textBox || raw;
    text.style.left = `${(textBox.x - box.x) / box.width * 100}%`;
    text.style.top = `${(textBox.y - box.y) / box.height * 100}%`;
    text.style.width = `${textBox.width / box.width * 100}%`;
    text.style.height = `${textBox.height / box.height * 100}%`;
    const original = segment.sourceText || "";
    const letters = original.match(/[A-Za-z]/g) || [];
    const capitals = letters.length >= 6 && letters.filter(l => l === l.toUpperCase()).length / letters.length > 0.82;
    const translation = String(segment.translatedText || "").replace(/\s+/g, " ").trim();
    const displayed = capitals ? translation.toLocaleUpperCase("fr") : translation;
    const typeface = segment.style?.fontFamily === "display" ? displayFamily : family;
    const fontStyle = segment.style?.fontStyle === "italic" ? "italic" : "normal";
    text.style.fontFamily = typeface;
    text.style.fontStyle = fontStyle;
    text.style.color = segment.style?.textColor || "#111";
    const weight = capitals ? "800" : "700";
    text.style.fontWeight = weight;
    bubble.append(fill, text);
    target.append(bubble);
    const details = dialogueDetails(target);
    const item = document.createElement("div");
    item.className = "dialogue-entry";
    item.dataset.segmentId = segment.id;
    removeDialogueItem(details, segment.id);
    const source = document.createElement("p");
    source.lang = /[\u3400-\u9fff]/.test(original) ? "zh" : "en";
    source.textContent = original;
    const french = document.createElement("p");
    french.textContent = translation;
    const hint = document.createElement("small");
    item.append(source, french, hint);
    details.append(item);

    const update = () => {
      const width = target.clientWidth * textBox.width;
      const height = target.clientHeight * textBox.height;
      const scale = target.clientWidth / (segment.imageWidth || target.clientWidth);
      const preferred = (segment.fontSizeSource || 20) * scale;
      let result = segment.renderMode === "replace" && segment.maskData
        ? fit(displayed, width, height, Math.max(10, preferred), weight, typeface, fontStyle) : null;
      bubble.hidden = false;
      while (result) {
        text.textContent = result.lines.join("\n");
        text.style.fontSize = `${result.size}px`;
        text.style.lineHeight = `${result.lineHeight}px`;
        if (text.scrollHeight <= text.clientHeight && text.scrollWidth <= text.clientWidth) break;
        result = fit(displayed, width, height, result.size - 0.5, weight, typeface, fontStyle);
      }
      bubble.dataset.fit = result ? "true" : "false";
      bubble.hidden = !result;
      hint.textContent = result ? "Traduction ajustée dans la bulle · police approchée."
        : "Original conservé : zone non fiable ou texte trop petit. Traduction intégrale ci-dessus.";
      if (!result) return;
      bubble.dataset.maxLineWidth = result.maxWidth;
      bubble.dataset.textWidth = width;
      bubble.dataset.textHeight = height;
      bubble.dataset.usedHeight = result.totalHeight;
      bubble.dataset.fontSize = result.size;
    };
    target.__layouts ||= new Map();
    target.__layouts.set(segment.id, update);
    if (!observers.has(target)) {
      const observer = new ResizeObserver(() => target.__layouts.forEach(fn => fn()));
      observer.observe(target);
      observers.set(target, observer);
    }
    update();
    if (bubble.dataset.fit === "false") details.open = true;
    return bubble;
  }

  function clear(target) {
    observers.get(target)?.disconnect();
    observers.delete(target);
    target.__layouts = new Map();
    target.innerHTML = "";
    target.parentElement.querySelector(".dialogue-list")?.remove();
  }
  return { fit, render, renderError, clear };
})();
