"""Regroupe les lignes dans un intérieur uniforme sûr ; sinon garde le dessin intact."""
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


def background_colors(patch: np.ndarray) -> list[np.ndarray]:
    if not patch.size:
        return []
    quantized = patch.reshape(-1, 3).astype(np.int32) // 16
    bins = quantized[:, 0]*256 + quantized[:, 1]*16 + quantized[:, 2]
    counts = np.bincount(bins, minlength=4096)
    colors = []
    for index in np.argsort(counts)[-2:][::-1]:
        if counts[index] < len(bins)*0.18:
            continue
        color = np.median(patch.reshape(-1, 3)[bins == index], axis=0).astype(np.uint8)
        # Les intérieurs clairs gardent leur détection et leur masque historiques.
        _, saturation, value = cv2.cvtColor(color.reshape(1, 1, 3), cv2.COLOR_BGR2HSV)[0, 0]
        if value >= 225 and saturation <= 38:
            continue
        colors.append(color)
    return colors


def text_color(fill: np.ndarray) -> str:
    rgb = np.floor(fill[::-1]) / 255
    linear = np.where(rgb <= 0.04045, rgb/12.92, ((rgb+0.055)/1.055)**2.4)
    luminance = float(np.sum(linear * np.array([0.2126, 0.7152, 0.0722])))
    dark_luminance = ((17/255+0.055)/1.055)**2.4
    if (luminance+0.05)/(dark_luminance+0.05) >= 4.5:
        return "#111111"
    if 1.05/(luminance+0.05) >= 4.5:
        return "#ffffff"
    return "#000000"


def letter_pixels(patch: np.ndarray, fill: np.ndarray) -> np.ndarray:
    valid = np.zeros(patch.shape[:2], dtype=bool)
    difference = patch.astype(np.float32)-fill
    for ink in (0, 255):
        direction = ink-fill
        length = float(np.sum(direction*direction))
        if length == 0:
            continue
        amount = np.clip(np.sum(difference*direction, axis=2)/length, 0, 1)
        residual = difference-amount[:, :, None]*direction
        valid |= np.max(np.abs(residual), axis=2) <= 20
    return valid.astype(np.uint8)*255


def component_for_line(labels: np.ndarray, stats: np.ndarray, rect: tuple,
                       width: int, height: int, colored: bool) -> int | None:
    x0, y0, x1, y1 = rect
    patch = labels[y0:y1, x0:x1]
    candidates, frequencies = np.unique(patch, return_counts=True)
    best = None
    for label, frequency in zip(candidates, frequencies):
        if not label:
            continue
        x, y, w, h, area = stats[label]
        edges = sum((x <= 1, y <= 1, x+w >= width-1, y+h >= height-1))
        # Une bulle colorée coupée par une fenêtre OCR peut toucher un seul bord.
        # Un aplat ouvert sur plusieurs bords reste une illustration, pas une bulle.
        if (edges > (1 if colored else 0) or area < 150 or area > width*height*0.65
                or (colored and (w >= width*0.96 or h >= height*0.96))
                or frequency < patch.size*(0.30 if colored else 0.45)):
            continue
        if best is None or frequency > best[1]:
            best = (int(label), int(frequency))
    return best[0] if best else None


