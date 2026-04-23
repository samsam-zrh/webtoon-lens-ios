const imageInput = document.getElementById("imageInput");
const previewImage = document.getElementById("previewImage");
const emptyState = document.getElementById("emptyState");
const overlay = document.getElementById("overlay");
const stage = document.getElementById("stage");
const imageReader = document.getElementById("imageReader");
const backendUrl = document.getElementById("backendUrl");
const statusLine = document.getElementById("statusLine");
const webtoonUrl = document.getElementById("webtoonUrl");
const openUrlButton = document.getElementById("openUrlButton");
const capabilityLine = document.getElementById("capabilityLine");
const readerSummary = document.getElementById("readerSummary");
const ocrLanguage = document.getElementById("ocrLanguage");
const prevChapterButton = document.getElementById("prevChapterButton");
const nextChapterButton = document.getElementById("nextChapterButton");
const chapterHint = document.getElementById("chapterHint");

const OCR_WINDOW_MARGIN_BEFORE = 0.12;
const OCR_WINDOW_MARGIN_AFTER = 0.42;
const OCR_WINDOW_MAX_NATURAL_HEIGHT = 2500;
const OCR_WINDOW_COVERAGE_THRESHOLD = 0.72;
const OCR_WINDOWS_PER_PASS = 4;
const OCR_VIEWPORT_FOCI = [0.48, 0.72, 0.96, 1.14];
const OCR_WINDOW_DEDUPE_THRESHOLD = 0.66;
const AUTO_TRANSLATE_DELAY_MS = 90;
const TRANSLATION_PAGES_PER_PASS = 1;
const BACKGROUND_TRANSLATION_PAGE_LIMIT = 3;
const BACKGROUND_TRANSLATION_VIEWPORTS = 5.5;

backendUrl.value = localStorage.getItem("webtoonLensBackend") || window.location.origin;
webtoonUrl.value = localStorage.getItem("webtoonLensUrl") || "";
ocrLanguage.value = localStorage.getItem("webtoonLensOcrLanguage") || "auto";

let loadedImages = 0;
let failedImages = 0;
let currentPageUrl = "";
let currentCaptureDataUrl = "";
let autoTranslateEnabled = false;
let translateScrollTimer = 0;
let contentSessionId = 0;
let chapterNavigation = { previousUrl: "", nextUrl: "", currentLabel: "" };

if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("./sw.js").catch(() => {});
}

loadCapabilities();
updateChapterNavigation(webtoonUrl.value);
window.addEventListener("scroll", scheduleAutoTranslate, { passive: true });
window.addEventListener("resize", scheduleAutoTranslate);

if (imageInput) {
  imageInput.addEventListener("change", () => {
    const file = imageInput.files && imageInput.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      prepareCapture(String(reader.result || ""));
    };
    reader.readAsDataURL(file);
  });
}

openUrlButton.addEventListener("click", () => {
  openWebtoonUrl().catch((error) => {
    statusLine.textContent = error && error.message ? error.message : String(error);
  });
});
webtoonUrl.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    openWebtoonUrl().catch((error) => {
      statusLine.textContent = error && error.message ? error.message : String(error);
    });
  }
});
webtoonUrl.addEventListener("input", () => {
  updateChapterNavigation(webtoonUrl.value);
});

backendUrl.addEventListener("input", () => {
  localStorage.setItem("webtoonLensBackend", backendUrl.value.trim());
});

ocrLanguage.addEventListener("change", () => {
  localStorage.setItem("webtoonLensOcrLanguage", ocrLanguage.value);
});

prevChapterButton.addEventListener("click", () => {
  navigateChapter(-1).catch((error) => {
    statusLine.textContent = error && error.message ? error.message : String(error);
  });
});
nextChapterButton.addEventListener("click", () => {
  navigateChapter(1).catch((error) => {
    statusLine.textContent = error && error.message ? error.message : String(error);
  });
});

async function openWebtoonUrl(urlOverride = "") {
  const value = normalizedUrlValue(urlOverride || webtoonUrl.value);
  if (!value) {
    statusLine.textContent = "Colle d'abord un lien.";
    return;
  }

  setOpenButtonBusy(true);
  readerSummary.textContent = "";
  statusLine.textContent = "Ouverture du chapitre, extraction des images et prechauffe de la traduction...";

  try {
    warmupLocalModel();
    webtoonUrl.value = value;
    localStorage.setItem("webtoonLensUrl", value);
    currentPageUrl = value;
    currentCaptureDataUrl = "";
    updateChapterNavigation(value);

    const response = await fetch(`/v1/webtoon/extract?url=${encodeURIComponent(value)}`);
    if (!response.ok) {
      const message = await readError(response);
      throw new Error(message || `Extraction impossible (${response.status})`);
    }
    const payload = await response.json();
    renderImageFeed(payload.images || []);
  } catch (error) {
    statusLine.textContent = error && error.message ? error.message : String(error);
  } finally {
    setOpenButtonBusy(false);
  }
}

