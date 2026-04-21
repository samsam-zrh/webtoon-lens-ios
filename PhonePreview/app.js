const imageInput = document.getElementById("imageInput");
const previewImage = document.getElementById("previewImage");
const emptyState = document.getElementById("emptyState");
const overlay = document.getElementById("overlay");
const translateButton = document.getElementById("translateButton");
const sourceText = document.getElementById("sourceText");
const backendUrl = document.getElementById("backendUrl");

const boxes = [
  { x: 0.12, y: 0.14, width: 0.42, height: 0.09 },
  { x: 0.48, y: 0.39, width: 0.36, height: 0.1 },
  { x: 0.16, y: 0.68, width: 0.46, height: 0.1 }
];

backendUrl.value = localStorage.getItem("webtoonLensBackend") || "";

imageInput.addEventListener("change", () => {
  const file = imageInput.files && imageInput.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = () => {
    previewImage.src = String(reader.result);
    previewImage.style.display = "block";
    emptyState.style.display = "none";
    overlay.innerHTML = "";
  };
  reader.readAsDataURL(file);
});

backendUrl.addEventListener("input", () => {
  localStorage.setItem("webtoonLensBackend", backendUrl.value.trim());
});

translateButton.addEventListener("click", async () => {
  translateButton.disabled = true;
  translateButton.textContent = "Traduction...";

  try {
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
  } finally {
    translateButton.disabled = false;
    translateButton.textContent = "Traduire";
  }
});

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
