const translatedImages = new WeakMap();
let autoMode = false;
let scanTimer = null;

browser.storage.local.get({ autoMode: false }).then((settings) => {
  autoMode = Boolean(settings.autoMode);
  if (autoMode) scheduleScan();
});

browser.runtime.onMessage.addListener((message) => {
  if (message && message.type === "translateVisibleImages") {
    translateVisibleImages();
    return Promise.resolve({ ok: true });
  }
  return undefined;
});

window.addEventListener("scroll", () => {
  updateOverlayPositions();
  if (autoMode) scheduleScan();
}, { passive: true });

window.addEventListener("resize", updateOverlayPositions, { passive: true });

const observer = new MutationObserver(() => {
  updateOverlayPositions();
  if (autoMode) scheduleScan();
});
observer.observe(document.documentElement, { childList: true, subtree: true });

function scheduleScan() {
  clearTimeout(scanTimer);
  scanTimer = setTimeout(translateVisibleImages, 180);
}

function translateVisibleImages() {
  const images = Array.from(document.images).filter(isCandidateImage);
  for (const image of images) {
    translateImage(image);
  }
}

function isCandidateImage(image) {
  const rect = image.getBoundingClientRect();
  const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
  const viewportWidth = window.innerWidth || document.documentElement.clientWidth;
  const visible = rect.bottom > -viewportHeight && rect.top < viewportHeight * 2 &&
    rect.right > 0 && rect.left < viewportWidth;
  const bigEnough = rect.width >= 160 && rect.height >= 120 &&
    image.naturalWidth >= 160 && image.naturalHeight >= 120;
  const hasSource = Boolean(image.currentSrc || image.src);
  return visible && bigEnough && hasSource;
}

async function translateImage(image) {
  const existing = translatedImages.get(image);
  if (existing && (existing.status === "loading" || existing.status === "done")) {
    return;
  }

  const overlay = ensureOverlay(image);
  overlay.classList.add("webtoon-lens-loading");
  overlay.textContent = "Traduction...";
  translatedImages.set(image, { status: "loading", overlay });
  positionOverlay(image, overlay);

  try {
    const response = await browser.runtime.sendMessage({
      type: "translateImage",
      imageURL: image.currentSrc || image.src,
      pageURL: location.href,
      naturalWidth: image.naturalWidth,
      naturalHeight: image.naturalHeight,
      targetLanguage: "fr"
    });

    if (!response || response.ok === false) {
      throw new Error(response && response.error ? response.error : "Erreur de traduction.");
    }

    renderSegments(image, overlay, response.segments || []);
    translatedImages.set(image, { status: "done", overlay });
  } catch (error) {
    overlay.classList.remove("webtoon-lens-loading");
    overlay.classList.add("webtoon-lens-error");
    overlay.textContent = error && error.message ? error.message : String(error);
    translatedImages.set(image, { status: "error", overlay });
  }
}

function ensureOverlay(image) {
  const existing = translatedImages.get(image);
  if (existing && existing.overlay) {
    return existing.overlay;
  }

  const overlay = document.createElement("div");
  overlay.className = "webtoon-lens-overlay";
  overlay.setAttribute("aria-live", "polite");
  document.documentElement.appendChild(overlay);
  return overlay;
}

function renderSegments(image, overlay, segments) {
  overlay.classList.remove("webtoon-lens-loading", "webtoon-lens-error");
  overlay.textContent = "";
  positionOverlay(image, overlay);

  for (const segment of segments) {
    const box = segment.boundingBox;
    if (!box) continue;

    const bubble = document.createElement("div");
    bubble.className = "webtoon-lens-bubble";
    bubble.textContent = segment.translatedText || "";
    bubble.style.left = `${box.x * 100}%`;
    bubble.style.top = `${box.y * 100}%`;
    bubble.style.width = `${Math.max(12, box.width * 100)}%`;
    bubble.style.minHeight = `${Math.max(28, box.height * overlay.clientHeight)}px`;
    overlay.appendChild(bubble);
  }
}

function updateOverlayPositions() {
  for (const image of Array.from(document.images)) {
    const state = translatedImages.get(image);
    if (state && state.overlay) {
      positionOverlay(image, state.overlay);
    }
  }
}

function positionOverlay(image, overlay) {
  const rect = image.getBoundingClientRect();
  overlay.style.left = `${rect.left + window.scrollX}px`;
  overlay.style.top = `${rect.top + window.scrollY}px`;
  overlay.style.width = `${rect.width}px`;
  overlay.style.height = `${rect.height}px`;
  overlay.style.display = rect.width > 0 && rect.height > 0 ? "block" : "none";
}
