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
      let disposed = false;
      const listeners = [];
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
        return {
          documentID, revision, url: location.href, scrollX, scrollY,
          viewportWidth: v ? v.width : innerWidth,
          viewportHeight: v ? v.height : innerHeight,
          viewportLeft: v ? v.offsetLeft : 0,
          viewportTop: v ? v.offsetTop : 0,
          viewportScale: v ? v.scale : 1,
          blockedReason: blockedReason()
        };
      }
      function changed() {
        if (disposed) return;
        revision += 1;
        window.webkit.messageHandlers.webtoonLensV2Viewport.postMessage({
          documentID, revision, url: location.href
        });
      }
      function listen(target, event, capture = false) {
        if (!target) return;
        target.addEventListener(event, changed, { passive: true, capture });
        listeners.push([target, event, capture]);
      }
      listen(document, 'scroll', true); // Includes nested scrolling containers.
      listen(document, 'load', true);
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
      const mutations = new MutationObserver(changed);
      mutations.observe(document.documentElement, {
        childList: true, subtree: true, attributes: true, characterData: true
      });
      const sizes = new ResizeObserver(changed);
      sizes.observe(document.documentElement);
      window.WebtoonLensV2 = {
        state,
        dispose() {
          disposed = true;
          mutations.disconnect();
          sizes.disconnect();
          for (const [target, event, capture] of listeners) target.removeEventListener(event, changed, capture);
        }
      };
      changed();
    })();
    """#
}
