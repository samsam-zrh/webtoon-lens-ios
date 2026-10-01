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
    return json.loads(result.stdout)
