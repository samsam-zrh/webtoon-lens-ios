const imageInput = document.getElementById("imageInput");
const previewImage = document.getElementById("previewImage");
const emptyState = document.getElementById("emptyState");
const overlay = document.getElementById("overlay");
const stage = document.getElementById("stage");
const imageReader = document.getElementById("imageReader");
const translateButton = document.getElementById("translateButton");
const backendUrl = document.getElementById("backendUrl");
const statusLine = document.getElementById("statusLine");
const webtoonUrl = document.getElementById("webtoonUrl");
const openUrlButton = document.getElementById("openUrlButton");
const capabilityLine = document.getElementById("capabilityLine");
const readerSummary = document.getElementById("readerSummary");
const ocrLanguage = document.getElementById("ocrLanguage");

backendUrl.value = localStorage.getItem("webtoonLensBackend") || window.location.origin;
webtoonUrl.value = localStorage.getItem("webtoonLensUrl") || "";
ocrLanguage.value = localStorage.getItem("webtoonLensOcrLanguage") || "auto";

let loadedImages = 0;
let failedImages = 0;
let currentPageUrl = "";
let currentCaptureDataUrl = "";

if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}

loadCapabilities();

imageInput.addEventListener("change", () => {
  const file = imageInput.files && imageInput.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = () => {
    resetReaderCounters();
    stage.classList.remove("feed-mode");
    imageReader.innerHTML = "";
    currentCaptureDataUrl = String(reader.result);
    previewImage.src = currentCaptureDataUrl;
    previewImage.style.display = "block";
    emptyState.style.display = "none";
    overlay.innerHTML = "";
    readerSummary.textContent = "Capture chargee depuis ton telephone.";
    statusLine.textContent = "Image chargee. Appuie sur Traduire pour lancer OCR + traduction locale.";
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

ocrLanguage.addEventListener("change", () => {
  localStorage.setItem("webtoonLensOcrLanguage", ocrLanguage.value);
});

translateButton.addEventListener("click", async () => {
  translateButton.disabled = true;
  translateButton.textContent = "Verification...";

  try {
    if (stage.classList.contains("feed-mode")) {
      await translateReaderImages();
      return;
    }

    if (previewImage.style.display === "block") {
      await translateCapture();
      return;
    }

    statusLine.textContent = "Ouvre un lien webtoon ou choisis une image avant de traduire.";
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
  readerSummary.textContent = "";
  statusLine.textContent = "Extraction des images visibles dans la page...";

  try {
    const normalized = value.includes("://") ? value : `https://${value}`;
    webtoonUrl.value = normalized;
    localStorage.setItem("webtoonLensUrl", normalized);
    currentPageUrl = normalized;

    const response = await fetch(`/v1/webtoon/extract?url=${encodeURIComponent(normalized)}`);
    if (!response.ok) {
      const message = await readError(response);
      throw new Error(message || `Extraction impossible (${response.status})`);
    }
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
  resetReaderCounters();
  stage.classList.add("feed-mode");
  previewImage.style.display = "none";
  overlay.innerHTML = "";
  imageReader.innerHTML = "";

  if (!images.length) {
    emptyState.style.display = "grid";
    emptyState.querySelector("strong").textContent = "Aucune image trouvee";
    emptyState.querySelector("span").textContent = "Certains sites chargent les images avec JavaScript, demandent une connexion, ou bloquent le proxy local.";
    readerSummary.textContent = "0 image extraite.";
    statusLine.textContent = "Essaie un lien direct d'episode avec images publiques, ou choisis une capture.";
    return;
  }

  emptyState.style.display = "none";
  for (const [index, image] of images.entries()) {
    const page = document.createElement("article");
    page.className = "reader-page";
    page.dataset.index = String(index);
    page.dataset.sourceUrl = image.url;

    const badge = document.createElement("div");
    badge.className = "page-badge";
    badge.textContent = `Image ${index + 1}`;

    const img = document.createElement("img");
    img.src = proxyImageUrl(image.url);
    img.alt = image.alt || `Image webtoon ${index + 1}`;
    img.loading = index < 2 ? "eager" : "lazy";
    img.addEventListener("load", () => {
      loadedImages += 1;
      page.dataset.loaded = "true";
      updateReaderStatus(images.length);
    });
    img.addEventListener("error", () => {
      failedImages += 1;
      page.classList.add("load-error");
      badge.textContent = `Image ${index + 1} bloquee`;
      updateReaderStatus(images.length);
    });

    const pageOverlay = document.createElement("div");
    pageOverlay.className = "overlay";
    pageOverlay.setAttribute("aria-live", "polite");

    page.append(img, badge, pageOverlay);
    imageReader.appendChild(page);
  }

  readerSummary.textContent = `${images.length} images trouvees. Chargement en cours...`;
  statusLine.textContent = "Le lecteur charge les images. Appuie sur Traduire pour lancer OCR + traduction locale.";
}

function proxyImageUrl(url) {
  const params = new URLSearchParams({ url });
  if (currentPageUrl) params.set("referer", currentPageUrl);
  return `/v1/webtoon/image?${params.toString()}`;
}

async function translateReaderImages() {
  const pages = Array.from(document.querySelectorAll(".reader-page[data-loaded='true']"));
  if (!pages.length) {
    statusLine.textContent = "Aucune image chargee. Attends le chargement, descends un peu, ou choisis une capture.";
    return;
  }

  let translatedPages = 0;
  for (const [index, page] of pages.entries()) {
    const pageOverlay = page.querySelector(".overlay");
    const imageUrl = page.dataset.sourceUrl || "";
    if (!pageOverlay || !imageUrl) continue;

    renderNotice(pageOverlay, `OCR ${index + 1}/${pages.length}...`);
    statusLine.textContent = `OCR + traduction image ${index + 1}/${pages.length}...`;

    const ocr = await ocrImage({ imageUrl, referer: currentPageUrl, language: ocrLanguage.value });
    if (!ocr.length) {
      renderNotice(pageOverlay, "Aucun texte detecte");
      continue;
    }

    const translated = await translateSegments(ocr);
    renderIntoOverlay(pageOverlay, translated);
    translatedPages += 1;
  }

  statusLine.textContent = translatedPages
    ? `OK: ${translatedPages} images traduites avec OCR local.`
    : "OCR termine, mais aucun texte lisible n'a ete detecte.";
}

async function translateCapture() {
  if (!currentCaptureDataUrl) {
    statusLine.textContent = "Choisis une capture avant de traduire.";
    return;
  }

  renderNotice(overlay, "OCR...");
  statusLine.textContent = "OCR + traduction de la capture...";
  const ocr = await ocrImage({ imageData: currentCaptureDataUrl, language: ocrLanguage.value });
  if (!ocr.length) {
    renderNotice(overlay, "Aucun texte detecte");
    statusLine.textContent = "OCR termine, mais aucun texte lisible n'a ete detecte.";
    return;
  }

  const translated = await translateSegments(ocr);
  renderIntoOverlay(overlay, translated);
  statusLine.textContent = `OK: ${translated.length} lignes traduites avec OCR local.`;
}

async function ocrImage(payload) {
  const result = await postJSON("/v1/webtoon/ocr", payload);
  return result.segments || [];
}

async function translateSegments(segments) {
  const payload = await postJSON("/v1/webtoon/translate", {
    sourceLanguage: ocrLanguage.value,
    targetLanguage: "fr",
    seriesID: "phone-preview",
    style: "Traduction naturelle en francais, adaptee aux webtoons. Garde les noms propres et les pouvoirs coherents.",
    glossary: [
      { id: "astra", source: "Astra", translation: "Astra", category: "power", isLocked: true },
      { id: "north-blade", source: "Lame du nord", translation: "Lame du Nord", category: "power", isLocked: true }
    ],
    segments
  });
  return payload.segments || [];
}

async function postJSON(path, payload) {
  const response = await fetch(`${backendBaseUrl()}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const message = await readError(response);
    throw new Error(message || `Backend ${response.status}`);
  }
  return response.json();
}

function backendBaseUrl() {
  return (backendUrl.value.trim() || window.location.origin).replace(/\/$/, "");
}

function renderIntoOverlay(targetOverlay, segments) {
  targetOverlay.innerHTML = "";

  for (const segment of segments) {
    const box = segment.boundingBox || { x: 0.12, y: 0.16, width: 0.52, height: 0.1 };
    const translatedText = formatBubbleText(segment.translatedText || segment.text || "");
    const bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.dataset.shape = segment.shape || guessBubbleShape(box);
    bubble.textContent = translatedText;
    bubble.title = segment.sourceText || "";
    bubble.style.left = `${box.x * 100}%`;
    bubble.style.top = `${box.y * 100}%`;
    bubble.style.width = `${Math.max(0.18, box.width) * 100}%`;
    bubble.style.height = `${Math.max(44, box.height * targetOverlay.clientHeight)}px`;
    bubble.style.fontSize = `${fontSizeForBox(box, targetOverlay, translatedText)}px`;
    applyBubbleStyle(bubble, segment.style);
    targetOverlay.appendChild(bubble);
  }
}

function guessBubbleShape(box) {
  return box.width / Math.max(0.001, box.height) > 1.35 ? "ellipse" : "rounded";
}

function fontSizeForBox(box, targetOverlay, text) {
  const normalized = text.replace(/\s+/g, " ").trim();
  const length = normalized.length;
  const pixelWidth = Math.max(80, box.width * targetOverlay.clientWidth);
  const pixelHeight = box.height * targetOverlay.clientHeight;
  const maxSize = pixelHeight >= 150 ? 20 : pixelHeight >= 105 ? 18 : pixelHeight >= 72 ? 16 : 13;
  const minSize = 10;

  for (let size = maxSize; size >= minSize; size -= 1) {
    const charsPerLine = Math.max(8, Math.floor(pixelWidth / (size * 0.58)));
    const explicitLines = text.split("\n").reduce((total, line) => {
      const lineLength = line.replace(/\s+/g, " ").trim().length;
      return total + Math.max(1, Math.ceil(lineLength / charsPerLine));
    }, 0);
    const neededHeight = explicitLines * size * 1.16;
    if (neededHeight <= pixelHeight * 0.68 && length / charsPerLine <= 5.2) {
      return size;
    }
  }

  return minSize;
}

function formatBubbleText(text) {
  return text
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\s+([?!:;])/g, "\u00a0$1")
    .replace(/([?!])\s+([A-Z\u00c0-\u00d6\u00d8-\u00dd])/g, "$1\n$2");
}

function applyBubbleStyle(bubble, style) {
  if (!style || typeof style !== "object") return;

  if (style.fillColor) bubble.style.backgroundColor = style.fillColor;
  if (style.textColor) bubble.style.color = style.textColor;
  if (style.borderColor) bubble.style.borderColor = style.borderColor;
}

function renderNotice(targetOverlay, text) {
  targetOverlay.innerHTML = "";

  const notice = document.createElement("div");
  notice.className = "ocr-notice";
  notice.textContent = text;
  targetOverlay.appendChild(notice);
}

function updateReaderStatus(total) {
  const pending = Math.max(0, total - loadedImages - failedImages);
  const chunks = [`${loadedImages}/${total} images chargees`];
  if (pending) chunks.push(`${pending} en attente`);
  if (failedImages) chunks.push(`${failedImages} bloquees`);
  readerSummary.textContent = chunks.join(" - ");

  if (failedImages && loadedImages === 0) {
    statusLine.textContent = "Toutes les images sont bloquees par le site ou le reseau. Essaie un autre lien ou une capture.";
    return;
  }

  statusLine.textContent = "Images visibles dans le lecteur. Appuie sur Traduire pour OCR + traduction locale.";
}

function resetReaderCounters() {
  loadedImages = 0;
  failedImages = 0;
}

async function loadCapabilities() {
  try {
    const response = await fetch("/v1/webtoon/capabilities");
    if (!response.ok) throw new Error(`Capabilities ${response.status}`);
    const capabilities = await response.json();
    if (capabilities.ocr && capabilities.translation) {
      capabilityLine.textContent = capabilities.ollamaModel
        ? `OCR + Qwen local prets (${capabilities.ollamaModel}).`
        : "OCR EasyOCR/Tesseract + traduction locale prets.";
    } else if (capabilities.ocr) {
      capabilityLine.textContent = "OCR local pret. Traduction locale non installee.";
    } else {
      capabilityLine.textContent = "Preview web: lecteur d'images OK, OCR/IA non connectee.";
    }
  } catch {
    capabilityLine.textContent = "Preview web locale. OCR/IA non connectee.";
  }
}

async function readError(response) {
  try {
    const payload = await response.json();
    return payload.error || payload.message || "";
  } catch {
    try {
      return await response.text();
    } catch {
      return "";
    }
  }
}
