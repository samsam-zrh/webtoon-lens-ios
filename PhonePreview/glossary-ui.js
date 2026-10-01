window.WebtoonGlossary = (() => {
  const series = document.getElementById("seriesName");
  const source = document.getElementById("termSource");
  const french = document.getElementById("termFrench");
  const list = document.getElementById("glossaryOverrides");
  const results = document.getElementById("glossaryResults");
  const search = document.getElementById("glossarySearch");
  const count = document.getElementById("glossaryCount");
  let base = [];
  let overrides = [];
  series.value = localStorage.getItem("webtoonLensSeries") || "Mes pages";
  const storageKey = () => `webtoonLensGlossary:${series.value.trim() || "Mes pages"}`;
  const categoryNames = { cultivation: "Cultivation", martial: "Arts martiaux", fantasy: "Fantasy",
    game: "Jeux", romance: "Romance", school: "École" };

  function load() {
    try {
      overrides = JSON.parse(localStorage.getItem(storageKey()) || "[]");
      if (!Array.isArray(overrides)) throw new Error("Format du glossaire invalide.");
      renderOverrides();
    } catch (error) {
      document.getElementById("statusLine").textContent = `Glossaire local illisible : ${error.message}`;
      overrides = [];
    }
  }
  function changed() {
    localStorage.setItem(storageKey(), JSON.stringify(overrides));
    renderOverrides();
    window.dispatchEvent(new Event("glossarychange"));
  }
  function renderOverrides() {
    list.replaceChildren();
    for (const [index, entry] of overrides.entries()) {
      const row = document.createElement("div");
      row.className = "override-row";
      const text = document.createElement("span");
      text.textContent = `${entry.source} → ${entry.translation}`;
      const remove = document.createElement("button");
      remove.className = "ghost-button";
      remove.type = "button";
      remove.textContent = "Supprimer";
      remove.setAttribute("aria-label", `Supprimer la correction ${entry.source}`);
      remove.addEventListener("click", () => { overrides.splice(index, 1); changed(); });
      row.append(text, remove);
      list.append(row);
    }
  }
  function renderBase() {
    results.replaceChildren();
    const query = search.value.toLocaleLowerCase("fr");
    const matches = base.filter(entry => Object.values(entry).filter(Boolean).join(" ").toLocaleLowerCase("fr").includes(query));
    for (const entry of matches.slice(0, 40)) {
      const row = document.createElement("div");
      row.className = "glossary-entry";
      const text = document.createElement("span");
      text.textContent = `${entry.en} / ${entry.zh} → ${entry.fr}`;
      const note = document.createElement("small");
      note.textContent = `${categoryNames[entry.category] || entry.category} · ${entry.context}`;
      row.append(text, note);
      results.append(row);
    }
    if (!matches.length) results.textContent = "Aucun terme correspondant. Ajoutez votre correction ci-dessus.";
  }
  document.getElementById("glossaryForm").addEventListener("submit", event => {
    event.preventDefault();
    const term = source.value.trim();
    const translation = french.value.trim();
    if (!term || !translation) return;
    const entry = { id: `custom-${term}`, source: term, translation, category: "unknown", isLocked: true };
    const index = overrides.findIndex(item => item.source.toLowerCase() === term.toLowerCase());
    if (index < 0) overrides.push(entry);
    else overrides[index] = entry;
    changed();
    source.value = "";
    french.value = "";
  });
  series.addEventListener("change", () => {
    localStorage.setItem("webtoonLensSeries", series.value);
    load();
    window.dispatchEvent(new Event("glossarychange"));
  });
  search.addEventListener("input", renderBase);
  load();
  fetch("/v1/webtoon/glossary").then(response => {
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }).then(payload => {
    base = payload.entries;
    count.textContent = `· ${base.length} concepts`;
    renderBase();
  }).catch(error => { results.textContent = `Lexique indisponible : ${error.message}`; });
  return { terms: () => overrides, series: () => series.value.trim() || "Mes pages" };
})();
