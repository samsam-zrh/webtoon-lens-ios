const nativeApplicationId = "com.example.webtoonlens.SafariExtension";

browser.runtime.onMessage.addListener((message, sender) => {
  if (!message || typeof message !== "object") {
    return undefined;
  }

  if (message.type === "translateImage") {
    return browser.runtime.sendNativeMessage(nativeApplicationId, message)
      .catch((error) => ({
        ok: false,
        error: error && error.message ? error.message : String(error),
        segments: []
      }));
  }

  if (message.type === "translateVisibleImages") {
    return browser.tabs.query({ active: true, currentWindow: true })
      .then((tabs) => {
        if (!tabs.length || tabs[0].id === undefined) {
          return { ok: false, error: "Aucun onglet actif." };
        }
        return browser.tabs.sendMessage(tabs[0].id, { type: "translateVisibleImages" });
      });
  }

  if (message.type === "setAutoMode") {
    return browser.storage.local.set({ autoMode: Boolean(message.enabled) })
      .then(() => ({ ok: true }));
  }

  if (message.type === "getAutoMode") {
    return browser.storage.local.get({ autoMode: false });
  }

  return undefined;
});
