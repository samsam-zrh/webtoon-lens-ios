const translateButton = document.getElementById("translate");
const autoModeCheckbox = document.getElementById("autoMode");

browser.runtime.sendMessage({ type: "getAutoMode" }).then((settings) => {
  autoModeCheckbox.checked = Boolean(settings.autoMode);
});

translateButton.addEventListener("click", async () => {
  translateButton.disabled = true;
  translateButton.textContent = "Traduction...";
  try {
    await browser.runtime.sendMessage({ type: "translateVisibleImages" });
    translateButton.textContent = "Lance";
  } catch (error) {
    translateButton.textContent = "Erreur";
  } finally {
    setTimeout(() => {
      translateButton.disabled = false;
      translateButton.textContent = "Traduire les images visibles";
    }, 900);
  }
});

autoModeCheckbox.addEventListener("change", () => {
  browser.runtime.sendMessage({
    type: "setAutoMode",
    enabled: autoModeCheckbox.checked
  });
});
