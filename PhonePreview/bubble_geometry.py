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
        # Les intérieurs clairs sont déjà inclus dans le premier masque.
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


def letter_pixels(patch: np.ndarray, fill: np.ndarray, inks: list | None = None) -> np.ndarray:
    valid = np.zeros(patch.shape[:2], dtype=bool)
    difference = patch.astype(np.float32)-fill
    for ink in [np.zeros(3), np.full(3, 255), *(inks or [])]:
        direction = ink-fill
        length = float(np.sum(direction*direction))
        if length == 0:
            continue
        amount = np.clip(np.sum(difference*direction, axis=2)/length, 0, 1)
        residual = difference-amount[:, :, None]*direction
        valid |= np.max(np.abs(residual), axis=2) <= 20
    # Une encre dégradée mélange son ton avec le noir, puis avec le fond antialiasé.
    for ink in inks or []:
        hue = ink/max(float(np.max(ink)), 1)*255
        background_length = float(np.sum(fill*fill))
        cross = float(np.sum(fill*hue))
        ink_length = float(np.sum(hue*hue))
        shade = np.sum(patch.astype(float)*hue, axis=2)/ink_length
        valid |= ((shade >= 0) & (shade <= 1.05)
                  & (np.max(np.abs(patch-shade[:, :, None]*hue), axis=2) <= 32))
        determinant = background_length*ink_length-cross*cross
        if determinant <= 0:
            continue
        background_dot = np.sum(patch.astype(float)*fill, axis=2)
        ink_dot = np.sum(patch.astype(float)*hue, axis=2)
        background_amount = (background_dot*ink_length-ink_dot*cross)/determinant
        ink_amount = (ink_dot*background_length-background_dot*cross)/determinant
        projected = background_amount[:, :, None]*fill+ink_amount[:, :, None]*hue
        valid |= ((background_amount >= -.05) & (ink_amount >= -.05)
                  & (background_amount+ink_amount <= 1.05)
                  & (np.max(np.abs(patch-projected), axis=2) <= 32))
    return valid.astype(np.uint8)*255


def ink_colors(image: np.ndarray, group: list[dict], fill: np.ndarray) -> list[np.ndarray]:
    patches = [image[b:d, a:c].reshape(-1, 3) for a, b, c, d in
               (pixels(line.get("rawBoundingBox") or line["boundingBox"], image.shape[1], image.shape[0])
                for line in group)]
    samples = np.concatenate(patches)
    foreground = samples[np.max(np.abs(samples.astype(float)-fill), axis=1) > 65]
    if not len(foreground):
        return []
    bins = foreground.astype(np.int32)//32
    keys = bins[:, 0]*64+bins[:, 1]*8+bins[:, 2]
    counts = np.bincount(keys, minlength=512)
    colors = []
    x0, y0, x1, y1 = pixels(union([line.get("rawBoundingBox") or line["boundingBox"] for line in group]),
                           image.shape[1], image.shape[0])
    region = image[y0:y1, x0:x1]
    for key in np.argsort(counts)[-6:][::-1]:
        if counts[key] < max(6, len(keys)*.025):
            continue
        color = np.median(foreground[keys == key], axis=0)
        if max(color)-min(color) < 40:
            continue
        if letter_pixels(color.reshape(1, 1, 3), fill)[0, 0]:
            continue
        mask = cv2.inRange(region, np.clip(color-30, 0, 255).astype(np.uint8),
                           np.clip(color+30, 0, 255).astype(np.uint8))
        ink_area = np.zeros(mask.shape, dtype=np.uint8)
        for a, b, c, d in (pixels(line.get("rawBoundingBox") or line["boundingBox"],
                                 image.shape[1], image.shape[0]) for line in group):
            ink_area[b-y0:d-y0, a-x0:c-x0] = mask[b-y0:d-y0, a-x0:c-x0]
        _, _, stats, _ = cv2.connectedComponentsWithStats(ink_area, connectivity=8)
        if np.count_nonzero(stats[1:, cv2.CC_STAT_AREA] >= 3) < 3:
            continue
        colors.append(color)
    return colors


