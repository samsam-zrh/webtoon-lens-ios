from __future__ import annotations

import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent


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

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/v1/webtoon/translate":
            self.send_error(404, "Unknown endpoint")
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)

        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        response = translate_payload(payload)
        data = json.dumps(response, ensure_ascii=False).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def translate_payload(payload: dict[str, Any]) -> dict[str, Any]:
    glossary = {
        str(item.get("source", "")).lower(): str(item.get("translation", ""))
        for item in payload.get("glossary", [])
        if item.get("isLocked") and item.get("source") and item.get("translation")
    }

    segments = []
    for index, segment in enumerate(payload.get("segments", [])):
        source = str(segment.get("text") or segment.get("sourceText") or "")
        translated = apply_glossary(source, glossary)
        segments.append(
            {
                "id": str(segment.get("id", f"segment-{index}")),
                "sourceText": source,
                "translatedText": f"[fr] {translated}",
                "boundingBox": segment.get(
                    "boundingBox",
                    {"x": 0.12, "y": 0.16 + index * 0.18, "width": 0.42, "height": 0.1},
                ),
                "confidence": float(segment.get("confidence", 0.86)),
                "readingOrder": int(segment.get("readingOrder", index)),
            }
        )

    return {
        "detectedSourceLanguage": payload.get("sourceLanguage") if payload.get("sourceLanguage") != "auto" else None,
        "segments": segments,
        "glossaryUpdates": [],
        "confidence": 0.82,
    }


def apply_glossary(text: str, glossary: dict[str, str]) -> str:
    result = text
    for source, translation in glossary.items():
        result = result.replace(source, translation)
        result = result.replace(source.title(), translation)
        result = result.replace(source.upper(), translation)
    return result


def main() -> None:
    port = int(os.environ.get("WEBTOON_LENS_PREVIEW_PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), PreviewHandler)
    print(f"Serving Webtoon Lens phone preview on http://0.0.0.0:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
