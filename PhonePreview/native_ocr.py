"""OCR Vision sur macOS ; compilation unique dans le runtime, jamais dans iOS."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

LOCK = threading.Lock()
SOURCE = Path(__file__).with_name("vision_ocr.swift")


def split_observation_lines(observations: list[dict]) -> list[dict]:
    lines = []
    for observation in observations:
        glyphs = observation.get("glyphs", [])
        original = observation.get("sourceText", "")
        if not glyphs or "".join(g["text"] for g in glyphs) != "".join(original.split()):
            lines.append(observation)
            continue
        rows = []
        for glyph in glyphs:
            box = glyph["boundingBox"]
            row = next((row for row in rows if
                        abs(box["y"]+box["height"]/2-row[0]["boundingBox"]["y"]
                            -row[0]["boundingBox"]["height"]/2)
                        <= max(box["height"], row[0]["boundingBox"]["height"])*.65), None)
            if row is None:
                rows.append([glyph])
            else:
                row.append(glyph)
        if len(rows) == 1:
            lines.append(observation)
            continue
        for index, row in enumerate(rows):
            left = min(g["boundingBox"]["x"] for g in row)
            top = min(g["boundingBox"]["y"] for g in row)
            right = max(g["boundingBox"]["x"]+g["boundingBox"]["width"] for g in row)
            bottom = max(g["boundingBox"]["y"]+g["boundingBox"]["height"] for g in row)
            text = "".join((" " if g["spaceBefore"] else "")+g["text"] for g in row).strip()
            lines.append({**observation, "id": f'{observation["id"]}-row-{index}',
                          "sourceText": text, "glyphs": row,
                          "boundingBox": dict(x=left, y=top, width=right-left, height=bottom-top)})
    return lines


def available() -> bool:
    return sys.platform == "darwin" and bool(shutil.which("xcrun"))


def recognize(data: bytes, language: str) -> list[dict]:
    runtime = Path(os.environ.get("WEBTOON_LENS_RUNTIME", Path.home() / "Library/Caches/WebtoonLens"))
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()[:12]
    executable = runtime / "bin" / f"vision-ocr-{digest}"
    with LOCK:
        if not executable.exists():
            executable.parent.mkdir(parents=True, exist_ok=True)
            result = subprocess.run(
                ["xcrun", "swiftc", "-O", str(SOURCE), "-o", str(executable)],
                capture_output=True, text=True, timeout=120,
            )
            if result.returncode:
                raise RuntimeError(f"Compilation OCR Vision impossible : {result.stderr.strip()}")
    with tempfile.NamedTemporaryFile(suffix=".png") as image:
        image.write(data)
        image.flush()
        result = subprocess.run(
            [str(executable), image.name, language], capture_output=True, text=True, timeout=60,
        )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Échec OCR Vision.")
    return split_observation_lines(json.loads(result.stdout))