def line_height(line: dict, height: int) -> float:
    boxes = [g["boundingBox"] for g in line.get("glyphs", []) if g["text"].isalpha()]
    return float(np.median([b["height"] for b in boxes]))*height if boxes else line["boundingBox"]["height"]*height


def source_text_color(fill: np.ndarray, inks: list[np.ndarray]) -> str:
    def luminance(bgr):
        values = np.floor(bgr[::-1])/255
        linear = np.where(values <= .04045, values/12.92, ((values+.055)/1.055)**2.4)
        return float(np.sum(linear*np.array([.2126, .7152, .0722])))
    background = luminance(fill)
    for ink in inks:
        foreground = luminance(ink)
        if (max(background, foreground)+.05)/(min(background, foreground)+.05) >= 4.5:
            return "#%02x%02x%02x" % tuple(int(value) for value in ink[::-1])
    return text_color(fill)


def paragraph_groups(lines: list[dict], height: int, distance: np.ndarray | None = None) -> list[list[dict]]:
    groups = []
    for line in sorted(lines, key=lambda item: (item["boundingBox"]["y"], item["boundingBox"]["x"])):
        box = line.get("rawBoundingBox") or line["boundingBox"]
        related = []
        for index, group in enumerate(groups):
            for previous in group:
                other = previous.get("rawBoundingBox") or previous["boundingBox"]
                gap = max(0, box["y"]-other["y"]-other["height"],
                          other["y"]-box["y"]-box["height"])*height
                overlap = max(0, min(box["x"]+box["width"], other["x"]+other["width"])
                              -max(box["x"], other["x"]))
                nearby = gap <= max(line_height(line, height), line_height(previous, height))*1.7
                if distance is not None:
                    width = distance.shape[1]
                    first = (int((box["x"]+box["width"]/2)*width),
                             int((box["y"]+box["height"]/2)*height))
                    second = (int((other["x"]+other["width"]/2)*width),
                              int((other["y"]+other["height"]/2)*height))
                    samples = [distance[min(height-1, max(0, round(first[1]*t+second[1]*(1-t)))),
                                        min(width-1, max(0, round(first[0]*t+second[0]*(1-t))))]
                               for t in np.linspace(0, 1, 9)]
                    nearby = (gap <= max(line_height(line, height), line_height(previous, height))*4
                              and min(samples) >= min(samples[0], samples[-1])*.55)
                if nearby and overlap >= min(box["width"], other["width"])*.2:
                    related.append(index)
                    break
        if not related:
            groups.append([line])
        else:
            groups[related[0]].append(line)
            for index in reversed(related[1:]):
                groups[related[0]].extend(groups.pop(index))
    return groups


