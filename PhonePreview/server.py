from __future__ import annotations

import json
import os
import re
import base64
import csv
import io
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import html as html_utils
from functools import lru_cache
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
TESSDATA_DIR = Path(os.environ.get("WEBTOON_LENS_TESSDATA", Path(os.environ.get("LOCALAPPDATA", "")) / "WebtoonLens" / "tessdata"))
OCR_LANGUAGES = ["jpn", "kor", "chi_sim", "chi_tra", "eng"]


class PreviewHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        super().end_headers()

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/v1/webtoon/capabilities":
            self.handle_capabilities()
            return
        if parsed.path == "/v1/webtoon/extract":
            self.handle_extract(parsed)
            return
        if parsed.path == "/v1/webtoon/image":
            self.handle_image_proxy(parsed)
            return
        super().do_GET()

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/v1/webtoon/ocr":
            self.handle_ocr()
            return
        if parsed.path != "/v1/webtoon/translate":
            self.send_error(404, "Unknown endpoint")
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)

        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        self.handle_translate_payload(payload)

    def handle_capabilities(self) -> None:
        tesseract_command = find_tesseract_command()
        languages = available_tesseract_languages()
        translation_pairs = available_translation_pairs()
        self.write_json(
            200,
            {
                "imageExtraction": True,
                "imageProxy": True,
                "ocr": bool(easyocr_available() or (tesseract_command and languages)),
                "translation": bool(translation_pairs),
                "ocrEngine": "easyocr+tesseract" if easyocr_available() and tesseract_command else ("easyocr" if easyocr_available() else ("tesseract" if tesseract_command else None)),
                "ocrLanguages": languages,
                "translationEngine": "argos" if translation_pairs else None,
                "translationPairs": translation_pairs,
                "message": "Local OCR and offline translation are available." if (easyocr_available() or tesseract_command) and translation_pairs else "OCR/translation dependencies are not fully installed.",
            },
        )

    def handle_ocr(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)

        try:
            payload = json.loads(body.decode("utf-8"))
            data = image_bytes_from_payload(payload)
            segments = ocr_image(data, requested_language=str(payload.get("language", "auto")))
        except json.JSONDecodeError:
            self.write_json(400, {"error": "Invalid JSON"})
            return
        except Exception as exc:
            self.write_json(500, {"error": str(exc), "segments": []})
            return

        self.write_json(200, {"segments": segments})

    def handle_extract(self, parsed: urllib.parse.ParseResult) -> None:
        query = urllib.parse.parse_qs(parsed.query)
        url = query.get("url", [""])[0]
        if not url:
            self.send_error(400, "Missing url")
            return

        try:
            html = fetch_url(url)
            images = extract_images(html, url)
        except Exception as exc:
            self.send_error(502, f"Extraction failed: {exc}")
            return

        self.write_json(200, {"pageURL": url, "images": images[:80]})

    def handle_image_proxy(self, parsed: urllib.parse.ParseResult) -> None:
        query = urllib.parse.parse_qs(parsed.query)
        url = query.get("url", [""])[0]
        referer = query.get("referer", [""])[0]
        if not url:
            self.send_error(400, "Missing url")
            return

        try:
            data, content_type = fetch_binary(url, referer=referer)
        except Exception as exc:
            self.send_error(502, f"Image proxy failed: {exc}")
            return

        self.send_response(200)
        self.send_header("Content-Type", content_type or "image/jpeg")
        self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def write_json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_translate_payload(self, payload: dict[str, Any]) -> None:
        try:
            response = translate_payload(payload)
        except Exception as exc:
            self.write_json(501, translation_unavailable_payload(payload, reason=str(exc)))
            return

        self.write_json(200, response)


def translation_unavailable_payload(payload: dict[str, Any], reason: str = "") -> dict[str, Any]:
    segment_count = len(payload.get("segments", [])) if isinstance(payload.get("segments", []), list) else 0
    return {
        "error": "OCR/LLM translation is not available in the local phone preview.",
        "message": reason or "This endpoint no longer returns fake translations. Connect a real OCR/LLM backend or build the native iOS app.",
        "detectedSourceLanguage": None,
        "segments": [],
        "glossaryUpdates": [],
        "confidence": 0,
        "receivedSegments": segment_count,
    }


