import Foundation

public enum BrowserBridgeScript {
    public static let handlerName = "webtoonLensV2Viewport"
    public static let mainFrameOnly = true
    public static let source = #"""
    (() => {
      if (window.WebtoonLensV2) return;
      const documentID = window.crypto && typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
      let revision = 0;
      let contentRevision = 0;
      let geometryRevision = 0;
      let disposed = false;
      const listeners = [];
      const sourceIDs = new WeakMap();
      const sourceVersions = new WeakMap();
      const knownImages = new Map();
      let sourceSequence = 0;
      let softTimer = 0;
      let scrollFrame = 0;
      let lastBlock = null;
      let readingElement = null;
      const viewport = () => window.visualViewport;
      function clippedRect(element) {
        const rect = element.getBoundingClientRect();
        const v = viewport();
        let left = Math.max(rect.left, v ? v.offsetLeft : 0), top = Math.max(rect.top, v ? v.offsetTop : 0);
        let right = Math.min(rect.right, (v ? v.offsetLeft + v.width : innerWidth));
        let bottom = Math.min(rect.bottom, (v ? v.offsetTop + v.height : innerHeight));
        for (let parent = element.parentElement, depth = 0; parent && depth < 128; parent = parent.parentElement, depth++) {
          const style = getComputedStyle(parent), clip = parent.getBoundingClientRect();
          if (/auto|scroll|hidden|clip/.test(style.overflowX)) { left = Math.max(left, clip.left); right = Math.min(right, clip.right); }
          if (/auto|scroll|hidden|clip/.test(style.overflowY)) { top = Math.max(top, clip.top); bottom = Math.min(bottom, clip.bottom); }
        }
        return { left, top, right, bottom, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
      }
      function visible(element) {
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        const v = viewport();
        const left = v ? v.offsetLeft : 0, top = v ? v.offsetTop : 0;
        const width = v ? v.width : innerWidth, height = v ? v.height : innerHeight;
        return style.display !== 'none' && style.visibility !== 'hidden' &&
          Number(style.opacity) !== 0 && rect.width > 0 && rect.height > 0 &&
          rect.right > left && rect.left < left + width &&
          rect.bottom > top && rect.top < top + height;
      }
      function blockedInRoot(root) {
        const fields = 'input:not([type="hidden"]):not([type="button"]):not([type="submit"]):not([type="reset"]), textarea, select, [contenteditable]:not([contenteditable="false"]), [role="textbox"]';
        if (Array.from(root.querySelectorAll(fields)).some(visible)) return 'form';
        if (Array.from(root.querySelectorAll('iframe, frame')).some(visible)) return 'frame';
        if (Array.from(root.querySelectorAll('video')).some(visible)) return 'media';
        for (const element of root.querySelectorAll('*')) {
          if (element.shadowRoot && visible(element)) {
            const reason = blockedInRoot(element.shadowRoot);
            if (reason) return reason;
          }
        }
        return null;
      }
      function blockedReason() {
        if (!/^https?:$/.test(location.protocol)) return 'scheme';
        if (/just a moment|captcha|access denied|security verification|verify.*human/i.test(document.title) ||
            Array.from(document.querySelectorAll('#challenge-form, .cf-turnstile, [id^="cf-chl"], [name="cf-turnstile-response"]')).some(visible)) {
          return 'challenge';
        }
        // Inspect field presence, never values, cookies, storage or credentials.
        return blockedInRoot(document);
      }
      function state() {
        const v = viewport();
        const left = v ? v.offsetLeft : 0, top = v ? v.offsetTop : 0;
        const width = v ? v.width : innerWidth, height = v ? v.height : innerHeight;
        const images = Array.from(document.querySelectorAll('img, canvas')).filter(element => {
          const rect = element.getBoundingClientRect();
          return rect.width >= 140 && rect.height >= 160 &&
            (element.tagName !== 'IMG' || (element.complete && element.naturalWidth >= 140));
        });
        function identify(element) {
          if (!sourceIDs.has(element)) sourceIDs.set(element, ++sourceSequence);
          const id = String(sourceIDs.get(element));
          knownImages.delete(id);
          knownImages.set(id, new WeakRef(element));
          while (knownImages.size > 40) knownImages.delete(knownImages.keys().next().value);
          return id;
        }
        function signature(element) {
          const source = element.currentSrc || '';
          let previous = sourceVersions.get(element);
          if (!previous || previous.source !== source) {
            previous = { source, version: (previous?.version || 0) + 1 };
            sourceVersions.set(element, previous);
          }
          return `${element.tagName}:v${previous.version}:${element.naturalWidth || element.width}:${element.naturalHeight || element.height}`;
        }
        const candidates = images.filter(visible).map(element => {
          const rect = clippedRect(element);
          return { element, x: rect.left, y: rect.top, width: rect.width, height: rect.height };
        }).filter(candidate => candidate.width >= 140 && candidate.height >= 120)
          .sort((a, b) => b.width * b.height - a.width * a.height);
        const reading = candidates[0];
        readingElement = reading?.element || null;
        const anchorFor = element => {
          const rect = element.getBoundingClientRect();
          const id = identify(element);
          const scale = devicePixelRatio || 1;
          const x = Math.round((rect.left - left) * scale) / scale;
          const y = Math.round((rect.top - top) * scale) / scale;
          const rasterWidth = Math.max(1, Math.round(rect.width * scale));
          const rasterHeight = Math.max(1, Math.round(rect.height * scale));
          const clip = clippedRect(element);
          const clipLeft = Math.ceil((clip.left - left) * scale) / scale, clipTop = Math.ceil((clip.top - top) * scale) / scale;
          const clipRight = Math.floor((clip.right - left) * scale) / scale, clipBottom = Math.floor((clip.bottom - top) * scale) / scale;
          return { id, signature: signature(element),
            bounds: { x: x / width, y: y / height, width: rasterWidth / scale / width, height: rasterHeight / scale / height },
            pixelWidth: element.naturalWidth || element.width, pixelHeight: element.naturalHeight || element.height,
            rasterWidth, rasterHeight,
            rasterPhaseX: (((rect.left - left) * scale) % 1 + 1) % 1,
            rasterPhaseY: (((rect.top - top) * scale) % 1 + 1) % 1,
            visibleBounds: { x: clipLeft / width, y: clipTop / height,
              width: Math.max(0, clipRight - clipLeft) / width, height: Math.max(0, clipBottom - clipTop) / height } };
        };
        const nearby = images.sort((a, b) => {
          const distance = element => {
            const rect = element.getBoundingClientRect();
            return Math.max(top - rect.bottom, rect.top - top - height, 0);
          };
          return distance(a) - distance(b);
        }).slice(0, 12).map(anchorFor);
        let readingSource = null, captureRegion = null, readingAnchor = null;
        if (reading) {
          const element = reading.element;
          readingAnchor = anchorFor(element);
          readingSource = `${readingAnchor.id}:${readingAnchor.signature}`;
          captureRegion = { x: (reading.x - left) / width, y: (reading.y - top) / height,
            width: reading.width / width, height: reading.height / height };
        } else {
          readingAnchor = { id: 'document', signature: `DOCUMENT:${documentID}`,
            bounds: { x: -scrollX / width, y: -scrollY / height,
              width: document.documentElement.scrollWidth / width, height: document.documentElement.scrollHeight / height } };
          captureRegion = { x: 0, y: 0, width: 1, height: 1 };
        }
        return {
          documentID, revision, contentRevision, geometryRevision, url: location.href, scrollX, scrollY,
          viewportWidth: v ? v.width : innerWidth,
          viewportHeight: v ? v.height : innerHeight,
          viewportLeft: v ? v.offsetLeft : 0,
          viewportTop: v ? v.offsetTop : 0,
          viewportScale: v ? v.scale : 1,
          blockedReason: blockedReason(), captureRegion, readingSource, readingAnchor,
          trackedAnchors: [ { id: 'document', signature: `DOCUMENT:${documentID}`,
            bounds: { x: -scrollX / width, y: -scrollY / height,
              width: document.documentElement.scrollWidth / width, height: document.documentElement.scrollHeight / height } },
            ...nearby ],
          sourceStates: Array.from(knownImages, ([id, reference]) => {
            const element = reference.deref();
            return { id, signature: element ? signature(element) : '', connected: !!element?.isConnected };
          })
        };
      }
      function changed(reason = 'initial') {
        if (disposed) return;
        revision += 1;
        if (reason === 'scroll' || reason === 'layout') geometryRevision += 1;
        if (reason === 'scroll') {
          if (scrollFrame) return;
          scrollFrame = requestAnimationFrame(() => {
            scrollFrame = 0;
            if (!disposed) window.webkit.messageHandlers.webtoonLensV2Viewport.postMessage({
              documentID, revision, url: location.href, kind: 'hard', reason, contentRevision,
              blockedReason: blockedReason(), document: state()
            });
          });
          return;
        }
        window.webkit.messageHandlers.webtoonLensV2Viewport.postMessage({
          documentID, revision, url: location.href
          , kind: 'hard', reason, contentRevision, blockedReason: blockedReason(),
          document: reason === 'reading-source' ? state() : null
        });
      }
      function contentChanged() {
        if (disposed) return;
        const block = blockedReason();
        if (block !== lastBlock) {
          lastBlock = block;
          changed('privacy');
          return;
        }
        clearTimeout(softTimer);
        softTimer = setTimeout(() => {
          contentRevision += 1;
          window.webkit.messageHandlers.webtoonLensV2Viewport.postMessage({
            documentID, revision, contentRevision, url: location.href, kind: 'content'
          });
        }, 80);
      }
      function listen(target, event, capture = false) {
        if (!target) return;
        const handler = () => changed(event === 'resize' ? 'layout' : event);
        target.addEventListener(event, handler, { passive: true, capture });
        listeners.push([target, event, capture, handler]);
      }
      listen(document, 'scroll', true); // Includes nested scrolling containers.
      document.addEventListener('load', contentChanged, true);
      listen(document, 'pointerdown', true);
      listen(document, 'keydown', true);
      listen(document, 'focusin', true);
      listen(window, 'resize');
      listen(window, 'pageshow');
      listen(window, 'pagehide');
      listen(window, 'hashchange');
      listen(window, 'popstate');
      listen(viewport(), 'scroll');
      listen(viewport(), 'resize');
      const mutations = new MutationObserver(records => {
        if (records.some(record =>
            (sourceIDs.has(record.target) && record.type === 'attributes' &&
              ['src', 'srcset'].includes(record.attributeName)) ||
            (readingElement && record.type !== 'attributes' && readingElement.contains(record.target)))) {
          changed('reading-source');
        } else {
          contentChanged();
        }
      });
      mutations.observe(document.documentElement, {
        childList: true, subtree: true, attributes: true, characterData: true
      });
      const sizes = new ResizeObserver(contentChanged);
      sizes.observe(document.documentElement);
      window.WebtoonLensV2 = {
        state,
        dispose() {
          disposed = true;
          knownImages.clear();
          clearTimeout(softTimer);
          cancelAnimationFrame(scrollFrame);
          mutations.disconnect();
          sizes.disconnect();
          document.removeEventListener('load', contentChanged, true);
          for (const [target, event, capture, handler] of listeners) target.removeEventListener(event, handler, capture);
        }
      };
      changed();
    })();
    """#
}
