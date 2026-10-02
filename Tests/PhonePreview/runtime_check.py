"""OCR + modèle réels via HTTP ; conserve les réponses et mesures de ce Mac."""
import base64
import io
import json
from pathlib import Path
import sys
import time
import urllib.request
import numpy as np
from PIL import Image

from fixtures import create, COLORED

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence")
URL = "http://127.0.0.1:8787"


def post(path, payload):
    started = time.perf_counter()
    request = urllib.request.Request(URL+path, data=json.dumps(payload).encode(),
                                    headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=180) as response:
        result = json.load(response)
    return result, round(time.perf_counter()-started, 3)


def run():
    create(ROOT / "fixtures")
    results = {}
    for language in ("en", "zh"):
        data = base64.b64encode((ROOT / "fixtures" / f"{language}.png").read_bytes()).decode()
        for mode in ("auto", language):
            ocr_payload = dict(imageData=data, language=mode)
            first, first_s = post("/v1/webtoon/ocr", ocr_payload)
            repeat, repeat_s = post("/v1/webtoon/ocr", ocr_payload)
            assert len(first["segments"]) == 3, first
            assert [s["readingOrder"] for s in first["segments"]] == [0, 1, 2]
            assert repeat["timing"]["cached"]
            if language == "zh":
                assert "金丹境" in first["segments"][0]["sourceText"]
            payload = dict(segments=first["segments"], sourceLanguage=mode, targetLanguage="fr", glossary=[])
            translations, translate_s = post("/v1/webtoon/translate", payload)
            cached, cached_s = post("/v1/webtoon/translate", payload)
            assert cached["timing"]["cacheHits"] == 3
            assert "noyau d'or" in translations["segments"][0]["translatedText"].casefold()
            if language == "en":
                assert "guilde" in translations["segments"][1]["translatedText"]
                assert "donjon" in translations["segments"][1]["translatedText"]
            else:
                assert "énergie spirituelle" in translations["segments"][1]["translatedText"].casefold()
            results[f"{language}-{mode}"] = dict(ocrFirstSeconds=first_s, ocrRepeatSeconds=repeat_s,
                translationFirstSeconds=translate_s, translationRepeatSeconds=cached_s,
                ocr=first, translation=translations)
    data = base64.b64encode((ROOT / "fixtures/colored.png").read_bytes()).decode()
    colored, seconds = post("/v1/webtoon/ocr", dict(imageData=data, language="auto"))
    assert len(colored["segments"]) == len(COLORED), colored
    truth = np.asarray(Image.open(ROOT / "fixtures/colored-interiors.png"))
    for segment, (fill, ink, _, _) in zip(colored["segments"], COLORED):
        assert segment["renderMode"] == "replace", segment
        assert segment["style"]["fillColor"] == fill
        assert segment["style"]["textColor"] == ink
        mask = Image.open(io.BytesIO(base64.b64decode(segment["maskData"].split(",")[1])))
        box = segment["boundingBox"]
        x, y = round(box["x"]*truth.shape[1]), round(box["y"]*truth.shape[0])
        allowed = truth[y:y+mask.height, x:x+mask.width]
        alpha = np.asarray(mask.getchannel("A"))
        assert alpha.shape == allowed.shape
        assert not np.any((alpha > 0) & (allowed == 0)), "Masque hors de la forme originale"
    results["colored"] = dict(ocrFirstSeconds=seconds, originalShapesPreserved=True, ocr=colored)
    payload = dict(segments=[dict(id="custom", text="Azure Moon is waiting for you.")], targetLanguage="fr",
                   glossary=[dict(source="Azure Moon", translation="Lune d'azur", isLocked=True)])
    before, _ = post("/v1/webtoon/translate", payload)
    payload["glossary"][0]["translation"] = "Lune écarlate"
    after, _ = post("/v1/webtoon/translate", payload)
    assert "Lune d'azur" in before["segments"][0]["translatedText"]
    assert "Lune écarlate" in after["segments"][0]["translatedText"]
    assert after["timing"]["cacheHits"] == 0
    results["override"] = dict(before=before, after=after)
    language_cases = {}
    for source, expected in (
        ("She is my childhood friend.", "amie"),
        ("師兄，你的靈氣已經耗盡了！", "énergie spirituelle"),
        ("DON'T ATTACK YET. WE MUST RESCUE THE HEALER FIRST!", "sauver"),
    ):
        translated, seconds = post("/v1/webtoon/translate", dict(segments=[dict(id="language", text=source)],
                                                               sourceLanguage="auto", targetLanguage="fr", glossary=[]))
        output = translated["segments"][0]["translatedText"]
        assert expected in output.casefold(), (source, output)
        assert not any("\u3400" <= char <= "\u9fff" for char in output)
        language_cases[source] = dict(translation=output, seconds=seconds)
    results["languageCases"] = language_cases
    (ROOT / "pipeline-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: {k: v for k, v in value.items() if k.endswith("Seconds")}
                      for key, value in results.items()}, indent=2))
    print("OCR, traduction réelle, cache et correction personnalisée : OK.")


if __name__ == "__main__":
    run()
