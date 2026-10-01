"""Mesure avec caches applicatifs vierges, puis répétition, moteur déjà démarré."""
import json
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "PhonePreview"))
import server
from fixtures import create

directory = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence")
create(directory / "fixtures")
results = {}
with tempfile.TemporaryDirectory(prefix="webtoon-benchmark-") as cache:
    server.CACHE_DIR = Path(cache)
    for language in ("en", "zh"):
        data = (directory / "fixtures" / f"{language}.png").read_bytes()
        key = server.ocr_cache_key(data, "auto", "")
        trials = []
        for iteration in range(2):
            started = time.perf_counter()
            segments = server.read_ocr_cache(key)
            cached_ocr = segments is not None
            if segments is None:
                segments = server.ocr_image(data, requested_language="auto")
                server.write_ocr_cache(key, segments)
            ocr_ms = (time.perf_counter()-started)*1000
            translations = server.translate_payload(dict(segments=segments, sourceLanguage="auto",
                                                         targetLanguage="fr", glossary=[]))
            trials.append(dict(ocrMs=round(ocr_ms, 2), translationMs=translations["timing"]["totalMs"],
                               totalMs=round((time.perf_counter()-started)*1000, 2),
                               ocrCached=cached_ocr, translationCacheHits=translations["timing"]["cacheHits"],
                               translations=[s["translatedText"] for s in translations["segments"]]))
        assert trials[0]["translationCacheHits"] == 0
        assert trials[1]["translationCacheHits"] == 3
        results[language] = trials
(directory / "benchmark-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(results, ensure_ascii=False, indent=2))
