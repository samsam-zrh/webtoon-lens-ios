const imageInput = document.getElementById("imageInput");
const previewImage = document.getElementById("previewImage");
const emptyState = document.getElementById("emptyState");
const overlay = document.getElementById("overlay");
const stage = document.getElementById("stage");
const imageReader = document.getElementById("imageReader");
const translateButton = document.getElementById("translateButton");
const sourceText = document.getElementById("sourceText");
const backendUrl = document.getElementById("backendUrl");
const statusLine = document.getElementById("statusLine");
const webtoonUrl = document.getElementById("webtoonUrl");
const openUrlButton = document.getElementById("openUrlButton");

const boxes = [
  { x: 0.12, y: 0.14, width: 0.42, height: 0.09 },
  { x: 0.48, y: 0.39, width: 0.36, height: 0.1 },
  { x: 0.16, y: 0.68, width: 0.46, height: 0.1 }
];

backendUrl.value = localStorage.getItem("webtoonLensBackend") || window.location.origin;
webtoonUrl.value = localStorage.getItem("webtoonLensUrl") || "";

if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}

imageInput.addEventListener("change", () => {
  const file = imageInput.files && imageInput.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = () => {
    stage.classList.remove("feed-mode");
    imageReader.innerHTML = "";
    previewImage.src = String(reader.result);
    previewImage.style.display = "block";
    emptyState.style.display = "none";
    overlay.innerHTML = "";
    statusLine.textContent = "Capture chargee.";
  };
  reader.readAsDataURL(file);
});

openUrlButton.addEventListener("click", openWebtoonUrl);
webtoonUrl.addEventListener("keydown", (event) => {
  if (event.key === "Enter") openWebtoonUrl();
});

backendUrl.addEventListener("input", () => {
  localStorage.setItem("webtoonLensBackend", backendUrl.value.trim());
});

translateButton.addEventListener("click", async () => {
  translateButton.disabled = true;
  translateButton.textContent = "Traduction...";

  try {
    if (stage.classList.contains("feed-mode")) {
      const count = await translateReaderImages();
      statusLine.textContent = `OK: ${count} images annotees.`;
      return;
    }

    const lines = sourceText.value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);

    const segments = lines.map((line, index) => ({
      id: `preview-${index}`,
      text: line,
      boundingBox: boxes[index % boxes.length],
      confidence: 0.9,
      readingOrder: index
    }));

    const translated = await translateSegments(segments);
    render(translated);
    statusLine.textContent = `OK: ${translated.length} bulles traduites.`;
  } catch (error) {
    statusLine.textContent = error && error.message ? error.message : String(error);
  } finally {
    translateButton.disabled = false;
    translateButton.textContent = "Traduire";
  }
});

async function openWebtoonUrl() {
  const value = webtoonUrl.value.trim();
  if (!value) {
    statusLine.textContent = "Colle d'abord un lien.";
    return;
  }

  openUrlButton.disabled = true;
  openUrlButton.textContent = "Ouverture...";
  statusLine.textContent = "Extraction des images...";

  try {
    const normalized = value.includes("://") ? value : `https://${value}`;
    webtoonUrl.value = normalized;
    localStorage.setItem("webtoonLensUrl", normalized);

    const response = await fetch(`/v1/webtoon/extract?url=${encodeURIComponent(normalized)}`);
    if (!response.ok) throw new Error(`Extraction impossible (${response.status})`);
    const payload = await response.json();
    renderImageFeed(payload.images || []);
  } catch (error) {
    statusLine.textContent = error && error.message ? error.message : String(error);
  } finally {
    openUrlButton.disabled = false;
    openUrlButton.textContent = "Ouvrir le lien";
  }
}