function normalizedUrlValue(rawValue) {
  const value = String(rawValue || "").trim();
  if (!value) return "";
  return value.includes("://") ? value : `https://${value}`;
}

function beginContentSession() {
  contentSessionId += 1;
  window.clearTimeout(translateScrollTimer);
  return contentSessionId;
}

function isStaleSession(sessionId) {
  return sessionId !== contentSessionId;
}

function setOpenButtonBusy(isBusy) {
  openUrlButton.disabled = isBusy;
  openUrlButton.textContent = isBusy ? "Ouverture..." : "Ouvrir";
  prevChapterButton.disabled = isBusy || !chapterNavigation.previousUrl;
  nextChapterButton.disabled = isBusy || !chapterNavigation.nextUrl;
}

function prepareCapture(dataUrl) {
  const sessionId = beginContentSession();
  resetReaderCounters();
  autoTranslateEnabled = false;
  stage.classList.remove("feed-mode");
  imageReader.innerHTML = "";
  overlay.innerHTML = "";
  currentPageUrl = "";
  currentCaptureDataUrl = dataUrl;
  previewImage.src = currentCaptureDataUrl;
  previewImage.style.display = "block";
  emptyState.style.display = "none";
  readerSummary.textContent = "Capture chargee depuis ton telephone.";
  statusLine.textContent = "Capture chargee. OCR + traduction locale en cours...";
  runAutoCaptureTranslation(sessionId).catch((error) => {
    if (isStaleSession(sessionId)) return;
    statusLine.textContent = error && error.message ? error.message : String(error);
  });
}

async function runAutoCaptureTranslation(sessionId) {
  await waitForImageReady(previewImage);
  await nextFrame();
  await nextFrame();
  if (isStaleSession(sessionId)) return;
  await translateCapture(sessionId);
}

async function navigateChapter(direction) {
  const targetUrl = direction < 0 ? chapterNavigation.previousUrl : chapterNavigation.nextUrl;
  if (!targetUrl) return;
  window.scrollTo({ top: 0, behavior: "smooth" });
  await openWebtoonUrl(targetUrl);
}

function updateChapterNavigation(rawValue) {
  chapterNavigation = deriveChapterNavigation(rawValue);
  prevChapterButton.disabled = !chapterNavigation.previousUrl || openUrlButton.disabled;
  nextChapterButton.disabled = !chapterNavigation.nextUrl || openUrlButton.disabled;
  chapterHint.textContent = chapterNavigation.currentLabel || "Colle un lien de chapitre pour activer la navigation rapide.";
}

function deriveChapterNavigation(rawValue) {
  const normalized = normalizedUrlValue(rawValue);
  if (!normalized) {
    return { previousUrl: "", nextUrl: "", currentLabel: "" };
  }

  try {
    const parsed = new URL(normalized);
    const pathMatch = lastNumericMatch(parsed.pathname);
    if (pathMatch) {
      const chapterNumber = Number(pathMatch[0]);
      return {
        previousUrl: chapterNumber > 1 ? buildSteppedUrl(parsed, "pathname", pathMatch, chapterNumber - 1) : "",
        nextUrl: buildSteppedUrl(parsed, "pathname", pathMatch, chapterNumber + 1),
        currentLabel: `Chapitre ${chapterNumber} detecte.`
      };
    }

    const searchMatch = lastNumericMatch(parsed.search);
    if (searchMatch) {
      const chapterNumber = Number(searchMatch[0]);
      return {
        previousUrl: chapterNumber > 1 ? buildSteppedUrl(parsed, "search", searchMatch, chapterNumber - 1) : "",
        nextUrl: buildSteppedUrl(parsed, "search", searchMatch, chapterNumber + 1),
        currentLabel: `Episode ${chapterNumber} detecte.`
      };
    }
  } catch {
    return { previousUrl: "", nextUrl: "", currentLabel: "Lien invalide." };
  }

  return {
    previousUrl: "",
    nextUrl: "",
    currentLabel: "Navigation rapide indisponible sur ce lien."
  };
}

function lastNumericMatch(text) {
  const matches = Array.from(String(text || "").matchAll(/\d+/g));
  return matches[matches.length - 1] || null;
}