def image_bytes_from_payload(payload: dict[str, Any]) -> bytes:
    image_data = str(payload.get("imageData", ""))
    if image_data:
        if "," in image_data and image_data.startswith("data:"):
            image_data = image_data.split(",", 1)[1]
        return base64.b64decode(image_data)

    image_url = str(payload.get("imageUrl", ""))
    if not image_url:
        raise ValueError("Missing imageUrl or imageData")

    referer = str(payload.get("referer", ""))
    data, _ = fetch_binary(image_url, referer=referer)
    return data


def ocr_image(data: bytes, requested_language: str = "auto") -> list[dict[str, Any]]:
    if easyocr_available():
        try:
            segments = easyocr_image(data, requested_language=requested_language)
            if segments:
                return segments
        except Exception:
            pass

    command = find_tesseract_command()
    if not command:
        raise RuntimeError("Tesseract is not installed.")

    languages = [language for language in OCR_LANGUAGES if language in available_tesseract_languages()]
    if not languages:
        raise RuntimeError("No Tesseract OCR languages are installed.")

    try:
        from PIL import Image
    except Exception as exc:
        raise RuntimeError("Pillow is required for OCR image preparation.") from exc

    with tempfile.TemporaryDirectory(prefix="webtoon-lens-ocr-") as temp_dir:
        image_path = Path(temp_dir) / "input.png"
        with Image.open(io.BytesIO(data)) as image:
            image = image.convert("RGB")
            width, height = image.size
            image.save(image_path)

        args = [
            command,
            str(image_path),
            "stdout",
            "--tessdata-dir",
            str(TESSDATA_DIR) if TESSDATA_DIR.exists() else str(Path(command).parent / "tessdata"),
            "-l",
            "+".join(languages),
            "--psm",
            "6",
            "-c",
            "tessedit_create_tsv=1",
        ]
        completed = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=45)
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr.strip() or "Tesseract OCR failed.")

    return tsv_to_segments(completed.stdout, width=width, height=height)


def easyocr_image(data: bytes, requested_language: str = "auto") -> list[dict[str, Any]]:
    try:
        from PIL import Image
    except Exception as exc:
        raise RuntimeError("Pillow is required for OCR image preparation.") from exc

    with tempfile.TemporaryDirectory(prefix="webtoon-lens-easyocr-") as temp_dir:
        image_path = Path(temp_dir) / "input.png"
        with Image.open(io.BytesIO(data)) as image:
            image = image.convert("RGB")
            width, height = image.size
            image.save(image_path)

        best_segments: list[dict[str, Any]] = []
        best_score = -1.0
        for languages in easyocr_language_sets(requested_language):
            segments = easyocr_segments_for_language(str(image_path), width=width, height=height, languages=tuple(languages))
            score = score_ocr_segments(segments)
            if score > best_score:
                best_segments = segments
                best_score = score

    return best_segments


def easyocr_segments_for_language(
    image_path: str,
    *,
    width: int,
    height: int,
    languages: tuple[str, ...],
) -> list[dict[str, Any]]:
    reader = easyocr_reader(languages)
    results = reader.readtext(
        image_path,
        detail=1,
        paragraph=False,
        text_threshold=0.45,
        low_text=0.3,
    )

    segments: list[dict[str, Any]] = []
    for index, (points, text, confidence) in enumerate(results):
        source_text = normalize_ocr_text(str(text))
        if not source_text:
            continue
        xs = [float(point[0]) for point in points]
        ys = [float(point[1]) for point in points]
        left, right = min(xs), max(xs)
        top, bottom = min(ys), max(ys)
        if right <= left or bottom <= top:
            continue
        segments.append(
            {
                "id": f"ocr-{index}",
                "text": source_text,
                "sourceText": source_text,
                "boundingBox": {
                    "x": clamp(left / width),
                    "y": clamp(top / height),
                    "width": clamp((right - left) / width),
                    "height": clamp((bottom - top) / height),
                },
                "confidence": round(float(confidence), 3),
                "readingOrder": index,
            }
        )

    return sorted(segments, key=lambda item: (item["boundingBox"]["y"], item["boundingBox"]["x"]))