function renderImageFeed(images) {
  stage.classList.add("feed-mode");
  previewImage.style.display = "none";
  overlay.innerHTML = "";
  imageReader.innerHTML = "";

  if (!images.length) {
    emptyState.style.display = "grid";
    emptyState.querySelector("strong").textContent = "Aucune image trouvee";
    emptyState.querySelector("span").textContent = "Certains sites chargent les images apres connexion ou bloquent l'extraction.";
    statusLine.textContent = "Aucune image trouvee sur cette page.";
    return;
  }

  emptyState.style.display = "none";
  for (const [index, image] of images.entries()) {
    const page = document.createElement("article");
    page.className = "reader-page";
    page.dataset.index = String(index);

    const img = document.createElement("img");
    img.src = `/v1/webtoon/image?url=${encodeURIComponent(image.url)}`;
    img.alt = image.alt || `Image webtoon ${index + 1}`;
    img.loading = index < 2 ? "eager" : "lazy";

    const pageOverlay = document.createElement("div");
    pageOverlay.className = "overlay";
    pageOverlay.setAttribute("aria-live", "polite");

    page.append(img, pageOverlay);
    imageReader.appendChild(page);
  }

  statusLine.textContent = `${images.length} images chargees. Appuie sur Traduire.`;
}

async function translateSegments(segments) {
  const baseUrl = backendUrl.value.trim();
  if (!baseUrl) {
    return segments.map((segment) => ({
      id: segment.id,
      translatedText: localPreviewTranslate(segment.text),
      boundingBox: segment.boundingBox
    }));
  }

  const response = await fetch(`${baseUrl.replace(/\/$/, "")}/v1/webtoon/translate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      sourceLanguage: "auto",
      targetLanguage: "fr",
      seriesID: "phone-preview",
      style: "Traduction naturelle en francais, adaptee aux webtoons.",
      glossary: [
        { id: "astra", source: "Astra", translation: "Astra", category: "power", isLocked: true },
        { id: "north-blade", source: "Lame du nord", translation: "Lame du Nord", category: "power", isLocked: true }
      ],
      segments
    })
  });

  if (!response.ok) {
    throw new Error(`Backend ${response.status}`);
  }

  const payload = await response.json();
  return payload.segments || [];
}

function localPreviewTranslate(text) {
  return text
    .replace(/lame du nord/gi, "Lame du Nord")
    .replace(/astra/gi, "Astra")
    .replace(/^(.+)$/, "[fr] $1");
}

function render(segments) {
  overlay.innerHTML = "";

  for (const segment of segments) {
    const box = segment.boundingBox || boxes[0];
    const bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.textContent = segment.translatedText || segment.text || "";
    bubble.style.left = `${box.x * 100}%`;
    bubble.style.top = `${box.y * 100}%`;
    bubble.style.width = `${box.width * 100}%`;
    bubble.style.minHeight = `${Math.max(42, box.height * overlay.clientHeight)}px`;
    overlay.appendChild(bubble);
  }
}

async function translateReaderImages() {
  const pages = Array.from(document.querySelectorAll(".reader-page"));
  let translatedCount = 0;

  for (const [pageIndex, page] of pages.entries()) {
    const pageOverlay = page.querySelector(".overlay");
    if (!pageOverlay) continue;

    const lines = sourceText.value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);

    const segments = lines.map((line, index) => ({
      id: `page-${pageIndex}-segment-${index}`,
      text: line,
      boundingBox: boxes[index % boxes.length],
      confidence: 0.9,
      readingOrder: index
    }));

    const translated = await translateSegments(segments);
    renderIntoOverlay(pageOverlay, translated);
    translatedCount += 1;
  }

  return translatedCount;
}

function renderIntoOverlay(targetOverlay, segments) {
  targetOverlay.innerHTML = "";

  for (const segment of segments) {
    const box = segment.boundingBox || boxes[0];
    const bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.textContent = segment.translatedText || segment.text || "";
    bubble.style.left = `${box.x * 100}%`;
    bubble.style.top = `${box.y * 100}%`;
    bubble.style.width = `${box.width * 100}%`;
    bubble.style.minHeight = `${Math.max(42, box.height * targetOverlay.clientHeight)}px`;
    targetOverlay.appendChild(bubble);
  }
}