def fit_dialogue(data: bytes, lines: list[dict]) -> list[dict]:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Image illisible. Utilisez PNG, JPEG ou WebP.")
    height, width = image.shape[:2]
    # Détection historique des intérieurs clairs, sans relier leurs contours.
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    clear = ((hsv[:, :, 2] >= 225) & (hsv[:, :, 1] <= 38)).astype(np.uint8) * 255
    clear = cv2.morphologyEx(clear, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    _, labels, stats, _ = cv2.connectedComponentsWithStats(clear, 8)
    pools = [(labels, stats, None)]
    palette: dict[tuple, int] = {}
    groups: dict[str, list[dict]] = {}
    for index, line in enumerate(lines):
        if not line.get("sourceText", line.get("text", "")).strip():
            continue
        box = line.get("rawBoundingBox") or line["boundingBox"]
        x0, y0, x1, y1 = pixels(box, width, height)
        rect = (x0, y0, x1, y1)
        label = component_for_line(labels, stats, rect, width, height, False)
        pool = 0
        if label is None:
            for color in background_colors(image[y0:y1, x0:x1]):
                color_key = tuple(int(v) for v in color)
                color_key = next((known for known in palette
                                  if max(abs(a-b) for a, b in zip(known, color_key)) <= 8), color_key)
                if color_key not in palette:
                    lower = np.maximum(color.astype(np.int16)-20, 0).astype(np.uint8)
                    upper = np.minimum(color.astype(np.int16)+20, 255).astype(np.uint8)
                    matching = cv2.inRange(image, lower, upper)
                    uniform = cv2.morphologyEx(matching, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
                    _, color_labels, color_stats, _ = cv2.connectedComponentsWithStats(uniform, 8)
                    palette[color_key] = len(pools)
                    pools.append((color_labels, color_stats, matching))
                pool = palette[color_key]
                color_labels, color_stats, _ = pools[pool]
                label = component_for_line(color_labels, color_stats, rect, width, height, True)
                if label is not None:
                    break
        key = f"component-{pool}-{label}" if label is not None else f"unverified-{index}"
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
            _, pool, label = key.split("-")
            labels, stats, matching = pools[int(pool)]
            colored = matching is not None
            label = int(label)
            # Remplit seulement les trous de lettres du composant, puis érode la bordure.
            component = (labels == label).astype(np.uint8) * 255
            contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            filled = np.zeros_like(component)
            cv2.drawContours(filled, contours, -1, 255, cv2.FILLED)
            fill = np.median(image[(component & matching) > 0] if colored else image[component > 0], axis=0)
            if colored:
                letters = np.zeros_like(component)
                for line in group:
                    a, b, c, d = pixels(line.get("rawBoundingBox") or line["boundingBox"], width, height)
                    line_height = d-b
                    pad = max(2, int(line_height*0.15))
                    raw_rect = (a, b, c, d)
                    a, b, c, d = max(0, a-pad), max(0, b-pad), min(width, c+pad), min(height, d+pad)
                    letters[b:d, a:c] |= letter_pixels(image[b:d, a:c], fill)
                    # Vision omet parfois un point isolé : accepter seulement de petits
                    # signes monochromes voisins, pas un autre élément du dessin.
                    a, b, c, d = raw_rect
                    pad = max(2, int(line_height*1.2))
                    a, b, c, d = max(0, a-pad), max(0, b-pad), min(width, c+pad), min(height, d+pad)
                    ink = letter_pixels(image[b:d, a:c], fill) & cv2.bitwise_not(matching[b:d, a:c])
                    _, signs, sign_stats, _ = cv2.connectedComponentsWithStats(ink, 8)
                    sx, sy, sw, sh, area = sign_stats.T
                    ra, rb, rc, rd = raw_rect
                    nearby = line_height*0.8
                    small = np.where((sw <= line_height*0.35) & (sh <= line_height*0.35)
                                     & (area <= line_height**2*0.12)
                                     & (sx > 0) & (sy > 0) & (sx+sw < c-a) & (sy+sh < d-b)
                                     & (sx+a+sw >= ra-nearby) & (sx+a <= rc+nearby)
                                     & (sy+b+sh >= rb-nearby) & (sy+b <= rd+nearby))[0]
                    punctuation = np.isin(signs, small[small != 0]).astype(np.uint8)*255
                    sign_contours, _ = cv2.findContours(punctuation, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    cv2.drawContours(punctuation, sign_contours, -1, 255, cv2.FILLED)
                    letters[b:d, a:c] |= punctuation & letter_pixels(image[b:d, a:c], fill)
                # Les trous hors des lignes OCR peuvent être du dessin : ne pas les effacer.
                filled = (component & matching) | (filled & letters)
            safe = cv2.erode(filled, np.ones((5, 5), np.uint8))
            x, y, w, h, _ = (int(v) for v in stats[label])
            # Rectangle inscrit conservateur, sans hypothèse d'ellipse.
            rx0, ry0, rx1, ry1 = pixels(raw, width, height)
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
                    segment.update(
                        boundingBox=normalized((x, y, w, h), width, height),
                        textBox=normalized((tx0, ty0, tx1-tx0, ty1-ty0), width, height),
                        bubbleDetected=True, renderMode="replace",
                        maskData="data:image/png;base64,"+base64.b64encode(encoded).decode(),
                        style=dict(fillColor="#%02x%02x%02x" % tuple(int(v) for v in fill[::-1]),
                                   textColor=text_color(fill) if colored else "#111111", fontWeight="700"),
                    )
        output.append(segment)
    output.sort(key=lambda s: (s["rawBoundingBox"]["y"], s["rawBoundingBox"]["x"]))
    for index, segment in enumerate(output):
        segment["id"] = f"bubble-{index}"
        segment["readingOrder"] = index
    return output