def easyocr_language_sets(requested_language: str) -> list[list[str]]:
    if requested_language == "auto":
        return [["ja", "en"], ["ko", "en"], ["ch_sim", "en"], ["ch_tra", "en"], ["en"]]
    normalized = normalize_language_code(requested_language, "")
    mapping = {
        "ja": [["ja", "en"]],
        "ko": [["ko", "en"]],
        "zh": [["ch_sim", "en"], ["ch_tra", "en"]],
        "en": [["en"]],
        "fr": [["en"]],
    }
    if normalized in mapping:
        return mapping[normalized]
    return [["ja", "en"], ["ko", "en"], ["ch_sim", "en"], ["ch_tra", "en"], ["en"]]


def score_ocr_segments(segments: list[dict[str, Any]]) -> float:
    if not segments:
        return -1
    text = " ".join(str(segment.get("sourceText", "")) for segment in segments)
    confidence = sum(float(segment.get("confidence", 0)) for segment in segments) / max(1, len(segments))
    useful_chars = len(re.sub(r"\s|\?", "", text))
    return confidence * max(1, useful_chars)


@lru_cache(maxsize=8)
def easyocr_reader(languages: tuple[str, ...]) -> Any:
    import easyocr

    return easyocr.Reader(list(languages), gpu=False, verbose=False)


def tsv_to_segments(tsv: str, *, width: int, height: int) -> list[dict[str, Any]]:
    lines: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    reader = csv.DictReader(io.StringIO(tsv), delimiter="\t")
    for row in reader:
        text = (row.get("text") or "").strip()
        if not text or row.get("level") != "5":
            continue

        try:
            confidence = float(row.get("conf", "-1"))
            left = int(row.get("left", "0"))
            top = int(row.get("top", "0"))
            item_width = int(row.get("width", "0"))
            item_height = int(row.get("height", "0"))
        except ValueError:
            continue

        if confidence < 25 or item_width <= 0 or item_height <= 0:
            continue

        key = (
            row.get("block_num", "0"),
            row.get("par_num", "0"),
            row.get("line_num", "0"),
            row.get("page_num", "0"),
        )
        current = lines.setdefault(
            key,
            {
                "words": [],
                "confidences": [],
                "left": left,
                "top": top,
                "right": left + item_width,
                "bottom": top + item_height,
            },
        )
        current["words"].append(text)
        current["confidences"].append(confidence)
        current["left"] = min(current["left"], left)
        current["top"] = min(current["top"], top)
        current["right"] = max(current["right"], left + item_width)
        current["bottom"] = max(current["bottom"], top + item_height)

    segments: list[dict[str, Any]] = []
    sorted_lines = sorted(lines.values(), key=lambda item: (item["top"], item["left"]))
    for index, item in enumerate(sorted_lines):
        source_text = normalize_ocr_text(" ".join(item["words"]))
        if not source_text:
            continue
        confidence = sum(item["confidences"]) / max(1, len(item["confidences"]))
        segments.append(
            {
                "id": f"ocr-{index}",
                "text": source_text,
                "sourceText": source_text,
                "boundingBox": {
                    "x": clamp(item["left"] / width),
                    "y": clamp(item["top"] / height),
                    "width": clamp((item["right"] - item["left"]) / width),
                    "height": clamp((item["bottom"] - item["top"]) / height),
                },
                "confidence": round(confidence / 100, 3),
                "readingOrder": index,
            }
        )

    return segments


