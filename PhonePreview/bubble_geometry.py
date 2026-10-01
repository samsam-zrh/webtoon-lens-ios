"""Regroupe les lignes dans un intérieur clair fermé ; sinon garde le dessin intact."""
from __future__ import annotations

import base64
import re
import cv2
import numpy as np


def union(boxes: list[dict]) -> dict:
    left = min(b["x"] for b in boxes)
    top = min(b["y"] for b in boxes)
    right = max(b["x"] + b["width"] for b in boxes)
    bottom = max(b["y"] + b["height"] for b in boxes)
    return dict(x=left, y=top, width=right-left, height=bottom-top)


def pixels(box: dict, width: int, height: int) -> tuple[int, int, int, int]:
    return (max(0, int(box["x"] * width)), max(0, int(box["y"] * height)),
            min(width, int((box["x"] + box["width"]) * width + 1)),
            min(height, int((box["y"] + box["height"]) * height + 1)))


def normalized(rect: tuple, width: int, height: int) -> dict:
    x, y, w, h = rect
    return dict(x=x/width, y=y/height, width=w/width, height=h/height)


def fit_dialogue(data: bytes, lines: list[dict]) -> list[dict]:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Image illisible. Utilisez PNG, JPEG ou WebP.")
    height, width = image.shape[:2]
    # Ferme les lettres, pas les contours. Les zones touchant le cadre sont refusées.
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    clear = ((hsv[:, :, 2] >= 225) & (hsv[:, :, 1] <= 38)).astype(np.uint8) * 255
    clear = cv2.morphologyEx(clear, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(clear, 8)
    groups: dict[str, list[dict]] = {}
    for index, line in enumerate(lines):
        if not line.get("sourceText", line.get("text", "")).strip():
            continue
        box = line.get("rawBoundingBox") or line["boundingBox"]
        x0, y0, x1, y1 = pixels(box, width, height)
        patch = labels[y0:y1, x0:x1]
        candidates, frequencies = np.unique(patch, return_counts=True)
        best = None
        for label, frequency in zip(candidates, frequencies):
            if not label:
                continue
            x, y, w, h, area = stats[label]
            if (x <= 1 or y <= 1 or x+w >= width-1 or y+h >= height-1
                    or area < 150 or area > width*height*0.65
                    or frequency < patch.size*0.45):
                continue
            if best is None or frequency > best[1]:
                best = (int(label), int(frequency))
        key = f"component-{best[0]}" if best else f"unverified-{index}"
        groups.setdefault(key, []).append(line)
    output = []
    for key, group in groups.items():
        group.sort(key=lambda line: (line["boundingBox"]["y"], line["boundingBox"]["x"]))
        raw = union([line.get("rawBoundingBox") or line["boundingBox"] for line in group])
        source = " ".join(line.get("sourceText") or line.get("text", "") for line in group)
        source = re.sub(r"(?<=[\u3400-\u9fff，。！？、])\s+(?=[\u3400-\u9fff，。！？、])", "", source)
        segment = dict(
            id=key, sourceText=source, text=source, rawBoundingBox=raw, boundingBox=raw,
            confidence=round(sum(line.get("confidence", 0.7) for line in group)/len(group), 3),
            bubbleDetected=False, renderMode="inspect",
            fontSizeSource=round(float(np.median([line["boundingBox"]["height"]*height for line in group]))*1.25, 2),
            imageWidth=width, imageHeight=height,
        )
        if key.startswith("component-"):
            label = int(key.split("-")[1])
            # Remplit seulement les trous de lettres du composant, puis érode la bordure.
            component = (labels == label).astype(np.uint8) * 255
            contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            filled = np.zeros_like(component)
            cv2.drawContours(filled, contours, -1, 255, cv2.FILLED)
            safe = cv2.erode(filled, np.ones((5, 5), np.uint8))
            x, y, w, h, _ = (int(v) for v in stats[label])
            # Rectangle inscrit conservateur, sans hypothèse d'ellipse.
            rx0, ry0, rx1, ry1 = pixels(raw, width, height)
            cx = int((rx0+rx1)/2)
            cy = int((ry0+ry1)/2)
            tx0, ty0, tx1, ty1 = rx0, ry0, rx1, ry1
            margin = max(3, int(segment["fontSizeSource"] * 0.14))
            if np.all(safe[ty0:ty1, tx0:tx1]):
                for _ in range(max(w, h)):
                    proposed = (max(x, tx0-1), max(y, ty0-1), min(x+w, tx1+1), min(y+h, ty1+1))
                    a, b, c, d = proposed
                    if proposed == (tx0, ty0, tx1, ty1) or not np.all(safe[b:d, a:c]):
                        break
                    tx0, ty0, tx1, ty1 = proposed
                tx0 += margin
                ty0 += margin
                tx1 -= margin
                ty1 -= margin
                if tx1 > tx0 and ty1 > ty0:
                    alpha = safe[y:y+h, x:x+w]
                    mask = np.full((h, w, 4), 255, dtype=np.uint8)
                    mask[:, :, 3] = alpha
                    success, encoded = cv2.imencode(".png", mask)
                    if not success:
                        raise RuntimeError("Encodage du masque de bulle impossible.")
                    fill = np.median(image[component > 0], axis=0)
                    segment.update(
                        boundingBox=normalized((x, y, w, h), width, height),
                        textBox=normalized((tx0, ty0, tx1-tx0, ty1-ty0), width, height),
                        bubbleDetected=True, renderMode="replace",
                        maskData="data:image/png;base64,"+base64.b64encode(encoded).decode(),
                        style=dict(fillColor="#%02x%02x%02x" % tuple(int(v) for v in fill[::-1]),
                                   textColor="#111111", fontWeight="700"),
                    )
        output.append(segment)
    output.sort(key=lambda s: (s["rawBoundingBox"]["y"], s["rawBoundingBox"]["x"]))
    for index, segment in enumerate(output):
        segment["id"] = f"bubble-{index}"
        segment["readingOrder"] = index
    return output
