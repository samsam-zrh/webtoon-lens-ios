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
      let disposed = false;
      const listeners = [];
      const sourceIDs = new WeakMap();
      const trackedImages = new Map();
      let sourceSequence = 0;
      let softTimer = 0;
      let lastBlock = null;
      let readingElement = null;
      const viewport = () => window.visualViewport;
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
        const candidates = Array.from(document.querySelectorAll('img, canvas')).filter(element => {
          if (!visible(element)) return false;
          const rect = element.getBoundingClientRect();
          return rect.width >= 140 && rect.height >= 160 &&
            (element.tagName !== 'IMG' || (element.complete && element.naturalWidth >= 140));
        }).map(element => {
          const rect = element.getBoundingClientRect();
          const x = Math.max(left, rect.left), y = Math.max(top, rect.top);
          const right = Math.min(left + width, rect.right), bottom = Math.min(top + height, rect.bottom);
          return { element, x, y, width: right - x, height: bottom - y };
        }).filter(candidate => candidate.width >= 140 && candidate.height >= 120)
          .sort((a, b) => b.width * b.height - a.width * a.height);
        const reading = candidates[0];
        readingElement = reading?.element || null;
        const anchorFor = element => {
          const rect = element.getBoundingClientRect();
          const id = String(sourceIDs.get(element));
          return { id, signature: `${element.tagName}:${element.currentSrc || ''}:${element.naturalWidth || element.width}:${element.naturalHeight || element.height}`,
            bounds: { x: (rect.left - left) / width, y: (rect.top - top) / height, width: rect.width / width, height: rect.height / height } };
        };
        let readingSource = null, captureRegion = null, readingAnchor = null;
        if (reading) {
          if (!sourceIDs.has(reading.element)) sourceIDs.set(reading.element, ++sourceSequence);
          const element = reading.element;
          trackedImages.set(String(sourceIDs.get(element)), element);
          while (trackedImages.size > 12) trackedImages.delete(trackedImages.keys().next().value);
          readingAnchor = anchorFor(element);
          readingSource = `${sourceIDs.get(element)}:${element.tagName}:${element.currentSrc || ''}:${element.naturalWidth || element.width}:${element.naturalHeight || element.height}`;
          captureRegion = { x: (reading.x - left) / width, y: (reading.y - top) / height,
            width: reading.width / width, height: reading.height / height };
        } else {
          readingAnchor = { id: 'document', signature: `DOCUMENT:${documentID}`,
            bounds: { x: -scrollX / width, y: -scrollY / height,
              width: document.documentElement.scrollWidth / width, height: document.documentElement.scrollHeight / height } };
          captureRegion = { x: 0, y: 0, width: 1, height: 1 };
        }
        return {
          documentID, revision, contentRevision, url: location.href, scrollX, scrollY,
          viewportWidth: v ? v.width : innerWidth,
          viewportHeight: v ? v.height : innerHeight,
          viewportLeft: v ? v.offsetLeft : 0,
          viewportTop: v ? v.offsetTop : 0,
          viewportScale: v ? v.scale : 1,
          blockedReason: blockedReason(), captureRegion, readingSource, readingAnchor,
          trackedAnchors: [ { id: 'document', signature: `DOCUMENT:${documentID}`,
            bounds: { x: -scrollX / width, y: -scrollY / height,
              width: document.documentElement.scrollWidth / width, height: document.documentElement.scrollHeight / height } },
            ...Array.from(trackedImages.values()).filter(element => element.isConnected).map(anchorFor) ]
        };
      }
      function changed(reason = 'initial') {
        if (disposed) return;
        revision += 1;
        window.webkit.messageHandlers.webtoonLensV2Viewport.postMessage({
          documentID, revision, url: location.href
          , kind: 'hard', reason, contentRevision, blockedReason: blockedReason()
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
        if (readingElement && records.some(record =>
            (record.target === readingElement && record.type === 'attributes' &&
              ['src', 'srcset'].includes(record.attributeName)) ||
            (record.type !== 'attributes' && readingElement.contains(record.target)))) {
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
          trackedImages.clear();
          clearTimeout(softTimer);
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
