"""Images originales de validation, sans extrait de webtoon publié."""
from pathlib import Path
import math
import os
from PIL import Image, ImageDraw, ImageFont

ENGLISH = [
    "Your cultivation has reached the Golden Core realm.",
    "The guild master is waiting at the dungeon entrance.",
    "I wanted to tell you yesterday, but the rain was so loud that you could not hear me.",
]
CHINESE = [
    "师兄，突破金丹境后，我们就能加入宗门。",
    "你的灵气已经耗尽了！",
    "明天放学后，我们一起去吃饭吧。",
]
COLORED = [
    ("#000000", "#ffffff", "en", "Wait for me! We must reach the school before the storm."),
    ("#27365a", "#ffffff", "zh", CHINESE[1]),
    ("#ffd966", "#111111", "en", ENGLISH[0]),
    ("#e1bbcf", "#111111", "en", ENGLISH[1]),
    ("#a83c3c", "#ffffff", "zh", CHINESE[2]),
]


def font(language, size):
    candidates = (
        [os.environ.get("WEBTOON_TEST_ZH_FONT", ""), "/System/Library/Fonts/STHeiti Medium.ttc",
         "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]
        if language == "zh" else
        [os.environ.get("WEBTOON_TEST_EN_FONT", ""), "/System/Library/Fonts/Supplemental/Arial.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    )
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    raise RuntimeError("Police de test absente : indiquez WEBTOON_TEST_EN_FONT / WEBTOON_TEST_ZH_FONT.")


def lines_for(draw, text, typeface, width, language):
    tokens = list(text) if language == "zh" else text.split()
    result, line = [], ""
    separator = "" if language == "zh" else " "
    for token in tokens:
        candidate = line + separator + token if line else token
        if draw.textlength(candidate, font=typeface) > width:
            result.append(line)
            line = token
        else:
            line = candidate
    if line:
        result.append(line)
    return result


def create(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    for language, dialogues in (("en", ENGLISH), ("zh", CHINESE)):
        image = Image.new("RGB", (800, 1250), "#384e5a")
        draw = ImageDraw.Draw(image)
        for index, dialogue in enumerate(dialogues):
            top = 80+index*390
            rect = (90, top, 710, top+290)
            draw.ellipse(rect, fill="white", outline="#151515", width=5)
            typeface = font(language, 31)
            lines = lines_for(draw, dialogue, typeface, 440, language)
            line_height = 43
            y = top+145-len(lines)*line_height/2
            for line in lines:
                x = 400-draw.textlength(line, font=typeface)/2
                draw.text((x, y), line, fill="#111", font=typeface)
                y += line_height
        image.save(directory / f"{language}.png")
    image = Image.new("RGB", (800, 3600), "#384e5a")
    draw = ImageDraw.Draw(image)
    for index in range(7):
        top = 60+index*500
        draw.rounded_rectangle((90, top, 710, top+300), radius=60, fill="white", outline="black", width=4)
        text = f"Page {index+1}. We will meet tomorrow at the school festival."
        typeface = font("en", 30)
        for number, line in enumerate(lines_for(draw, text, typeface, 460, "en")):
            draw.text((400-draw.textlength(line, font=typeface)/2, top+90+number*42), line, font=typeface, fill="black")
    image.save(directory / "tall.png")
    small = Image.new("RGB", (350, 240), "#38596a")
    draw = ImageDraw.Draw(small)
    draw.ellipse((90, 65, 260, 160), fill="white", outline="black", width=3)
    draw.text((125, 102), "Wait!", font=font("en", 20), fill="black")
    draw.text((10, 200), "Text on the drawing", font=font("en", 16), fill="white")
    small.save(directory / "small.png")
    announcement = Image.new("RGB", (800, 1000), "#384e5a")
    draw = ImageDraw.Draw(announcement)
    for index, text in enumerate((
        "WORKSHOP ANNOUNCEMENT",
        "THE SCHOOL CLUBS HAVE JOINED FORCES.",
        "COME TO DISCOVER OUR NEW PROJECTS.",
        "READ WITH US, CELEBRATE WITH US!",
        "ALBA. COM",
        "workshop.example.org",
    )):
        typeface = font("en", 30)
        for number, line in enumerate(lines_for(draw, text, typeface, 670, "en")):
            draw.text((60, 80 + index * 145 + number * 40), line, font=typeface, fill="white")
    announcement.save(directory / "announcement.png")
    colored = Image.new("RGB", (800, 2040), "#384e5a")
    draw = ImageDraw.Draw(colored)
    interiors = Image.new("L", colored.size, 0)
    interior_draw = ImageDraw.Draw(interiors)
    for index, (fill, ink, language, dialogue) in enumerate(COLORED):
        top = 80+index*390
        if index == 0:
            points = []
            for point in range(96):
                angle = point*math.tau/96
                scale = 1 if point % 2 else 1.12
                points.append((400+290*scale*math.cos(angle), top+145+135*scale*math.sin(angle)))
            draw.polygon(points, fill=fill)
            interior_draw.polygon(points, fill=255)
        else:
            draw.ellipse((90, top, 710, top+290), fill=fill, outline="#151515", width=5)
            interior_draw.ellipse((90, top, 710, top+290), fill=255)
        typeface = font(language, 31)
        lines = lines_for(draw, dialogue, typeface, 440, language)
        y = top+145-len(lines)*43/2
        for line in lines:
            draw.text((400-draw.textlength(line, font=typeface)/2, y), line, fill=ink, font=typeface)
            y += 43
    colored.save(directory / "colored.png")
    interiors.save(directory / "colored-interiors.png")
    thin = Image.new("RGB", (800, 800), "white")
    draw = ImageDraw.Draw(thin)
    draw.rectangle((0, 320, 799, 799), fill="#384e5a")
    draw.ellipse((90, 100, 710, 460), fill="white", outline="black", width=2)
    typeface = font("en", 40)
    for index, text in enumerate(("WAIT!", "WE STILL HAVE TIME", "TO REACH THE SCHOOL!")):
        draw.text((400-draw.textlength(text, font=typeface)/2, 170+index*58),
                  text, fill="black", font=typeface)
    thin.save(directory / "thin-white.png")


if __name__ == "__main__":
    import sys
    create(Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence/fixtures"))
