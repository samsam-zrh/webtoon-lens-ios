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
const chapterError = document.getElementById("chapterError");
const chapterErrorMessage = document.getElementById("chapterErrorMessage");
const openSourceLink = document.getElementById("openSourceLink");

document.getElementById("importAfterError").addEventListener("click", () => imageInput.click());

const OCR_WINDOW_MARGIN_BEFORE = 0.12;
const OCR_WINDOW_MARGIN_AFTER = 0.42;
const OCR_WINDOW_MAX_NATURAL_HEIGHT = 2500;
const OCR_WINDOW_COVERAGE_THRESHOLD = 1 - 1e-8;
const OCR_WINDOWS_PER_PASS = 4;
const OCR_VIEWPORT_FOCI = [0.48, 0.72, 0.96, 1.14];
const OCR_WINDOW_DEDUPE_THRESHOLD = 0.66;
const AUTO_TRANSLATE_DELAY_MS = 90;
const TRANSLATION_PAGES_PER_PASS = 1;
const BACKGROUND_PREFETCH_PAGES = 3;

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
let requests = new AbortController();
let translationPassRunning = false;
let importedUrls = [];

if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("./sw.js").catch(error => console.warn("Cache hors ligne indisponible", error));
}

loadCapabilities();
updateChapterNavigation(webtoonUrl.value);
window.addEventListener("scroll", scheduleAutoTranslate, { passive: true });
window.addEventListener("resize", scheduleAutoTranslate);
document.getElementById("showOriginal").addEventListener("change", event => {
  stage.classList.toggle("show-original", event.target.checked);
});
document.getElementById("retryButton").addEventListener("click", retryFailedTranslations);
window.addEventListener("glossarychange", restartTranslation);

