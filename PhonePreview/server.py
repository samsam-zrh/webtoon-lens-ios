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
import time
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
OLLAMA_URL = os.environ.get("WEBTOON_LENS_OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("WEBTOON_LENS_OLLAMA_MODEL", "qwen3:14b-q4_K_M")
WEBTOON_PHRASE_TRANSLATIONS = {
    "beast taming sect": "la Secte du Dressage des Betes",
    "beast-taming sect": "la Secte du Dressage des Betes",
    "demonic sect": "la Secte Demoniaque",
    "martial arts": "arts martiaux",
    "sword aura": "aura d'epee",
    "mana core": "noyau de mana",
}
COMMON_ENGLISH_WORDS = {
    "A", "AN", "AND", "ARE", "AS", "AT", "BE", "BEGINNING", "BUT", "BY", "CAN",
    "DID", "DO", "DOES", "DON", "FOR", "FROM", "GO", "HAD", "HAS", "HAVE", "HE",
    "HER", "HERE", "HIM", "HIS", "I", "IF", "IN", "INTO", "IS", "IT", "ITS", "JUST",
    "BEAST", "BEASTS", "EIGHT", "FIRST", "FIVE", "FOUR", "LIKE", "LEVEL", "LOOK",
    "ME", "MY", "NINE", "NO", "NOT", "OF", "ON", "ONE", "OR", "OUR", "PLACE",
    "SECT", "SEVEN", "SHOULD", "SIX", "SO", "SPIRIT", "TAMING", "TEN", "THAT",
    "THE", "THEIR", "THEM", "THEN", "THERE", "THESE", "THIS", "THOSE", "THOUGHT",
    "THREE", "TO", "TWO", "WAS", "WE", "WHAT", "WHEN", "WHERE", "WHO", "WHY",
    "WILL", "WITH", "YOU", "YOUR", "ZERO",
}


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
        has_ollama = ollama_model_available()
        has_translation = has_ollama or bool(translation_pairs)
        self.write_json(
            200,
            {
                "imageExtraction": True,
                "imageProxy": True,
                "ocr": bool(easyocr_available() or (tesseract_command and languages)),
                "translation": has_translation,
                "ocrEngine": "easyocr+tesseract" if easyocr_available() and tesseract_command else ("easyocr" if easyocr_available() else ("tesseract" if tesseract_command else None)),
                "ocrLanguages": languages,
                "translationEngine": translation_engine_name(translation_pairs),
                "ollamaModel": OLLAMA_MODEL if has_ollama else None,
                "translationPairs": translation_pairs,
                "message": "Local OCR and offline translation are available." if (easyocr_available() or tesseract_command) and has_translation else "OCR/translation dependencies are not fully installed.",
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
    candidates: list[tuple[str, list[dict[str, Any]]]] = []

    if requested_language in {"auto", "en", "eng"}:
        try:
            english_segments = tesseract_image(data, languages=["eng"])
            if english_segments:
                candidates.append(("tesseract-eng", english_segments))
        except Exception:
            pass

    if easyocr_available():
        try:
            segments = easyocr_image(data, requested_language=requested_language)
            if segments:
                candidates.append(("easyocr", segments))
        except Exception:
            pass

    try:
        tesseract_languages = tesseract_languages_for_request(requested_language)
        if tesseract_languages:
            segments = tesseract_image(data, languages=tesseract_languages)
            if segments:
                candidates.append(("tesseract", segments))
    except Exception:
        pass

    if candidates:
        grouped = group_ocr_segments(choose_ocr_candidate(candidates, requested_language))
        return fit_segments_to_speech_bubbles(data, grouped)

    command = find_tesseract_command()
    if not command:
        raise RuntimeError("Tesseract is not installed.")
    raise RuntimeError("OCR found no readable text.")


def tesseract_image(data: bytes, *, languages: list[str]) -> list[dict[str, Any]]:
    command = find_tesseract_command()
    if not command:
        raise RuntimeError("Tesseract is not installed.")

    languages = [language for language in languages if language in available_tesseract_languages()]
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


def tesseract_languages_for_request(requested_language: str) -> list[str]:
    normalized = normalize_language_code(requested_language, "")
    if requested_language == "auto":
        return OCR_LANGUAGES
    mapping = {
        "ja": ["jpn"],
        "ko": ["kor"],
        "zh": ["chi_sim", "chi_tra"],
        "en": ["eng"],
        "fr": ["fra", "eng"],
    }
    return mapping.get(normalized, OCR_LANGUAGES)


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
    question_marks = text.count("?")
    latin_words = re.findall(r"[A-Za-z]{2,}", text)
    cjk_chars = re.findall(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", text)
    return confidence * (useful_chars + len(latin_words) * 8 + len(cjk_chars) * 3) - question_marks * 8


def choose_ocr_candidate(
    candidates: list[tuple[str, list[dict[str, Any]]]],
    requested_language: str,
) -> list[dict[str, Any]]:
    normalized = normalize_language_code(requested_language, "")
    scored: list[tuple[float, str, list[dict[str, Any]]]] = []
    for engine, segments in candidates:
        text = " ".join(str(segment.get("sourceText", "")) for segment in segments)
        latin_words = re.findall(r"[A-Za-z]{2,}", text)
        cjk_chars = re.findall(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", text)
        score = score_ocr_segments(segments)

        if normalized == "en" and len(latin_words) >= 3:
            score += 60
        elif requested_language == "auto" and len(latin_words) >= 4 and not cjk_chars:
            score += 45
        elif normalized in {"ja", "ko", "zh"} and cjk_chars:
            score += 60

        if engine == "tesseract-eng" and len(latin_words) >= 3:
            score += 25

        scored.append((score, engine, segments))

    return max(scored, key=lambda item: item[0])[2]


def group_ocr_segments(segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not segments:
        return []

    ordered = sorted(segments, key=lambda item: (item["boundingBox"]["y"], item["boundingBox"]["x"]))
    heights = [float(item["boundingBox"]["height"]) for item in ordered]
    median_height = sorted(heights)[len(heights) // 2] if heights else 0.025
    max_gap = max(0.024, median_height * 2.1)

    groups: list[list[dict[str, Any]]] = []
    current: list[dict[str, Any]] = []
    for segment in ordered:
        if not current:
            current = [segment]
            continue

        current_box = merge_boxes([item["boundingBox"] for item in current])
        box = segment["boundingBox"]
        vertical_gap = float(box["y"]) - (float(current_box["y"]) + float(current_box["height"]))
        center_delta = abs(box_mid_x(box) - box_mid_x(current_box))
        overlap = horizontal_overlap(box, current_box)
        same_bubble = vertical_gap <= max_gap and (overlap > 0.16 or center_delta < 0.24)

        if same_bubble:
            current.append(segment)
        else:
            groups.append(current)
            current = [segment]

    if current:
        groups.append(current)

    return [merge_segment_group(group, index) for index, group in enumerate(groups)]


def merge_segment_group(group: list[dict[str, Any]], index: int) -> dict[str, Any]:
    text = normalize_ocr_text(" ".join(str(item.get("sourceText") or item.get("text") or "") for item in group))
    raw_box = merge_boxes([item["boundingBox"] for item in group])
    padded_box = expand_box(raw_box)
    confidence = sum(float(item.get("confidence", 0.7)) for item in group) / max(1, len(group))
    return {
        "id": f"bubble-{index}",
        "text": text,
        "sourceText": text,
        "boundingBox": padded_box,
        "rawBoundingBox": raw_box,
        "shape": "ellipse" if padded_box["width"] / max(0.001, padded_box["height"]) > 1.35 else "rounded",
        "confidence": round(confidence, 3),
        "readingOrder": index,
    }


def fit_segments_to_speech_bubbles(data: bytes, segments: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not segments:
        return segments

    try:
        import cv2
        import numpy as np
    except Exception:
        return segments

    image = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        return segments

    height, width = image.shape[:2]
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1]
    value = hsv[:, :, 2]
    b, g, r = cv2.split(image)
    white_mask = ((value > 235) & (saturation < 45)) | ((r > 224) & (g > 224) & (b > 224))
    mask = white_mask.astype("uint8") * 255
    mask = cv2.medianBlur(mask, 5)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8), iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8), iterations=1)

    component_count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    fitted: list[dict[str, Any]] = []
    for segment in segments:
        bubble_box = find_best_bubble_component(segment, labels, stats, image=image, width=width, height=height, component_count=component_count)
        if bubble_box:
            fitted.append({**segment, **bubble_box})
        else:
            fitted.append(segment)

    return fitted


def find_best_bubble_component(
    segment: dict[str, Any],
    labels: Any,
    stats: Any,
    *,
    image: Any,
    width: int,
    height: int,
    component_count: int,
) -> dict[str, Any] | None:
    raw_box = segment.get("rawBoundingBox") or segment.get("boundingBox")
    if not raw_box:
        return None

    left = int(float(raw_box["x"]) * width)
    top = int(float(raw_box["y"]) * height)
    right = int((float(raw_box["x"]) + float(raw_box["width"])) * width)
    bottom = int((float(raw_box["y"]) + float(raw_box["height"])) * height)
    left, top = max(0, left), max(0, top)
    right, bottom = min(width - 1, right), min(height - 1, bottom)
    if right <= left or bottom <= top:
        return None

    labels_to_score: dict[int, float] = {}
    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    sample_points = [(center_x, center_y)]
    for y in range(top, bottom + 1, max(1, (bottom - top) // 4 or 1)):
        for x in range(left, right + 1, max(1, (right - left) // 4 or 1)):
            sample_points.append((x, y))

    for x, y in sample_points:
        if 0 <= x < width and 0 <= y < height:
            label = int(labels[y, x])
            if label:
                labels_to_score[label] = labels_to_score.get(label, 0) + 4

    for label in range(1, component_count):
        x, y, w, h, area = [int(value) for value in stats[label]]
        if area < 900:
            continue
        if area > width * height * 0.55:
            continue
        if w > width * 0.96 and h > height * 0.96:
            continue
        overlap = pixel_overlap((left, top, right, bottom), (x, y, x + w, y + h))
        if overlap <= 0:
            continue
        raw_area = max(1, (right - left) * (bottom - top))
        overlap_ratio = overlap / raw_area
        if overlap_ratio < 0.08:
            continue
        labels_to_score[label] = labels_to_score.get(label, 0) + overlap_ratio * 100

    if not labels_to_score:
        return None

    best_label = max(labels_to_score.items(), key=lambda item: item[1])[0]
    x, y, w, h, area = [int(value) for value in stats[best_label]]
    if w <= 0 or h <= 0:
        return None

    pad = max(2, int(min(width, height) * 0.004))
    x0 = max(0, x - pad)
    y0 = max(0, y - pad)
    x1 = min(width, x + w + pad)
    y1 = min(height, y + h + pad)
    x0, y0, x1, y1 = clamp_oversized_bubble_box(
        component_box=(x0, y0, x1, y1),
        raw_box=(left, top, right, bottom),
        image_width=width,
        image_height=height,
    )
    normalized = {
        "x": clamp(x0 / width),
        "y": clamp(y0 / height),
        "width": clamp((x1 - x0) / width),
        "height": clamp((y1 - y0) / height),
    }
    fill_ratio = area / max(1, w * h)
    shape = "ellipse" if fill_ratio < 0.86 and w / max(1, h) > 1.12 else "rounded"
    return {
        "boundingBox": normalized,
        "shape": shape,
        "style": sample_bubble_style(image, labels, best_label, raw_box=(left, top, right, bottom)),
        "bubbleDetected": True,
    }


def clamp_oversized_bubble_box(
    *,
    component_box: tuple[int, int, int, int],
    raw_box: tuple[int, int, int, int],
    image_width: int,
    image_height: int,
) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = component_box
    raw_left, raw_top, raw_right, raw_bottom = raw_box
    box_width = x1 - x0
    box_height = y1 - y0
    raw_width = max(1, raw_right - raw_left)
    raw_height = max(1, raw_bottom - raw_top)
    component_ratio = (box_width * box_height) / max(1, image_width * image_height)
    too_wide = box_width > image_width * 0.96
    too_tall = box_height > image_height * 0.34
    too_large = component_ratio > 0.24

    if not (too_wide or too_tall or too_large):
        return component_box

    max_width = int(min(image_width * 0.94, max(raw_width * 4.4, image_width * 0.34)))
    max_height = int(min(image_height * 0.30, max(raw_height * 7.0, image_height * 0.15)))
    center_x = (raw_left + raw_right) // 2
    center_y = (raw_top + raw_bottom) // 2

    if box_width > max_width:
        half_width = max_width // 2
        x0 = max(0, center_x - half_width)
        x1 = min(image_width, center_x + half_width)

    if box_height > max_height:
        half_height = max_height // 2
        y0 = max(0, center_y - half_height)
        y1 = min(image_height, center_y + half_height)

    return x0, y0, max(x0 + 1, x1), max(y0 + 1, y1)


def sample_bubble_style(
    image: Any,
    labels: Any,
    label: int,
    *,
    raw_box: tuple[int, int, int, int],
) -> dict[str, str]:
    try:
        import numpy as np
    except Exception:
        return {}

    mask = labels == label
    fill_pixels = image[mask]
    if fill_pixels.size == 0:
        return {}

    fill_color = bgr_to_hex(np.median(fill_pixels, axis=0))
    raw_left, raw_top, raw_right, raw_bottom = raw_box
    patch = image[max(0, raw_top) : max(0, raw_bottom), max(0, raw_left) : max(0, raw_right)]
    if patch.size:
        luminance = patch[:, :, 2] * 0.2126 + patch[:, :, 1] * 0.7152 + patch[:, :, 0] * 0.0722
        dark_pixels = patch[luminance < 115]
        text_color = bgr_to_hex(np.median(dark_pixels, axis=0)) if dark_pixels.size else "#111111"
    else:
        text_color = "#111111"

    return {
        "fillColor": fill_color,
        "textColor": text_color,
        "borderColor": text_color,
    }


def bgr_to_hex(pixel: Any) -> str:
    values = [int(max(0, min(255, round(float(value))))) for value in pixel[:3]]
    blue, green, red = values
    return f"#{red:02x}{green:02x}{blue:02x}"


def pixel_overlap(first: tuple[int, int, int, int], second: tuple[int, int, int, int]) -> int:
    left = max(first[0], second[0])
    top = max(first[1], second[1])
    right = min(first[2], second[2])
    bottom = min(first[3], second[3])
    return max(0, right - left) * max(0, bottom - top)


def merge_boxes(boxes: list[dict[str, Any]]) -> dict[str, float]:
    left = min(float(box["x"]) for box in boxes)
    top = min(float(box["y"]) for box in boxes)
    right = max(float(box["x"]) + float(box["width"]) for box in boxes)
    bottom = max(float(box["y"]) + float(box["height"]) for box in boxes)
    return {"x": left, "y": top, "width": right - left, "height": bottom - top}


def expand_box(box: dict[str, Any]) -> dict[str, float]:
    width = float(box["width"])
    height = float(box["height"])
    pad_x = min(0.065, max(0.018, width * 0.12))
    pad_y = min(0.065, max(0.012, height * 0.34))
    left = clamp(float(box["x"]) - pad_x)
    top = clamp(float(box["y"]) - pad_y)
    right = clamp(float(box["x"]) + width + pad_x)
    bottom = clamp(float(box["y"]) + height + pad_y)
    return {"x": left, "y": top, "width": max(0.001, right - left), "height": max(0.001, bottom - top)}


def box_mid_x(box: dict[str, Any]) -> float:
    return float(box["x"]) + float(box["width"]) / 2


def horizontal_overlap(first: dict[str, Any], second: dict[str, Any]) -> float:
    left = max(float(first["x"]), float(second["x"]))
    right = min(float(first["x"]) + float(first["width"]), float(second["x"]) + float(second["width"]))
    overlap = max(0, right - left)
    return overlap / max(0.001, min(float(first["width"]), float(second["width"])))


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

    prepared_segments: list[dict[str, Any]] = []
    detected_language: str | None = None
    for index, segment in enumerate(payload.get("segments", [])):
        source = str(segment.get("text") or segment.get("sourceText") or "")
        source_language = normalize_language_code(str(payload.get("sourceLanguage") or "auto"), source)
        if detected_language is None and source_language != "auto":
            detected_language = source_language
        prepared_text, protected_terms = prepare_text_for_translation(source, source_language)
        prepared_segments.append(
            {
                "index": index,
                "segment": segment,
                "id": str(segment.get("id", f"segment-{index}")),
                "source": source,
                "sourceLanguage": source_language,
                "preparedText": prepared_text,
                "protectedTerms": protected_terms,
            }
        )

    ollama_translations = translate_segments_with_ollama(prepared_segments, glossary)

    translated_segments = []
    for item in prepared_segments:
        index = int(item["index"])
        segment = item["segment"]
        source = item["source"]
        source_language = item["sourceLanguage"]
        translated = ollama_translations.get(item["id"])
        if translated:
            translated = restore_protected_terms(translated, item["protectedTerms"])
        else:
            translated = translate_text_to_french(source, source_language)
        translated = apply_locked_glossary(source, translated, glossary)
        translated_segments.append(
            {
                "id": item["id"],
                "sourceText": source,
                "translatedText": translated,
                "boundingBox": segment.get(
                    "boundingBox",
                    {"x": 0.12, "y": 0.16 + index * 0.18, "width": 0.42, "height": 0.1},
                ),
                "rawBoundingBox": segment.get("rawBoundingBox"),
                "shape": segment.get("shape", "rounded"),
                "style": segment.get("style"),
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

    prepared_text, protected_terms = prepare_text_for_translation(text, source_language)

    from argostranslate import translate

    installed_languages = translate.get_installed_languages()
    by_code = {language.code: language for language in installed_languages}
    source_code = source_language if source_language in by_code else detect_language_code(prepared_text)

    if source_code == "fr":
        return restore_protected_terms(prepared_text, protected_terms)
    if source_code == "en":
        translated = translate_english_to_french(prepared_text, by_code)
        return restore_protected_terms(translated, protected_terms)

    english = get_argos_translation(by_code, source_code, "en", prepared_text)
    translated = translate_english_to_french(english, by_code)
    return restore_protected_terms(translated, protected_terms)


def translate_english_to_french(text: str, by_code: dict[str, Any]) -> str:
    transformer = english_french_transformer()
    if transformer:
        return transformer(text, max_length=256)[0]["translation_text"]
    return get_argos_translation(by_code, "en", "fr", text)


def translate_segments_with_ollama(
    prepared_segments: list[dict[str, Any]],
    glossary: list[dict[str, Any]],
) -> dict[str, str]:
    if not prepared_segments or not ollama_model_available():
        return {}

    payload = {
        "targetLanguage": "fr",
        "instructions": (
            "Traduis pour un webtoon/manhwa en francais naturel. "
            "Garde exactement les placeholders XWEBTOON0X, XWEBTOON1X, etc. "
            "Garde les noms propres et termes de pouvoir coherents. "
            "Ne traduis pas litteralement si la phrase doit etre reformulee."
        ),
        "glossary": [
            {
                "source": str(item.get("source", "")),
                "translation": str(item.get("translation", "")),
            }
            for item in glossary
        ],
        "segments": [
            {
                "id": item["id"],
                "sourceLanguage": item["sourceLanguage"],
                "text": item["preparedText"],
            }
            for item in prepared_segments
            if item.get("preparedText")
        ],
    }
    if not payload["segments"]:
        return {}

    request_payload = {
        "model": OLLAMA_MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are a professional webtoon translator. "
                    "Return only valid JSON in this exact shape: "
                    "{\"translations\":[{\"id\":\"...\",\"text\":\"...\"}]}. "
                    "No explanation."
                ),
            },
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False) + " /no_think"},
        ],
        "format": "json",
        "stream": False,
        "think": False,
        "options": {
            "temperature": 0.12,
            "top_p": 0.85,
            "num_ctx": 4096,
            "num_predict": 96 + 96 * len(payload["segments"]),
        },
    }

    try:
        data = json.dumps(request_payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            f"{OLLAMA_URL.rstrip('/')}/api/chat",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        started = time.time()
        with urllib.request.urlopen(request, timeout=28) as response:
            raw = json.loads(response.read().decode("utf-8"))
        content = str(raw.get("message", {}).get("content", "")).strip()
        parsed = parse_json_object(content)
        translations = parsed.get("translations", [])
        result = {
            str(item.get("id", "")): str(item.get("text", "")).strip()
            for item in translations
            if item.get("id") and item.get("text")
        }
        if result:
            print(f"Ollama translated {len(result)} segments in {time.time() - started:.2f}s")
        return result
    except Exception as exc:
        print(f"Ollama translation fallback: {exc}")
        return {}


def parse_json_object(content: str) -> dict[str, Any]:
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        start = content.find("{")
        end = content.rfind("}")
        if start >= 0 and end > start:
            return json.loads(content[start : end + 1])
        raise


@lru_cache(maxsize=1)
def english_french_transformer() -> Any | None:
    try:
        from transformers import pipeline

        return pipeline("translation", model="Helsinki-NLP/opus-mt-en-fr", device=-1)
    except Exception:
        return None


@lru_cache(maxsize=1)
def english_french_transformer_available() -> bool:
    try:
        import transformers  # noqa: F401

        return True
    except Exception:
        return False


@lru_cache(maxsize=1)
def ollama_model_available() -> bool:
    try:
        with urllib.request.urlopen(f"{OLLAMA_URL.rstrip('/')}/api/tags", timeout=3) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return any(model.get("name") == OLLAMA_MODEL or model.get("model") == OLLAMA_MODEL for model in payload.get("models", []))
    except Exception:
        return False


def translation_engine_name(translation_pairs: list[str]) -> str | None:
    if ollama_model_available():
        return f"ollama:{OLLAMA_MODEL}"
    if english_french_transformer_available() and translation_pairs:
        return "transformers+argos"
    if translation_pairs:
        return "argos"
    return None


def prepare_text_for_translation(text: str, source_language: str) -> tuple[str, dict[str, str]]:
    protected_terms: dict[str, str] = {}
    prepared = text

    for phrase, translation in WEBTOON_PHRASE_TRANSLATIONS.items():
        placeholder = f"XWEBTOON{len(protected_terms)}X"
        pattern = re.compile(re.escape(phrase), flags=re.IGNORECASE)
        if pattern.search(prepared):
            prepared = pattern.sub(placeholder, prepared)
            protected_terms[placeholder] = translation

    if normalize_language_code(source_language, text) == "en":
        for token in sorted(set(re.findall(r"\b[A-Z][A-Z0-9]{3,}\b", prepared)), key=len, reverse=True):
            if token in COMMON_ENGLISH_WORDS or token.startswith("XWEBTOON"):
                continue
            placeholder = f"XWEBTOON{len(protected_terms)}X"
            protected_terms[placeholder] = token.title()
            prepared = re.sub(rf"\b{re.escape(token)}\b", placeholder, prepared)
        prepared = normalize_english_casing(prepared)

    return prepared, protected_terms


def normalize_english_casing(text: str) -> str:
    letters = re.findall(r"[A-Za-z]", text)
    if not letters:
        return text
    uppercase_ratio = sum(1 for letter in letters if letter.isupper()) / len(letters)
    if uppercase_ratio < 0.72:
        return text

    lowered = text.lower()
    lowered = re.sub(r"\bxwebtoon(\d+)x\b", lambda match: f"XWEBTOON{match.group(1)}X", lowered)
    lowered = re.sub(r"\bi\b", "I", lowered)
    lowered = re.sub(r"(^|[.!?]\s+)([a-z])", lambda match: match.group(1) + match.group(2).upper(), lowered)
    return lowered


def restore_protected_terms(text: str, protected_terms: dict[str, str]) -> str:
    result = text
    for placeholder, value in protected_terms.items():
        result = re.sub(re.escape(placeholder), value, result, flags=re.IGNORECASE)
    return cleanup_french_webtoon_terms(result)


def cleanup_french_webtoon_terms(text: str) -> str:
    result = re.sub(r"\bLa\s+premi(?:e|\u00e8)re\s+place\s+(?:a|\u00e0)\s+regarder", "Le premier endroit ou chercher", text, flags=re.IGNORECASE)
    result = re.sub(r"\bLe\s+premier\s+lieu\s+(?:a|\u00e0)\s+regarder", "Le premier endroit ou chercher", result, flags=re.IGNORECASE)
    result = re.sub(r"\ble\s+la\s+Secte", "la Secte", result, flags=re.IGNORECASE)
    result = re.sub(r"\ble\s+Secte", "la Secte", result, flags=re.IGNORECASE)
    result = re.sub(r"\bdu\s+la\s+Secte", "de la Secte", result, flags=re.IGNORECASE)
    return result


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