def component_parts(component: np.ndarray) -> list[np.ndarray]:
    x, y, w, h = cv2.boundingRect(component)
    outline = component[y:y+h, x:x+w].copy()
    contours, _ = cv2.findContours(outline, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(outline, contours, -1, 255, cv2.FILLED)
    distance = cv2.distanceTransform(np.pad(outline, 1), cv2.DIST_L2, 5)[1:-1, 1:-1]
    cores = (distance >= distance.max()*.55).astype(np.uint8)
    count, seeds, stats, _ = cv2.connectedComponentsWithStats(cores, connectivity=8)
    candidates = [index for index in range(1, count)
                  if stats[index, cv2.CC_STAT_AREA] >= max(150, np.count_nonzero(outline)*.015)]
    if len(candidates) < 2:
        return [component]
    distances = [cv2.distanceTransform((seeds != index).astype(np.uint8), cv2.DIST_L2, 5)
                 for index in candidates]
    nearest = np.argmin(distances, axis=0)
    parts = []
    for index in range(len(candidates)):
        part = np.zeros_like(component)
        part[y:y+h, x:x+w] = component[y:y+h, x:x+w] & ((nearest == index).astype(np.uint8)*255)
        parts.append(part)
    return parts


def bounded_component(component: np.ndarray) -> bool:
    height, width = component.shape
    x, y, w, h = cv2.boundingRect(component)
    edges = sum((x == 0, y == 0, x+w == width, y+h == height))
    return (edges <= 1 and np.count_nonzero(component) >= 150
            and (not edges or (np.count_nonzero(component) <= width*height*.65
                               and w < width*.96 and h < height*.96)))


def text_regions(image: np.ndarray, matching: np.ndarray, group: list[dict],
                 fill: np.ndarray, inks: list[np.ndarray]) -> np.ndarray:
    height, width = image.shape[:2]
    letters = np.zeros_like(matching)
    for line in group:
        a, b, c, d = pixels(line.get("rawBoundingBox") or line["boundingBox"], width, height)
        line_height = d-b
        pad = max(2, int(line_height*(.45 if inks else .15)))
        raw_rect = (a, b, c, d)
        a, b, c, d = max(0, a-pad), max(0, b-pad), min(width, c+pad), min(height, d+pad)
        letters[b:d, a:c] |= letter_pixels(image[b:d, a:c], fill, inks)
        # Vision peut omettre une petite ponctuation isolée, notamment « 。 ».
        a, b, c, d = raw_rect
        pad = max(2, int(line_height*1.2))
        a, b, c, d = max(0, a-pad), max(0, b-pad), min(width, c+pad), min(height, d+pad)
        ink = letter_pixels(image[b:d, a:c], fill, inks) & cv2.bitwise_not(matching[b:d, a:c])
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
        contours, _ = cv2.findContours(punctuation, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(punctuation, contours, -1, 255, cv2.FILLED)
        letters[b:d, a:c] |= punctuation & letter_pixels(image[b:d, a:c], fill, inks)
    return letters


def component_for_line(labels: np.ndarray, stats: np.ndarray, rect: tuple,
                       width: int, height: int, *, allow_open: bool = False) -> int | None:
    x0, y0, x1, y1 = rect
    patch = labels[y0:y1, x0:x1]
    candidates, frequencies = np.unique(patch, return_counts=True)
    best = None
    for label, frequency in zip(candidates, frequencies):
        if not label:
            continue
        x, y, w, h, area = stats[label]
        edges = sum((x == 0, y == 0, x+w == width, y+h == height))
        # Une bulle coupée par une fenêtre OCR peut toucher un seul bord.
        # Un aplat ouvert sur plusieurs bords reste une illustration, pas une bulle.
        if (area < 150 or (not allow_open and (edges > 1
                or (edges and (area > width*height*0.65 or w >= width*0.96 or h >= height*0.96))))
                or frequency < patch.size*0.30):
            continue
        if best is None or frequency > best[1]:
            best = (int(label), int(frequency))
    return best[0] if best else None


def fit_dialogue(data: bytes, lines: list[dict]) -> list[dict]:
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Image illisible. Utilisez PNG, JPEG ou WebP.")
    height, width = image.shape[:2]
    # Ne pas fermer le masque : cela relierait les bulles au fond à travers un contour fin.
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    clear = ((hsv[:, :, 2] >= 225) & (hsv[:, :, 1] <= 38)).astype(np.uint8) * 255
    _, labels, stats, _ = cv2.connectedComponentsWithStats(clear, connectivity=4)
    pools = [(labels, stats, clear)]
    palette: dict[tuple, int] = {}
    groups: dict[str, list[dict]] = {}
    for index, line in enumerate(lines):
        if not line.get("sourceText", line.get("text", "")).strip():
            continue
        box = line.get("rawBoundingBox") or line["boundingBox"]
        x0, y0, x1, y1 = pixels(box, width, height)
        rect = (x0, y0, x1, y1)
        label = component_for_line(labels, stats, rect, width, height, allow_open=True)
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
                    _, color_labels, color_stats, _ = cv2.connectedComponentsWithStats(matching, connectivity=4)
                    palette[color_key] = len(pools)
                    pools.append((color_labels, color_stats, matching))
                pool = palette[color_key]
                color_labels, color_stats, _ = pools[pool]
                label = component_for_line(color_labels, color_stats, rect, width, height, allow_open=True)
                if label is not None:
                    break
        key = f"component-{pool}-{label}" if label is not None else f"unverified-{index}"
        groups.setdefault(key, []).append(line)
    output = []
    paragraphs = []
    for key, lines in groups.items():
        if key.startswith("component-"):
            _, pool, label = key.split("-")
            component_labels, component_stats, _ = pools[int(pool)]
            parts = component_parts((component_labels == int(label)).astype(np.uint8)*255)
            assigned = [[] for _ in parts]
            for line in lines:
                a, b, c, d = pixels(line.get("rawBoundingBox") or line["boundingBox"], width, height)
                index = int(np.argmax([np.count_nonzero(part[b:d, a:c]) for part in parts]))
                assigned[index].append(line)
            for part, observations in zip(parts, assigned):
                if not observations:
                    continue
                distance = None
                if bounded_component(part):
                    outline = part.copy()
                    contours, _ = cv2.findContours(outline, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    cv2.drawContours(outline, contours, -1, 255, cv2.FILLED)
                    distance = cv2.distanceTransform(np.pad(outline, 1), cv2.DIST_L2, 5)[1:-1, 1:-1]
                paragraphs.extend((key, part, group) for group in paragraph_groups(observations, height, distance))
        else:
            paragraphs.extend((key, None, group) for group in paragraph_groups(lines, height))
    for key, component, group in paragraphs:
        group.sort(key=lambda line: (line["boundingBox"]["y"], line["boundingBox"]["x"]))
        raw = union([line.get("rawBoundingBox") or line["boundingBox"] for line in group])
        source = " ".join(line.get("sourceText") or line.get("text", "") for line in group)
        source = re.sub(r"(?<=[\u3400-\u9fff，。！？、])\s+(?=[\u3400-\u9fff，。！？、])", "", source)
        segment = dict(
            id=key, sourceText=source, text=source, rawBoundingBox=raw, boundingBox=raw,
            confidence=round(sum(line.get("confidence", 0.7) for line in group)/len(group), 3),
            bubbleDetected=False, renderMode="inspect",
            fontSizeSource=round(float(np.median([line_height(line, height) for line in group]))*1.25, 2),
            imageWidth=width, imageHeight=height,
        )
        if key.startswith("component-"):
            _, pool, label = key.split("-")
            labels, stats, matching = pools[int(pool)]
            label = int(label)
            # Remplit seulement les trous de lettres du composant, puis érode la bordure.
            contours, _ = cv2.findContours(component, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            filled = np.zeros_like(component)
            cv2.drawContours(filled, contours, -1, 255, cv2.FILLED)
            fill = np.median(image[(component & matching) > 0], axis=0)
            inks = ink_colors(image, group, fill)
            strict = bounded_component(component)
            if not strict and not inks:
                output.append(segment)
                continue
            letters = text_regions(image, matching, group, fill, inks)
            filled = (component & matching) | (filled & letters)
            safe = cv2.erode(filled, np.ones((5, 5), np.uint8))
            x, y, w, h = cv2.boundingRect(component)
            # Rectangle inscrit conservateur, sans hypothèse d'ellipse.
            rx0, ry0, rx1, ry1 = pixels(raw, width, height)
            tx0, ty0, tx1, ty1 = rx0, ry0, rx1, ry1
            margin = max(3, int(segment["fontSizeSource"] * 0.14))
            line_rects = [pixels(line.get("rawBoundingBox") or line["boundingBox"], width, height)
                          for line in group]
            def line_is_safe(rect):
                a, b, c, d = rect
                if np.all(safe[b:d, a:c]):
                    return True
                foreground = np.max(np.abs(image[b:d, a:c].astype(float)-fill), axis=2) > 65
                return bool(inks and np.any(foreground) and np.all(safe[b:d, a:c][foreground]))
            def observation_is_safe(line, rect):
                if line_is_safe(rect):
                    return True
                glyph_rects = {pixels(glyph["boundingBox"], width, height)
                               for glyph in line.get("glyphs", []) if glyph["text"].strip()}
                return bool(glyph_rects and all(line_is_safe(box) for box in glyph_rects))
            if all(observation_is_safe(line, rect) for line, rect in zip(group, line_rects)):
                # L'union de lignes de longueurs différentes peut dépasser une courbe.
                while tx1 > tx0 and ty1 > ty0 and not np.all(safe[ty0:ty1, tx0:tx1]):
                    tx0, ty0, tx1, ty1 = tx0+1, ty0+1, tx1-1, ty1-1
                if tx1 <= tx0 or ty1 <= ty0:
                    output.append(segment)
                    continue
                base = (tx0, ty0, tx1, ty1)
                low, high = 0, max(w, h)
                while low < high:
                    expansion = (low+high+1)//2
                    a, b, c, d = (max(x, base[0]-expansion), max(y, base[1]-expansion),
                                  min(x+w, base[2]+expansion), min(y+h, base[3]+expansion))
                    if np.all(safe[b:d, a:c]):
                        low = expansion
                    else:
                        high = expansion-1
                tx0, ty0, tx1, ty1 = (max(x, base[0]-low), max(y, base[1]-low),
                                      min(x+w, base[2]+low), min(y+h, base[3]+low))
                tx0 += margin
                ty0 += margin
                tx1 -= margin
                ty1 -= margin
                if tx1 > tx0 and ty1 > ty0:
                    paint = letters.copy()
                    paint[ty0:ty1, tx0:tx1] = 255
                    alpha = (safe & paint)[y:y+h, x:x+w]
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
                                   textColor=source_text_color(fill, inks), fontWeight="700",
                                   fontFamily="display" if inks and segment["fontSizeSource"] >= 40 else "dialogue"),
                    )
                    if inks:
                        foreground = (np.max(np.abs(image.astype(float)-fill), axis=2) > 30).astype(np.uint8)*255
                        erase = cv2.dilate(foreground & letters, np.ones((3, 3), np.uint8)) & safe
                        restored = cv2.inpaint(image, erase, 5, cv2.INPAINT_TELEA)
                        # Un fond réellement uniforme permet aussi d'effacer les ombres très pâles.
                        for row in np.where(np.any(letters, axis=1))[0]:
                            samples = image[row, (component[row] > 0) & (matching[row] > 0)]
                            samples = samples[np.max(np.abs(samples.astype(float)-fill), axis=1) <= 8]
                            if len(samples) < max(12, (rx1-rx0)*.1):
                                continue
                            background = np.median(samples, axis=0)
                            restored[row, (letters[row] > 0) & (safe[row] > 0)] = background
                        replacement = cv2.cvtColor(restored[y:y+h, x:x+w], cv2.COLOR_BGR2BGRA)
                        replacement[:, :, 3] = alpha
                        success, encoded = cv2.imencode(".png", replacement)
                        if not success:
                            raise RuntimeError("Encodage du fond restauré impossible.")
                        segment["replacementData"] = "data:image/png;base64,"+base64.b64encode(encoded).decode()
        output.append(segment)
    output.sort(key=lambda s: (s["rawBoundingBox"]["y"], s["rawBoundingBox"]["x"]))
    for index, segment in enumerate(output):
        segment["id"] = f"bubble-{index}"
        segment["readingOrder"] = index
    return output