if (imageInput) {
  imageInput.addEventListener("change", () => {
    const files = Array.from(imageInput.files || []);
    if (!files.length) return;
    if (files.some(file => !["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > 20_000_000)) {
      statusLine.textContent = "Utilisez des pages PNG, JPEG ou WebP de moins de 20 Mo.";
      return;
    }
    clearChapterError();
    currentPageUrl = "";
    renderImageFeed(files.map(file => ({ url: URL.createObjectURL(file), alt: file.name, local: true })));
    warmupLocalModel();
    imageInput.value = "";
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
  restartTranslation();
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
  if (openUrlButton.disabled) return;
  clearChapterError();
  const value = normalizedUrlValue(urlOverride || webtoonUrl.value);
  if (!value) {
    showChapterError("Collez d’abord le lien d’un chapitre, ou importez vos pages.", "");
    return;
  }

  setOpenButtonBusy(true);
  const sessionId = contentSessionId;
  statusLine.textContent = "Ouverture du chapitre, extraction des images et prechauffe de la traduction...";

  try {
    warmupLocalModel();
    webtoonUrl.value = value;

    const response = await fetch(`/v1/webtoon/extract?url=${encodeURIComponent(value)}`, { signal: requests.signal });
    if (!response.ok) {
      const message = await readError(response);
      throw new Error(message || `Extraction impossible (${response.status})`);
    }
    const payload = await response.json();
    if (isStaleSession(sessionId)) return;
    if (!Array.isArray(payload.images) || !payload.images.length) {
      throw new Error("Aucune image de chapitre accessible n’a été trouvée. Ouvrez le site dans votre navigateur ou importez vos pages.");
    }
    localStorage.setItem("webtoonLensUrl", value);
    updateChapterNavigation(value);
    currentPageUrl = value;
    currentCaptureDataUrl = "";
    renderImageFeed(payload.images);
  } catch (error) {
    if (isStaleSession(sessionId) || error.name === "AbortError") return;
    const message = error instanceof TypeError
      ? "Le lecteur n’a pas pu contacter le serveur local. Vérifiez qu’il est démarré, ou réessayez."
      : error.message || "Impossible d’ouvrir ce chapitre. Vous pouvez importer vos pages.";
    showChapterError(message, value);
  } finally {
    setOpenButtonBusy(false);
  }
}

function clearChapterError() {
  chapterError.hidden = true;
  chapterErrorMessage.textContent = "";
  webtoonUrl.removeAttribute("aria-invalid");
  openSourceLink.removeAttribute("href");
  openSourceLink.hidden = true;
}

function showChapterError(message, url) {
  chapterErrorMessage.textContent = message;
  chapterError.hidden = false;
  webtoonUrl.setAttribute("aria-invalid", "true");
  try {
    const source = new URL(url);
    if (["http:", "https:"].includes(source.protocol) && !source.username && !source.password) {
      openSourceLink.href = source.href;
      openSourceLink.hidden = false;
    }
  } catch {
    openSourceLink.hidden = true;
  }
  statusLine.textContent = imageReader.querySelector(".reader-page")
    ? "Ce chapitre n’a pas été chargé. Les pages précédentes sont conservées."
    : "Ce chapitre n’a pas été chargé. Utilisez « Importer des pages » pour continuer.";
}

function normalizedUrlValue(rawValue) {
  const value = String(rawValue || "").trim();
  if (!value) return "";
  return value.includes("://") ? value : `https://${value}`;
}

function beginContentSession() {
  contentSessionId += 1;
  requests.abort();
  requests = new AbortController();
  for (const page of imageReader.querySelectorAll(".reader-page")) {
    page.__imageObserver?.disconnect();
    window.WebtoonLayout.clear(page.querySelector(".overlay"));
  }
  importedUrls.forEach(url => URL.revokeObjectURL(url));
  importedUrls = [];
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
    const pathMatch = /(?:chapter|chapitre|episode|ep|ch)[-_/]?(\d+)(?=[^\d]*$)/i.exec(parsed.pathname);
    if (pathMatch) {
      const digits = { 0: pathMatch[1], index: pathMatch.index + pathMatch[0].lastIndexOf(pathMatch[1]) };
      const chapterNumber = Number(digits[0]);
      return {
        previousUrl: chapterNumber > 1 ? buildSteppedUrl(parsed, "pathname", digits, chapterNumber - 1) : "",
        nextUrl: buildSteppedUrl(parsed, "pathname", digits, chapterNumber + 1),
        currentLabel: `Chapitre ${chapterNumber} detecte.`
      };
    }

    const searchMatch = /[?&](?:chapter|episode|chapitre)=(\d+)/i.exec(parsed.search);
    if (searchMatch) {
      const digits = { 0: searchMatch[1], index: searchMatch.index + searchMatch[0].lastIndexOf(searchMatch[1]) };
      const chapterNumber = Number(digits[0]);
      return {
        previousUrl: chapterNumber > 1 ? buildSteppedUrl(parsed, "search", digits, chapterNumber - 1) : "",
        nextUrl: buildSteppedUrl(parsed, "search", digits, chapterNumber + 1),
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
  importedUrls = images.filter(image => image.local).map(image => image.url);

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
    img.src = image.local ? image.url : proxyImageUrl(image.url);
    img.alt = image.alt || `Image webtoon ${index + 1}`;
    img.loading = index < 3 ? "eager" : "lazy";
    img.decoding = "async";
    img.fetchPriority = index < 2 ? "high" : "auto";
    img.addEventListener("load", () => {
      if (isStaleSession(Number(page.dataset.sessionId)) || !page.isConnected) return;
      loadedImages += 1;
      page.dataset.loaded = "true";
      updateReaderStatus(images.length);
    });
    img.addEventListener("error", () => {
      if (isStaleSession(Number(page.dataset.sessionId)) || !page.isConnected) return;
      failedImages += 1;
      page.classList.add("load-error");
      badge.textContent = `Image ${index + 1} bloquee`;
      updateReaderStatus(images.length);
    });

    const pageOverlay = document.createElement("div");
    pageOverlay.className = "overlay";
    pageOverlay.setAttribute("aria-live", "polite");

    const imageObserver = new ResizeObserver(() => {
      pageOverlay.style.height = `${img.clientHeight}px`;
    });
    imageObserver.observe(img);
    page.__imageObserver = imageObserver;
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
  if (translationPassRunning) return;
  translationPassRunning = true;
  try {
  const sessionId = contentSessionId;
  autoTranslateEnabled = true;
  preloadTranslationPages();
  const pages = readerPagesForTranslation().filter((page) => pageNeedsTranslation(page)).slice(0, TRANSLATION_PAGES_PER_PASS);
  if (!pages.length) {
    if (showTranslationErrors()) return;
    if (!loadedImages && !failedImages) {
      statusLine.textContent = "Chargement des premieres images...";
      return;
    }
    const running = document.querySelector(".reader-page[data-translation-state='running']");
    const dialogueCount = document.querySelectorAll(".dialogue-entry").length;
    const allAnalyzed = Array.from(imageReader.querySelectorAll(".reader-page")).every(page =>
      page.dataset.translationState === "done" || page.classList.contains("load-error"));
    const coverageNotice = allAnalyzed
      ? failedImages
        ? "Les images accessibles ont été analysées ; certaines images n'ont pas pu être chargées."
        : "Toutes les images ont été analysées."
      : "Le chapitre continue en arrière-plan.";
    statusLine.textContent = running
      ? "Traduction en cours..."
      : dialogueCount
        ? `${dialogueCount} dialogue(s) traduit(s). La traduction des zones non fiables est affichée sous l’image. ${coverageNotice}`
        : `Aucun texte reconnu pour le moment. ${coverageNotice}`;
    return;
  }

  let translatedPages = 0;
  for (const [index, page] of pages.entries()) {
    if (isStaleSession(sessionId)) return;
    const translated = await translatePageProgressively(page, index + 1, pages.length, sessionId);
    if (translated) translatedPages += 1;
  }

  if (isStaleSession(sessionId)) return;
  if (!showTranslationErrors()) {
    statusLine.textContent = translatedPages
      ? `OK: ${translatedPages} image(s) avancee(s). La traduction continue en fond.`
      : "Analyse en cours. La traduction avance zone par zone.";
  }
  scheduleAutoTranslate();
  } finally {
    translationPassRunning = false;
  }
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
      clearOverlayNotice(pageOverlay);
      processedWindows += 1;

      if (ocr.length) {
        upgradeTranslatedRegions(page, ocr);
        const coreSegments = ocr.filter(segment => segment.withinWindow);
        page.__ocrSegments = mergeSegmentLists(page.__ocrSegments || [], coreSegments);
        const freshSegments = newSegmentsForPage(page, coreSegments);
        if (freshSegments.length) {
          const contextSegments = contextForSegments(page.__ocrSegments);

          for (let segmentIndex = 0; segmentIndex < freshSegments.length;) {
            if (isStaleSession(sessionId) || !page.isConnected) return false;
            const batchSize = segmentIndex === 0 ? 1 : progressiveBatchSize(freshSegments.length - segmentIndex);
            const batch = freshSegments.slice(segmentIndex, segmentIndex + batchSize);
            const endIndex = segmentIndex + batch.length;
            statusLine.textContent = `Traduction bulle ${segmentIndex + 1}/${freshSegments.length} - image ${Number(page.dataset.index || "0") + 1}...`;
            const translated = await translateSegments(batch, contextSegments, previousTranslations);
            if (isStaleSession(sessionId)) return false;

            for (const segment of translated) {
              renderSegmentIntoOverlay(pageOverlay, segment);
              rememberTranslatedSegment(page, segment);
              previousTranslations.push({
                source: segment.sourceText || "",
                translation: segment.translatedText || ""
              });
              translatedCount += 1;
            }
            page.__previousTranslations = previousTranslations.slice(-14);
            segmentIndex = endIndex;
          }
        }
      }

      rememberProcessedWindow(page, crop.window);
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
    if (isStaleSession(sessionId)) return false;
    page.dataset.translationState = "error";
    page.dataset.translationError = error.message || String(error);
    showOverlayNotice(pageOverlay, error && error.message ? error.message : String(error));
    showTranslationErrors();
    return false;
  } finally {
    scheduleAutoTranslate();
  }
}

function showTranslationErrors() {
  const failed = imageReader.querySelectorAll(".reader-page[data-translation-state='error']");
  if (!failed.length) return false;
  statusLine.textContent = `${failed.length} image(s) en erreur : ${failed[0].dataset.translationError}. Les autres pages continuent. « Relancer la traduction » réessaie les échecs sans effacer les traductions affichées.`;
  return true;
}

function pageNeedsTranslation(page) {
  if (page.dataset.loaded !== "true" || ["running", "done", "error"].includes(page.dataset.translationState)) {
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
  return page.dataset.loaded === "true";
}

function preloadTranslationPages() {
  const pending = Array.from(imageReader.querySelectorAll(".reader-page")).filter(page =>
    !page.classList.contains("load-error") && !["done", "error"].includes(page.dataset.translationState));
  let active = pending.filter(page =>
    page.dataset.loaded === "true" || page.querySelector("img").loading === "eager").length;
  for (const page of pending) {
    if (active >= BACKGROUND_PREFETCH_PAGES) break;
    const img = page.querySelector("img");
    if (page.dataset.loaded !== "true" && img.loading !== "eager") {
      img.loading = "eager";
      active += 1;
    }
  }
}

function nextSequentialWindow(page) {
  const img = page.querySelector("img");
  if (!img || !img.naturalHeight) return null;

  const merged = mergeWindows(page.__ocrWindows || []);
  const normalizedMaxHeight = clamp01(OCR_WINDOW_MAX_NATURAL_HEIGHT / Math.max(1, img.naturalHeight));
  const minimumGap = 0.5 / img.naturalHeight;
  let cursor = 0;

  for (const windowRange of merged) {
    if (windowRange.y - cursor > minimumGap) {
      return { y: cursor, height: Math.min(windowRange.y - cursor, normalizedMaxHeight) };
    }
    cursor = Math.max(cursor, windowRange.y + windowRange.height);
  }

  if (1 - cursor <= minimumGap) return null;
  const height = Math.min(1 - cursor, normalizedMaxHeight);
  return {
    y: clamp01(cursor),
    height: clamp01(height)
  };
}

async function visibleImageCrop(page) {
  const img = page.querySelector("img");
  const cropWindow = translationWindowCandidates(page)[0];
  if (!img || !cropWindow) return null;

  const coreY = Math.max(0, Math.floor(cropWindow.y * img.naturalHeight));
  const coreBottom = Math.min(img.naturalHeight, Math.ceil((cropWindow.y + cropWindow.height) * img.naturalHeight));
  const cropY = Math.max(0, coreY - 400);
  const cropHeight = Math.min(img.naturalHeight, coreBottom + 400) - cropY;
  const canvas = document.createElement("canvas");
  canvas.width = img.naturalWidth;
  canvas.height = cropHeight;

  const context = canvas.getContext("2d", { willReadFrequently: false });
  if (!context) return null;
  context.drawImage(img, 0, cropY, img.naturalWidth, cropHeight, 0, 0, img.naturalWidth, cropHeight);

  return {
    dataUrl: canvas.toDataURL("image/png"),
    cacheKey: `${coreY}-${coreBottom}`,
    window: {
      y: coreY / img.naturalHeight,
      height: (coreBottom - coreY) / img.naturalHeight
    },
    mappingWindow: {
      y: cropY / img.naturalHeight,
      height: cropHeight / img.naturalHeight
    },
    imageWidth: img.naturalWidth,
    imageHeight: img.naturalHeight
  };
}

function mapCropSegmentsToPage(segments, crop, page) {
  const pageIndex = Number(page.dataset.index || "0");
  const mapping = crop.mappingWindow || crop.window;
  return segments.map((segment, index) => {
    const box = segment.boundingBox || { x: 0, y: 0, width: 0, height: 0 };
    const fullBox = {
      x: clamp01(Number(box.x || 0)),
      y: clamp01(mapping.y + Number(box.y || 0) * mapping.height),
      width: clamp01(Number(box.width || 0)),
      height: clamp01(Number(box.height || 0) * mapping.height)
    };
    const mapBox = input => input ? {
      x: input.x, y: mapping.y + input.y * mapping.height,
      width: input.width, height: input.height * mapping.height
    } : undefined;
    const raw = mapBox(segment.rawBoundingBox) || fullBox;
    const center = raw.y + raw.height / 2;
    return {
      ...segment,
      id: `p${pageIndex}-${crop.cacheKey}-${segment.id || index}`,
      boundingBox: fullBox,
      rawBoundingBox: raw,
      textBox: mapBox(segment.textBox),
      imageWidth: crop.imageWidth,
      imageHeight: crop.imageHeight,
      readingOrder: Math.round(fullBox.y * 100000) + index,
      cropWindow: crop.window,
      withinWindow: center >= crop.window.y && center <= crop.window.y + crop.window.height
    };
  });
}

function mergeSegmentLists(existing, incoming) {
  const merged = [...existing];
  for (const segment of incoming) {
    const index = merged.findIndex(previous => sameDialogue(previous, segment));
    if (index >= 0) merged[index] = segment;
    else merged.push(segment);
  }
  return merged.sort((a, b) => Number(a.readingOrder || 0) - Number(b.readingOrder || 0));
}

function newSegmentsForPage(page, segments) {
  return mergeSegmentLists([], segments).filter(segment =>
    !(page.__translatedSegments || []).some(previous => sameDialogue(previous, segment)));
}

function rememberTranslatedSegment(page, segment) {
  page.__translatedSegments = mergeSegmentLists(page.__translatedSegments || [], [segment]);
}

function upgradeTranslatedRegions(page, segments) {
  for (const segment of segments) {
    const previous = (page.__translatedSegments || []).find(item => sameDialogue(item, segment));
    if (!previous || segment.renderMode !== "replace" || !segment.maskData) continue;
    const area = box => box ? box.width * box.height : 0;
    if (previous.renderMode === "replace" && area(segment.textBox) <= area(previous.textBox) * 1.15) continue;
    const upgraded = { ...segment, id: previous.id, translatedText: previous.translatedText };
    renderSegmentIntoOverlay(page.querySelector(".overlay"), upgraded);
    rememberTranslatedSegment(page, upgraded);
  }
}

function rememberProcessedWindow(page, cropWindow) {
  page.__ocrWindows = mergeWindows([...(page.__ocrWindows || []), cropWindow]);
}

function visibleWindowAlreadyCovered(page, cropWindow) {
  const windows = page.__ocrWindows || [];
  return coveredRatio(cropWindow, windows) >= OCR_WINDOW_COVERAGE_THRESHOLD;
}

function pageFullyCovered(page) {
  const height = page.querySelector("img")?.naturalHeight || 1;
  return coveredRatio({ y: 0, height: 1 }, page.__ocrWindows || []) >= 1 - 0.5 / height;
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

  return target.height > 0 ? covered / target.height : 0;
}

function mergeWindows(windows) {
  const sorted = windows
    .filter((windowRange) => windowRange && windowRange.height > 0)
    .map((windowRange) => ({ y: clamp01(windowRange.y), height: clamp01(windowRange.height) }))
    .sort((a, b) => a.y - b.y);
  const merged = [];

  for (const windowRange of sorted) {
    const last = merged[merged.length - 1];
    if (!last || windowRange.y > last.y + last.height + 1e-8) {
      merged.push({ ...windowRange });
      continue;
    }
    const end = Math.max(last.y + last.height, windowRange.y + windowRange.height);
    last.height = clamp01(end - last.y);
  }

  return merged;
}

function dialogueText(segment) {
  return String(segment.sourceText || segment.text || "")
    .toLowerCase()
    .replace(/[^a-z0-9\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+/g, "");
}

function sameDialogue(first, second) {
  const a = first.rawBoundingBox || first.boundingBox;
  const b = second.rawBoundingBox || second.boundingBox;
  return Boolean(a && b && dialogueText(first) === dialogueText(second) && boxOverlapRatio(a, b) > 0.7);
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

  return uniquePageList([...visiblePages, ...backgroundPages]);
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
    seriesID: window.WebtoonGlossary.series(),
    style: "Traduction naturelle en francais, adaptee aux webtoons. Garde les noms propres et les pouvoirs coherents.",
    glossary: window.WebtoonGlossary.terms(),
    contextSegments,
    previousTranslations,
    segments: segments.map(segment => {
      const { maskData, ...textOnly } = segment;
      return textOnly;
    })
  });
  if (!Array.isArray(payload.segments) || payload.segments.length !== segments.length) {
    throw new Error("Le moteur n’a pas renvoyé tous les dialogues.");
  }
  return payload.segments.map(translated => ({ ...segments.find(source => source.id === translated.id), ...translated }));
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
    body: JSON.stringify(payload),
    signal: requests.signal
  });
  if (!response.ok) {
    const message = await readError(response);
    throw new Error(message || `Backend ${response.status}`);
  }
  return response.json();
}

function backendBaseUrl() {
  const url = new URL(backendUrl.value.trim() || window.location.origin);
  if (!["localhost", "127.0.0.1", window.location.hostname].includes(url.hostname)) {
    throw new Error("Choisissez un serveur local : les pages ne sont pas envoyées à une API externe.");
  }
  return url.origin;
}

function renderIntoOverlay(targetOverlay, segments) {
  targetOverlay.innerHTML = "";

  for (const segment of segments) {
    renderSegmentIntoOverlay(targetOverlay, segment);
  }
}

function renderSegmentIntoOverlay(targetOverlay, segment) {
  window.WebtoonLayout.render(targetOverlay, segment);
}

function retryFailedTranslations() {
  if (!imageReader.querySelector(".reader-page[data-translation-state='error']")) {
    restartTranslation();
    return;
  }
  requests.abort();
  requests = new AbortController();
  contentSessionId += 1;
  for (const page of imageReader.querySelectorAll(".reader-page")) {
    page.dataset.sessionId = String(contentSessionId);
    if (["error", "running"].includes(page.dataset.translationState)) {
      page.dataset.translationState = "idle";
      delete page.dataset.translationError;
      clearOverlayNotice(page.querySelector(".overlay"));
    }
  }
  statusLine.textContent = "Nouvelle tentative sur les pages en erreur. Les traductions affichées sont conservées…";
  scheduleAutoTranslate();
}

function restartTranslation() {
  requests.abort();
  requests = new AbortController();
  contentSessionId += 1;
  for (const page of imageReader.querySelectorAll(".reader-page")) {
    page.dataset.sessionId = String(contentSessionId);
    page.dataset.translationState = "idle";
    delete page.dataset.translationError;
    page.__ocrWindows = [];
    page.__translatedSegments = [];
    page.__ocrSegments = [];
    page.__previousTranslations = [];
    window.WebtoonLayout.clear(page.querySelector(".overlay"));
  }
  statusLine.textContent = "Nouvelle traduction avec la langue et le glossaire actuels…";
  scheduleAutoTranslate();
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
    Math.max(0, Number(a.width || 0) * Number(a.height || 0)),
    Math.max(0, Number(b.width || 0) * Number(b.height || 0))
  );
  return smallestArea > 0 ? overlap / smallestArea : 0;
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
  if (showTranslationErrors()) {
    scheduleAutoTranslate();
    return;
  }

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
  const text = await response.text();
  try {
    const payload = JSON.parse(text);
    return payload.error || payload.message || "";
  } catch {
    if (/<(?:!doctype|html|head|body)\b/i.test(text)) {
      return `Le serveur n’a pas pu traiter la demande (HTTP ${response.status}). Réessayez ou importez vos pages.`;
    }
    return text.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, 300);
  }
}
