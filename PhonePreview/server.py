from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
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

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/v1/webtoon/extract":
            self.handle_extract(parsed)
            return
        if parsed.path == "/v1/webtoon/image":
            self.handle_image_proxy(parsed)
            return
        super().do_GET()

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

    def handle_extract(self, parsed: urllib.parse.ParseResult) -> None:
        query = urllib.parse.parse_qs(parsed.query)
        url = query.get("url", [""])[0]
        if not url:
            self.send_error(400, "Missing url")
            return

        try:
            html = fetch_url(url)
            extractor = ImageExtractor(url)
            extractor.feed(html)
            images = extractor.images
        except Exception as exc:
            self.send_error(502, f"Extraction failed: {exc}")
            return

        data = json.dumps({"pageURL": url, "images": images[:80]}, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_image_proxy(self, parsed: urllib.parse.ParseResult) -> None:
        query = urllib.parse.parse_qs(parsed.query)
        url = query.get("url", [""])[0]
        if not url:
            self.send_error(400, "Missing url")
            return

        try:
            data, content_type = fetch_binary(url)
        except Exception as exc:
            self.send_error(502, f"Image proxy failed: {exc}")
            return

        self.send_response(200)
        self.send_header("Content-Type", content_type or "image/jpeg")
        self.send_header("Cache-Control", "public, max-age=3600")
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


class ImageExtractor(HTMLParser):
    def __init__(self, page_url: str) -> None:
        super().__init__()
        self.page_url = page_url
        self.images: list[dict[str, str]] = []
        self.seen: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() not in {"img", "source"}:
            return

        attr = {name.lower(): value or "" for name, value in attrs}
        raw = (
            attr.get("data-src")
            or attr.get("data-original")
            or attr.get("data-lazy-src")
            or attr.get("src")
            or first_srcset_url(attr.get("srcset", ""))
        )
        if not raw:
            raw = first_srcset_url(attr.get("data-srcset", ""))
        if not raw or raw.startswith("data:"):
            return

        url = urllib.parse.urljoin(self.page_url, raw)
        if url in self.seen or not looks_like_image(url):
            return
        self.seen.add(url)
        self.images.append({"url": url, "alt": attr.get("alt", "")})


def first_srcset_url(srcset: str) -> str:
    if not srcset:
        return ""
    candidates = [part.strip().split(" ")[0] for part in srcset.split(",") if part.strip()]
    return candidates[-1] if candidates else ""


def looks_like_image(url: str) -> bool:
    lowered = url.lower().split("?")[0]
    return bool(re.search(r"\.(jpg|jpeg|png|webp|gif|avif)$", lowered)) or "/image" in lowered or "img" in lowered


def request_for(url: str) -> urllib.request.Request:
    return urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            "Accept": "text/html,image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
        },
    )


def fetch_url(url: str) -> str:
    with urllib.request.urlopen(request_for(url), timeout=15) as response:
        data = response.read(5_000_000)
        charset = response.headers.get_content_charset() or "utf-8"
        return data.decode(charset, errors="replace")


def fetch_binary(url: str) -> tuple[bytes, str]:
    with urllib.request.urlopen(request_for(url), timeout=20) as response:
        return response.read(20_000_000), response.headers.get("Content-Type", "image/jpeg")


def main() -> None:
    port = int(os.environ.get("WEBTOON_LENS_PREVIEW_PORT", "8787"))
    server = ThreadingHTTPServer(("0.0.0.0", port), PreviewHandler)
    print(f"Serving Webtoon Lens phone preview on http://0.0.0.0:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