function buildSteppedUrl(parsedUrl, property, match, targetNumber) {
  const clone = new URL(parsedUrl.toString());
  const source = clone[property];
  const padded = String(targetNumber).padStart(String(match[0]).length, "0");
  clone[property] = `${source.slice(0, match.index)}${padded}${source.slice(match.index + match[0].length)}`;
  return clone.toString();
}

function waitForImageReady(image) {
  if (image.complete && image.naturalWidth > 0) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const onLoad = () => {
      cleanup();
      resolve();
    };
    const onError = () => {
      cleanup();
      reject(new Error("Image impossible a charger."));
    };
    const cleanup = () => {
      image.removeEventListener("load", onLoad);
      image.removeEventListener("error", onError);
    };
    image.addEventListener("load", onLoad, { once: true });
    image.addEventListener("error", onError, { once: true });
  });
}

function nextFrame() {
  return new Promise((resolve) => window.requestAnimationFrame(() => resolve()));
}

function renderImageFeed(images) {
  const sessionId = beginContentSession();
  resetReaderCounters();
  autoTranslateEnabled = true;
  stage.classList.add("feed-mode");
  previewImage.style.display = "none";
  overlay.innerHTML = "";
  imageReader.innerHTML = "";

  if (!images.length) {
    emptyState.style.display = "grid";
    emptyState.querySelector("strong").textContent = "Aucune image trouvee";
    emptyState.querySelector("span").textContent = "Certains sites chargent les images avec JavaScript, demandent une connexion, ou bloquent le proxy local.";
    readerSummary.textContent = "0 image extraite.";
    statusLine.textContent = "Essaie un lien direct d'episode avec images publiques.";
    return;
  }

  emptyState.style.display = "none";
  for (const [index, image] of images.entries()) {
    const page = document.createElement("article");
    page.className = "reader-page";
    page.dataset.index = String(index);
    page.dataset.sourceUrl = image.url;
    page.dataset.sessionId = String(sessionId);

    const badge = document.createElement("div");
    badge.className = "page-badge";
    badge.textContent = `Image ${index + 1}`;

    const img = document.createElement("img");
    img.src = proxyImageUrl(image.url);
    img.alt = image.alt || `Image webtoon ${index + 1}`;
    img.loading = index < 3 ? "eager" : "lazy";
    img.decoding = "async";
    img.fetchPriority = index < 2 ? "high" : "auto";
    img.addEventListener("load", () => {
      if (isStaleSession(sessionId)) return;
      loadedImages += 1;
      page.dataset.loaded = "true";
      updateReaderStatus(images.length);
    });
    img.addEventListener("error", () => {
      if (isStaleSession(sessionId)) return;
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
  statusLine.textContent = "Le lecteur charge le chapitre. La traduction se lance et continuera automatiquement.";
  scheduleAutoTranslate();
}

function proxyImageUrl(url) {
  const params = new URLSearchParams({ url });
  if (currentPageUrl) params.set("referer", currentPageUrl);
  return `/v1/webtoon/image?${params.toString()}`;
}

async function translateReaderImages() {
  const sessionId = contentSessionId;
  autoTranslateEnabled = true;
  const pages = readerPagesForTranslation().filter((page) => pageNeedsTranslation(page)).slice(0, TRANSLATION_PAGES_PER_PASS);
  if (!pages.length) {
    if (!loadedImages && !failedImages) {
      statusLine.textContent = "Chargement des premieres images...";
      return;
    }
    const running = document.querySelector(".reader-page[data-translation-state='running']");
    statusLine.textContent = running
      ? "Traduction en cours..."
      : "Les premieres zones sont pretes. Continue a lire, la suite partira toute seule.";
    return;
  }

  let translatedPages = 0;
  for (const [index, page] of pages.entries()) {
    if (isStaleSession(sessionId)) return;
    const translated = await translatePageProgressively(page, index + 1, pages.length, sessionId);
    if (translated) translatedPages += 1;
  }

  if (isStaleSession(sessionId)) return;
  statusLine.textContent = translatedPages
    ? `OK: ${translatedPages} image(s) avancee(s). La traduction continue en fond.`
    : "Analyse en cours. La traduction avance zone par zone.";
  scheduleAutoTranslate();
}

async function translatePageProgressively(page, pageNumber, totalPages, sessionId = contentSessionId) {
  const pageOverlay = page.querySelector(".overlay");
  const imageUrl = page.dataset.sourceUrl || "";
  if (!pageOverlay || !imageUrl) return false;
  if (page.dataset.translationState === "running") return false;
  if (isStaleSession(sessionId) || !page.isConnected) return false;

  let crop = await visibleImageCrop(page);
  if (!crop || visibleWindowAlreadyCovered(page, crop.window)) return false;

  page.dataset.translationState = "running";
  showOverlayNotice(pageOverlay, `OCR zone ${Number(page.dataset.index || "0") + 1}...`);
  statusLine.textContent = `OCR zone visible ${pageNumber}/${totalPages}...`;

  try {
    const previousTranslations = page.__previousTranslations || [];
    let translatedCount = 0;
    let processedWindows = 0;

    while (crop && processedWindows < OCR_WINDOWS_PER_PASS) {
      if (isStaleSession(sessionId) || !page.isConnected) return false;
      showOverlayNotice(pageOverlay, `OCR zone ${Number(page.dataset.index || "0") + 1}...`);
      statusLine.textContent = `OCR zone visible ${pageNumber}/${totalPages}...`;

      const cropOcr = await ocrImage({
        imageData: crop.dataUrl,
        language: ocrLanguage.value,
        cacheKey: `${imageUrl}:${crop.cacheKey}`
      });
      const ocr = mapCropSegmentsToPage(cropOcr, crop, page);
      rememberProcessedWindow(page, crop.window);
      clearOverlayNotice(pageOverlay);
      processedWindows += 1;

      if (ocr.length) {
        page.__ocrSegments = mergeSegmentLists(page.__ocrSegments || [], ocr);
        const freshSegments = newSegmentsForPage(page, ocr);
        if (freshSegments.length) {
          const contextSegments = contextForSegments(page.__ocrSegments);

          for (let segmentIndex = 0; segmentIndex < freshSegments.length;) {
            if (isStaleSession(sessionId) || !page.isConnected) return false;
            const batchSize = segmentIndex === 0 ? 1 : progressiveBatchSize(freshSegments.length - segmentIndex);
            const batch = freshSegments.slice(segmentIndex, segmentIndex + batchSize);
            const endIndex = segmentIndex + batch.length;
            statusLine.textContent = `Traduction bulle ${segmentIndex + 1}/${freshSegments.length} - image ${Number(page.dataset.index || "0") + 1}...`;
            const translated = await translateSegments(batch, contextSegments, previousTranslations);

            for (const segment of translated) {
              renderSegmentIntoOverlay(pageOverlay, segment);
              rememberTranslatedSegment(page, segment);
              previousTranslations.push({
                source: segment.sourceText || "",
                translation: segment.translatedText || ""
              });
              translatedCount += 1;
            }
            segmentIndex = endIndex;
          }
        }
      }

      crop = await visibleImageCrop(page);
    }

    if (isStaleSession(sessionId) || !page.isConnected) return false;
    page.__previousTranslations = previousTranslations.slice(-14);
    if (!translatedCount && !pageOverlay.querySelector(".bubble")) {
      showOverlayNotice(pageOverlay, "Aucun texte detecte ici");
    }
    page.dataset.translationState = pageFullyCovered(page) ? "done" : "idle";
    return translatedCount > 0;
  } catch (error) {
    page.dataset.translationState = "error";
    showOverlayNotice(pageOverlay, error && error.message ? error.message : String(error));
    return false;
  } finally {
    scheduleAutoTranslate();
  }
}

function pageNeedsTranslation(page) {
  if (page.dataset.loaded !== "true" || page.dataset.translationState === "running" || page.dataset.translationState === "done") {
    return false;
  }

  return translationWindowCandidates(page).some((cropWindow) => !visibleWindowAlreadyCovered(page, cropWindow));
}

function currentVisibleWindow(page) {
  return currentVisibleWindows(page)[0] || null;
}

function currentVisibleWindows(page) {
  const img = page.querySelector("img");
  if (!img || !img.complete || !img.naturalWidth || !img.naturalHeight) return [];

  const rect = img.getBoundingClientRect();
  if (rect.bottom <= 0 || rect.top >= window.innerHeight) {
    const preloadMargin = window.innerHeight * 1.8;
    if (rect.bottom < -preloadMargin || rect.top > window.innerHeight + preloadMargin) return [];
  }

  const before = window.innerHeight * OCR_WINDOW_MARGIN_BEFORE;
  const after = window.innerHeight * OCR_WINDOW_MARGIN_AFTER;
  let topCss = Math.max(0, -rect.top - before);
  let bottomCss = Math.min(rect.height, window.innerHeight - rect.top + after);
  if (bottomCss <= topCss + 24) return [];

  const scaleY = img.naturalHeight / Math.max(1, rect.height);
  const maxCssHeight = OCR_WINDOW_MAX_NATURAL_HEIGHT / Math.max(0.001, scaleY);
  if (bottomCss - topCss <= maxCssHeight) {
    return [normalizedWindow(topCss, bottomCss, rect.height)];
  }

  const focusWindows = OCR_VIEWPORT_FOCI.map((viewportRatio) => {
    const focusCss = Math.min(rect.height, Math.max(0, -rect.top + window.innerHeight * viewportRatio));
    const focusedTop = Math.max(0, Math.min(focusCss - maxCssHeight * 0.56, rect.height - maxCssHeight));
    return normalizedWindow(focusedTop, Math.min(rect.height, focusedTop + maxCssHeight), rect.height);
  });

  return uniqueWindows(focusWindows);
}

function normalizedWindow(topCss, bottomCss, imageCssHeight) {
  return {
    y: clamp01(topCss / Math.max(1, imageCssHeight)),
    height: clamp01((bottomCss - topCss) / Math.max(1, imageCssHeight))
  };
}

function uniqueWindows(windows) {
  const unique = [];
  for (const cropWindow of windows) {
    if (!unique.some((existing) => coveredRatio(cropWindow, [existing]) > OCR_WINDOW_DEDUPE_THRESHOLD)) {
      unique.push(cropWindow);
    }
  }
  return unique;
}

function translationWindowCandidates(page) {
  const visible = currentVisibleWindows(page).filter((candidate) => !visibleWindowAlreadyCovered(page, candidate));
  if (visible.length) return visible;
  return backgroundWindowCandidates(page).filter((candidate) => !visibleWindowAlreadyCovered(page, candidate));
}

function backgroundWindowCandidates(page) {
  if (!pageEligibleForBackgroundTranslation(page)) return [];
  const nextWindow = nextSequentialWindow(page);
  return nextWindow ? [nextWindow] : [];
}

function pageEligibleForBackgroundTranslation(page) {
  const pageIndex = Number(page.dataset.index || "0");
  if (pageIndex < BACKGROUND_TRANSLATION_PAGE_LIMIT) return true;
  const rect = page.getBoundingClientRect();
  return rect.top <= window.innerHeight * BACKGROUND_TRANSLATION_VIEWPORTS;
}

function nextSequentialWindow(page) {
  const img = page.querySelector("img");
  if (!img || !img.naturalHeight) return null;

  const merged = mergeWindows(page.__ocrWindows || []);
  const normalizedMaxHeight = clamp01(OCR_WINDOW_MAX_NATURAL_HEIGHT / Math.max(1, img.naturalHeight));
  const minimumGap = Math.max(0.03, normalizedMaxHeight * 0.32);
  let cursor = 0;

  for (const windowRange of merged) {
    if (windowRange.y - cursor > minimumGap) {
      break;
    }
    cursor = Math.max(cursor, windowRange.y + windowRange.height);
  }

  if (cursor >= 0.985) return null;
  const height = Math.min(1 - cursor, Math.max(0.08, normalizedMaxHeight));
  return {
    y: clamp01(cursor),
    height: clamp01(height)
  };
}

async function visibleImageCrop(page) {
  const img = page.querySelector("img");
  const cropWindow = translationWindowCandidates(page)[0];
  if (!img || !cropWindow) return null;

  const cropY = Math.max(0, Math.floor(cropWindow.y * img.naturalHeight));
  const cropHeight = Math.max(1, Math.min(img.naturalHeight - cropY, Math.ceil(cropWindow.height * img.naturalHeight)));
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = cropHeight;

  const context = canvas.getContext("2d", { willReadFrequently: false });
  if (!context) return null;
  context.drawImage(img, 0, cropY, img.naturalWidth, cropHeight, 0, 0, img.naturalWidth, cropHeight);

  return {
    dataUrl: canvas.toDataURL("image/jpeg", 0.88),
    cacheKey: `${Math.round(cropWindow.y * 10000)}-${Math.round((cropWindow.y + cropWindow.height) * 10000)}`,
    window: {
      y: cropY / img.naturalHeight,
      height: cropHeight / img.naturalHeight
    },
    imageWidth: img.naturalWidth,
    imageHeight: img.naturalHeight
  };
}

function mapCropSegmentsToPage(segments, crop, page) {
  const pageIndex = Number(page.dataset.index || "0");
  return segments.map((segment, index) => {
    const box = segment.boundingBox || { x: 0, y: 0, width: 0, height: 0 };
    const fullBox = {
      x: clamp01(Number(box.x || 0)),
      y: clamp01(crop.window.y + Number(box.y || 0) * crop.window.height),
      width: clamp01(Number(box.width || 0)),
      height: clamp01(Number(box.height || 0) * crop.window.height)
    };
    return {
      ...segment,
      id: `p${pageIndex}-${crop.cacheKey}-${segment.id || index}`,
      boundingBox: fullBox,
      rawBoundingBox: fullBox,
      readingOrder: Math.round(fullBox.y * 100000) + index,
      cropWindow: crop.window
    };
  });
}

function mergeSegmentLists(existing, incoming) {
  const bySignature = new Map();
  for (const segment of [...existing, ...incoming]) {
    bySignature.set(segmentSignature(segment), segment);
  }
  return Array.from(bySignature.values()).sort((a, b) => Number(a.readingOrder || 0) - Number(b.readingOrder || 0));
}

function newSegmentsForPage(page, segments) {
  page.__translatedSegmentSignatures ||= new Set();
  return segments.filter((segment) => !page.__translatedSegmentSignatures.has(segmentSignature(segment)));
}

function rememberTranslatedSegment(page, segment) {
  page.__translatedSegmentSignatures ||= new Set();
  page.__translatedSegmentSignatures.add(segmentSignature(segment));
}

function rememberProcessedWindow(page, cropWindow) {
  page.__ocrWindows = mergeWindows([...(page.__ocrWindows || []), cropWindow]);
}

function visibleWindowAlreadyCovered(page, cropWindow) {
  const windows = page.__ocrWindows || [];
  return coveredRatio(cropWindow, windows) >= OCR_WINDOW_COVERAGE_THRESHOLD;
}

function pageFullyCovered(page) {
  return coveredRatio({ y: 0, height: 1 }, page.__ocrWindows || []) > 0.94;
}

function coveredRatio(target, windows) {
  const targetStart = target.y;
  const targetEnd = target.y + target.height;
  let covered = 0;

  for (const windowRange of mergeWindows(windows)) {
    const start = Math.max(targetStart, windowRange.y);
    const end = Math.min(targetEnd, windowRange.y + windowRange.height);
    if (end > start) covered += end - start;
  }

  return covered / Math.max(0.0001, target.height);
}

function mergeWindows(windows) {
  const sorted = windows
    .filter((windowRange) => windowRange && windowRange.height > 0.001)
    .map((windowRange) => ({ y: clamp01(windowRange.y), height: clamp01(windowRange.height) }))
    .sort((a, b) => a.y - b.y);
  const merged = [];

  for (const windowRange of sorted) {
    const last = merged[merged.length - 1];
    if (!last || windowRange.y > last.y + last.height + 0.015) {
      merged.push({ ...windowRange });
      continue;
    }
    const end = Math.max(last.y + last.height, windowRange.y + windowRange.height);
    last.height = clamp01(end - last.y);
  }

  return merged;
}

function segmentSignature(segment) {
  const box = segment.boundingBox || {};
  const source = String(segment.sourceText || segment.text || "")
    .toLowerCase()
    .replace(/[^a-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+/g, "")
    .slice(0, 90);
  if (source.length >= 18) return source;
  return [
    source,
    Math.round(Number(box.x || 0) * 40),
    Math.round(Number(box.y || 0) * 20),
    Math.round(Number(box.width || 0) * 30)
  ].join(":");
}

function clamp01(value) {
  return Math.min(1, Math.max(0, Number(value) || 0));
}

function readerPagesForTranslation() {
  const pages = Array.from(document.querySelectorAll(".reader-page"))
    .filter((page) => page.dataset.loaded === "true")
    .sort((a, b) => Number(a.dataset.index || "0") - Number(b.dataset.index || "0"));
  const margin = window.innerHeight * 2.05;
  const visiblePages = pages.filter((page) => {
    const rect = page.getBoundingClientRect();
    return rect.bottom >= -margin && rect.top <= window.innerHeight + margin;
  });
  const backgroundPages = pages.filter((page) => !visiblePages.includes(page) && pageEligibleForBackgroundTranslation(page));

  return uniquePageList([...visiblePages, ...backgroundPages, ...pages.slice(0, BACKGROUND_TRANSLATION_PAGE_LIMIT)]);
}

function uniquePageList(pages) {
  const seen = new Set();
  return pages.filter((page) => {
    if (seen.has(page)) return false;
    seen.add(page);
    return true;
  });
}

function scheduleAutoTranslate() {
  if (!autoTranslateEnabled || !stage.classList.contains("feed-mode")) return;
  window.clearTimeout(translateScrollTimer);
  translateScrollTimer = window.setTimeout(() => {
    translateReaderImages().catch((error) => {
      statusLine.textContent = error && error.message ? error.message : String(error);
    });
  }, AUTO_TRANSLATE_DELAY_MS);
}

async function translateCapture(sessionId = contentSessionId) {
  if (!currentCaptureDataUrl) {
    statusLine.textContent = "Choisis une capture avant de traduire.";
    return;
  }

  renderNotice(overlay, "OCR...");
  statusLine.textContent = "OCR + traduction de la capture...";
  const ocr = await ocrImage({ imageData: currentCaptureDataUrl, language: ocrLanguage.value });
  if (isStaleSession(sessionId)) return;
  if (!ocr.length) {
    renderNotice(overlay, "Aucun texte detecte");
    statusLine.textContent = "OCR termine, mais aucun texte lisible n'a ete detecte.";
    return;
  }

  await translateOverlayProgressively(overlay, ocr, "capture", sessionId);
}

async function ocrImage(payload) {
  const result = await postJSON("/v1/webtoon/ocr", payload);
  return result.segments || [];
}

async function translateOverlayProgressively(targetOverlay, segments, label, sessionId = contentSessionId) {
  targetOverlay.innerHTML = "";
  const contextSegments = contextForSegments(segments);
  const previousTranslations = [];
  let translatedCount = 0;

  for (let index = 0; index < segments.length;) {
    if (isStaleSession(sessionId)) return;
    const batchSize = index === 0 ? 1 : progressiveBatchSize(segments.length - index);
    const batch = segments.slice(index, index + batchSize);
    const endIndex = index + batch.length;
    statusLine.textContent = `Traduction bulle ${index + 1}/${segments.length} - ${label}...`;
    const translated = await translateSegments(batch, contextSegments, previousTranslations);

    for (const segment of translated) {
      renderSegmentIntoOverlay(targetOverlay, segment);
      previousTranslations.push({
        source: segment.sourceText || "",
        translation: segment.translatedText || ""
      });
      translatedCount += 1;
    }
    index = endIndex;
  }

  if (isStaleSession(sessionId)) return;
  statusLine.textContent = translatedCount
    ? `OK: ${translatedCount} bulles traduites avec OCR local.`
    : "OCR termine, mais aucun texte lisible n'a ete traduit.";
}

async function translateSegments(segments, contextSegments = [], previousTranslations = []) {
  const payload = await postJSON("/v1/webtoon/translate", {
    sourceLanguage: ocrLanguage.value,
    targetLanguage: "fr",
    seriesID: "phone-preview",
    style: "Traduction naturelle en francais, adaptee aux webtoons. Garde les noms propres et les pouvoirs coherents.",
    glossary: [
      { id: "astra", source: "Astra", translation: "Astra", category: "power", isLocked: true },
      { id: "north-blade", source: "Lame du nord", translation: "Lame du Nord", category: "power", isLocked: true }
    ],
    contextSegments,
    previousTranslations,
    segments
  });
  return payload.segments || [];
}

function contextForSegments(segments) {
  return segments.map((segment, index) => ({
    id: segment.id || `segment-${index}`,
    order: Number(segment.readingOrder ?? index),
    text: segment.sourceText || segment.text || ""
  }));
}

function progressiveBatchSize(remaining) {
  if (remaining <= 2) return remaining;
  return remaining >= 8 ? 3 : 2;
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
    renderSegmentIntoOverlay(targetOverlay, segment);
  }
}

function renderSegmentIntoOverlay(targetOverlay, segment) {
  const existing = targetOverlay.querySelector(`[data-segment-id="${cssEscape(segment.id || "")}"]`);
  if (existing) existing.remove();
  removeOverlappingBubbles(targetOverlay, segment);

  const box = segment.boundingBox || { x: 0.12, y: 0.16, width: 0.52, height: 0.1 };
  const translatedText = formatBubbleText(segment.translatedText || segment.text || "");
  const bubble = document.createElement("div");
  bubble.className = "bubble";
  bubble.dataset.segmentId = segment.id || "";
  bubble.dataset.shape = segment.shape || guessBubbleShape(box);
  bubble.dataset.x = String(box.x);
  bubble.dataset.y = String(box.y);
  bubble.dataset.width = String(box.width);
  bubble.dataset.height = String(box.height);
  bubble.textContent = translatedText;
  bubble.title = segment.sourceText || "";
  bubble.style.left = `${box.x * 100}%`;
  bubble.style.top = `${box.y * 100}%`;
  bubble.style.width = `${Math.max(0.18, box.width) * 100}%`;
  bubble.style.height = `${Math.max(44, box.height * targetOverlay.clientHeight)}px`;
  bubble.style.fontSize = `${fontSizeForBox(box, targetOverlay, translatedText)}px`;
  bubble.dataset.length = translatedText.length > 72 ? "long" : "short";
  applyBubbleStyle(bubble, segment.style, segment.sourceText || "");
  targetOverlay.appendChild(bubble);
}

function removeOverlappingBubbles(targetOverlay, segment) {
  const box = segment.boundingBox;
  if (!box) return;

  for (const bubble of Array.from(targetOverlay.querySelectorAll(".bubble"))) {
    const existingBox = {
      x: Number(bubble.dataset.x || 0),
      y: Number(bubble.dataset.y || 0),
      width: Number(bubble.dataset.width || 0),
      height: Number(bubble.dataset.height || 0)
    };
    if (boxOverlapRatio(box, existingBox) > 0.58) {
      bubble.remove();
    }
  }
}

function boxOverlapRatio(a, b) {
  const ax2 = Number(a.x || 0) + Number(a.width || 0);
  const ay2 = Number(a.y || 0) + Number(a.height || 0);
  const bx2 = Number(b.x || 0) + Number(b.width || 0);
  const by2 = Number(b.y || 0) + Number(b.height || 0);
  const overlapWidth = Math.max(0, Math.min(ax2, bx2) - Math.max(Number(a.x || 0), Number(b.x || 0)));
  const overlapHeight = Math.max(0, Math.min(ay2, by2) - Math.max(Number(a.y || 0), Number(b.y || 0)));
  const overlap = overlapWidth * overlapHeight;
  const smallestArea = Math.min(
    Math.max(0.0001, Number(a.width || 0) * Number(a.height || 0)),
    Math.max(0.0001, Number(b.width || 0) * Number(b.height || 0))
  );
  return overlap / smallestArea;
}

function guessBubbleShape(box) {
  return box.width / Math.max(0.001, box.height) > 1.35 ? "ellipse" : "rounded";
}

function fontSizeForBox(box, targetOverlay, text) {
  const normalized = text.replace(/\s+/g, " ").trim();
  const length = normalized.length;
  const pixelWidth = Math.max(80, box.width * targetOverlay.clientWidth);
  const pixelHeight = box.height * targetOverlay.clientHeight;
  let maxSize = pixelHeight >= 150 ? 20 : pixelHeight >= 105 ? 18 : pixelHeight >= 72 ? 16 : 13;
  if (pixelWidth < 190) maxSize = Math.min(maxSize, 16);
  if (length > 34) maxSize = Math.min(maxSize, 17);
  if (length > 70) maxSize = Math.min(maxSize, 14);
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

function applyBubbleStyle(bubble, style, sourceText = "") {
  if (!style || typeof style !== "object") return;

  if (style.fillColor) bubble.style.backgroundColor = style.fillColor;
  if (style.textColor) bubble.style.color = style.textColor;
  if (style.borderColor) bubble.style.borderColor = style.borderColor;
  if (style.fontFamily) bubble.style.fontFamily = style.fontFamily;
  if (style.fontWeight) bubble.style.fontWeight = style.fontWeight;
  if (style.letterSpacing) bubble.style.letterSpacing = style.letterSpacing;
  if (style.textTransform) bubble.style.textTransform = style.textTransform;

  const letters = sourceText.match(/[A-Za-z]/g) || [];
  const uppercase = letters.filter((letter) => letter === letter.toUpperCase()).length;
  if (letters.length >= 6 && uppercase / letters.length > 0.82 && sourceText.length < 95) {
    bubble.style.textTransform = "uppercase";
    bubble.style.fontWeight = "900";
  }
}

function cssEscape(value) {
  if (window.CSS && typeof window.CSS.escape === "function") return window.CSS.escape(value);
  return String(value).replace(/["\\]/g, "\\$&");
}

function renderNotice(targetOverlay, text) {
  targetOverlay.innerHTML = "";
  showOverlayNotice(targetOverlay, text);
}

function showOverlayNotice(targetOverlay, text) {
  let notice = targetOverlay.querySelector(".ocr-notice");
  if (!notice) {
    notice = document.createElement("div");
    notice.className = "ocr-notice";
    targetOverlay.appendChild(notice);
  }

  notice.textContent = text;
}

function clearOverlayNotice(targetOverlay) {
  targetOverlay.querySelector(".ocr-notice")?.remove();
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

  statusLine.textContent = loadedImages
    ? "Images visibles dans le lecteur. La traduction continue en arriere-plan."
    : "Chargement des premieres images...";
  scheduleAutoTranslate();
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
        : "OCR local + traduction locale prets.";
      if (capabilities.ollamaModel) warmupLocalModel();
    } else if (capabilities.ocr) {
      capabilityLine.textContent = "OCR local pret. Traduction locale non installee.";
    } else {
      capabilityLine.textContent = "Preview web: lecteur d'images OK, OCR/IA non connectee.";
    }
  } catch {
    capabilityLine.textContent = "Preview web locale. OCR/IA non connectee.";
  }
}

function warmupLocalModel() {
  fetch("/v1/webtoon/warmup", { cache: "no-store" }).catch(() => {});
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