def normalize_ocr_text(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    cjk = r"\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af"
    return re.sub(fr"(?<=[{cjk}])\s+(?=[{cjk}])", "", text)


def clamp(value: float) -> float:
    return min(1, max(0, value))


def translate_payload(payload: dict[str, Any]) -> dict[str, Any]:
    glossary = [
        item
        for item in payload.get("glossary", [])
        if item.get("isLocked") and item.get("source") and item.get("translation")
    ]

    translated_segments = []
    detected_language: str | None = None
    for index, segment in enumerate(payload.get("segments", [])):
        source = str(segment.get("text") or segment.get("sourceText") or "")
        source_language = normalize_language_code(str(payload.get("sourceLanguage") or "auto"), source)
        if detected_language is None and source_language != "auto":
            detected_language = source_language
        translated = translate_text_to_french(source, source_language)
        translated = apply_locked_glossary(source, translated, glossary)
        translated_segments.append(
            {
                "id": str(segment.get("id", f"segment-{index}")),
                "sourceText": source,
                "translatedText": translated,
                "boundingBox": segment.get(
                    "boundingBox",
                    {"x": 0.12, "y": 0.16 + index * 0.18, "width": 0.42, "height": 0.1},
                ),
                "confidence": float(segment.get("confidence", 0.75)),
                "readingOrder": int(segment.get("readingOrder", index)),
            }
        )

    return {
        "detectedSourceLanguage": detected_language,
        "segments": translated_segments,
        "glossaryUpdates": [],
        "confidence": 0.7,
    }


def translate_text_to_french(text: str, source_language: str) -> str:
    if not text.strip():
        return ""
    if source_language == "fr":
        return text

    from argostranslate import translate

    installed_languages = translate.get_installed_languages()
    by_code = {language.code: language for language in installed_languages}
    source_code = source_language if source_language in by_code else detect_language_code(text)

    if source_code == "fr":
        return text
    if source_code == "en":
        return get_argos_translation(by_code, "en", "fr", text)

    english = get_argos_translation(by_code, source_code, "en", text)
    return get_argos_translation(by_code, "en", "fr", english)


def get_argos_translation(by_code: dict[str, Any], source: str, target: str, text: str) -> str:
    from_language = by_code.get(source)
    to_language = by_code.get(target)
    if not from_language or not to_language:
        raise RuntimeError(f"Missing Argos language package {source}->{target}.")

    translation = from_language.get_translation(to_language)
    if not translation:
        raise RuntimeError(f"Missing Argos translation package {source}->{target}.")
    return translation.translate(text)


def apply_locked_glossary(source: str, translated: str, glossary: list[dict[str, Any]]) -> str:
    result = translated
    for item in glossary:
        source_term = str(item.get("source", ""))
        translated_term = str(item.get("translation", ""))
        if not source_term or not translated_term:
            continue
        if source_term.lower() in source.lower():
            result = re.sub(re.escape(source_term), translated_term, result, flags=re.IGNORECASE)
        result = re.sub(re.escape(translated_term), translated_term, result, flags=re.IGNORECASE)
    return result


def normalize_language_code(source_language: str, text: str) -> str:
    mapping = {
        "jpn": "ja",
        "jp": "ja",
        "ja": "ja",
        "kor": "ko",
        "ko": "ko",
        "chi_sim": "zh",
        "chi_tra": "zh",
        "zh": "zh",
        "zho": "zh",
        "eng": "en",
        "en": "en",
        "fra": "fr",
        "fr": "fr",
    }
    if source_language != "auto":
        return mapping.get(source_language, source_language)
    return detect_language_code(text)


def detect_language_code(text: str) -> str:
    if re.search(r"[\uac00-\ud7af]", text):
        return "ko"
    if re.search(r"[\u3040-\u30ff]", text):
        return "ja"
    if re.search(r"[\u3400-\u9fff]", text):
        return "zh"
    if re.search(r"[A-Za-z]", text):
        return "en"
    return "en"


@lru_cache(maxsize=1)
def find_tesseract_command() -> str:
    configured = os.environ.get("TESSERACT_CMD")
    candidates = [
        configured,
        shutil.which("tesseract"),
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(candidate)
    return ""


@lru_cache(maxsize=1)
def available_tesseract_languages() -> list[str]:
    command = find_tesseract_command()
    if not command:
        return []
    args = [command]
    if TESSDATA_DIR.exists():
        args.extend(["--tessdata-dir", str(TESSDATA_DIR)])
    args.append("--list-langs")
    try:
        completed = subprocess.run(args, capture_output=True, text=True, timeout=10)
    except Exception:
        return []
    if completed.returncode != 0:
        return []
    return [line.strip() for line in completed.stdout.splitlines()[1:] if line.strip()]


@lru_cache(maxsize=1)
def available_translation_pairs() -> list[str]:
    try:
        from argostranslate import translate

        pairs: list[str] = []
        for source in translate.get_installed_languages():
            for target in translate.get_installed_languages():
                if source.code != target.code and source.get_translation(target):
                    pairs.append(f"{source.code}->{target.code}")
        return sorted(set(pairs))
    except Exception:
        return []


@lru_cache(maxsize=1)
def easyocr_available() -> bool:
    try:
        import easyocr  # noqa: F401

        return True
    except Exception:
        return False


def extract_images(markup: str, page_url: str) -> list[dict[str, str]]:
    extractor = ImageExtractor(page_url)
    extractor.feed(markup)

    normalized_markup = html_utils.unescape(markup).replace("\\/", "/")
    for raw in regex_image_candidates(normalized_markup):
        extractor.add_image(raw, alt="")

    return extractor.images


class ImageExtractor(HTMLParser):
    def __init__(self, page_url: str) -> None:
        super().__init__()
        self.page_url = page_url
        self.images: list[dict[str, str]] = []
        self.seen: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {name.lower(): value or "" for name, value in attrs}
        candidates = [
            attr.get("src", ""),
            attr.get("data-src", ""),
            attr.get("data-original", ""),
            attr.get("data-lazy-src", ""),
            attr.get("data-url", ""),
            attr.get("data-image", ""),
            attr.get("content", "") if tag.lower() == "meta" else "",
        ]

        candidates.extend(srcset_urls(attr.get("srcset", "")))
        candidates.extend(srcset_urls(attr.get("data-srcset", "")))
        candidates.extend(css_url_candidates(attr.get("style", "")))

        for raw in candidates:
            self.add_image(raw, attr.get("alt", ""))

    def add_image(self, raw: str, alt: str) -> None:
        raw = html_utils.unescape(raw.strip())
        if not raw or raw.startswith("data:"):
            return

        url = urllib.parse.urljoin(self.page_url, raw)
        if url in self.seen or not looks_like_image(url):
            return

        self.seen.add(url)
        self.images.append({"url": url, "alt": alt})


def regex_image_candidates(markup: str) -> list[str]:
    matches = re.findall(
        r"""(?:(?:https?:)?//|/)[^"'<>\s)]+?\.(?:jpg|jpeg|png|webp|gif|avif)(?:\?[^"'<>\s)]*)?""",
        markup,
        flags=re.IGNORECASE,
    )
    return [match for match in matches if not match.startswith("/>")]


def css_url_candidates(style: str) -> list[str]:
    return re.findall(
        r"""url\((?:'|")?([^'")]+)(?:'|")?\)""",
        style,
        flags=re.IGNORECASE,
    )


def srcset_urls(srcset: str) -> list[str]:
    if not srcset:
        return []
    return [part.strip().split(" ")[0] for part in srcset.split(",") if part.strip()]


def first_srcset_url(srcset: str) -> str:
    urls = srcset_urls(srcset)
    return urls[-1] if urls else ""


def looks_like_image(url: str) -> bool:
    lowered = url.lower().split("?")[0]
    return (
        bool(re.search(r"\.(jpg|jpeg|png|webp|gif|avif)$", lowered))
        or "/image" in lowered
        or "img" in lowered
    )


def request_for(url: str, *, referer: str = "", accept: str = "*/*") -> urllib.request.Request:
    headers = {
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
        "Accept": accept,
    }
    if referer:
        headers["Referer"] = referer

    return urllib.request.Request(url, headers=headers)


def fetch_url(url: str) -> str:
    with urllib.request.urlopen(
        request_for(
            url,
            referer=url,
            accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ),
        timeout=15,
    ) as response:
        data = response.read(5_000_000)
        charset = response.headers.get_content_charset() or "utf-8"
        return data.decode(charset, errors="replace")


def fetch_binary(url: str, *, referer: str = "") -> tuple[bytes, str]:
    with urllib.request.urlopen(
        request_for(
            url,
            referer=referer,
            accept="image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
        ),
        timeout=20,
    ) as response:
        return response.read(20_000_000), response.headers.get("Content-Type", "image/jpeg")


def main() -> None:
    port = int(os.environ.get("WEBTOON_LENS_PREVIEW_PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), PreviewHandler)
    print(f"Serving Webtoon Lens phone preview on http://0.0.0.0:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
