"""Images originales de validation, sans extrait de webtoon publié."""
from pathlib import Path
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


if __name__ == "__main__":
    import sys
    create(Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence/fixtures"))
