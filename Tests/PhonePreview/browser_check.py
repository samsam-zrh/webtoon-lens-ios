"""Validation Chromium réelle : import, rendu, navigation et cas difficiles."""
import json
import base64
import io
from pathlib import Path
import sys
import time
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from playwright.sync_api import sync_playwright
from fixtures import create
from PIL import Image, ImageChops, ImageFilter
import numpy as np

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence").resolve()
URL = "http://127.0.0.1:8787"


def fit_assertions(page):
    return page.evaluate("""() => {
      const visible = [...document.querySelectorAll('.bubble[data-fit="true"]')];
      for (const bubble of visible) {
        if (+bubble.dataset.maxLineWidth > +bubble.dataset.textWidth + 0.01)
          throw new Error('Texte trop large');
        if (+bubble.dataset.usedHeight > +bubble.dataset.textHeight + 0.01)
          throw new Error('Texte trop haut');
        const text = bubble.querySelector('.bubble-text');
        if (text.scrollHeight > text.clientHeight + 1 || text.scrollWidth > text.clientWidth + 1)
          throw new Error('Débordement DOM');
      }
      if (document.documentElement.scrollWidth > innerWidth)
        throw new Error('Débordement horizontal du lecteur');
      return { adjusted: visible.length, preserved: document.querySelectorAll('.bubble[data-fit="false"]').length };
    }""")


def wait_ready(page, count, timeout=180000):
    page.wait_for_function(
        """count => document.querySelectorAll('.dialogue-entry').length >= count &&
        !document.querySelector('.reader-page[data-translation-state="running"]')""", arg=count, timeout=timeout)
    page.wait_for_timeout(250)


def paint_assertions(page):
    image = page.locator(".reader-page img").first
    translated = Image.open(io.BytesIO(image.screenshot())).convert("RGB")
    masks = page.locator(".reader-page").first.evaluate("""el => {
      const image = el.querySelector('img').getBoundingClientRect();
      return [...el.querySelectorAll('.bubble[data-fit="true"]')].map(b => {
        const r = b.getBoundingClientRect();
        const style = b.querySelector('.bubble-fill').style.maskImage;
        return {x: r.left-image.left, y: r.top-image.top, w:r.width, h:r.height,
                data: style.slice(style.indexOf('base64,')+7, style.lastIndexOf('"'))};
      });
    }""")
    page.locator("#showOriginal").check()
    original = Image.open(io.BytesIO(image.screenshot())).convert("RGB")
    page.locator("#showOriginal").uncheck()
    allowed = Image.new("L", translated.size, 0)
    for mask in masks:
        alpha = Image.open(io.BytesIO(base64.b64decode(mask["data"]))).getchannel("A")
        alpha = alpha.resize((round(mask["w"]), round(mask["h"])))
        patch = Image.new("L", translated.size, 0)
        patch.paste(alpha, (round(mask["x"]), round(mask["y"])))
        allowed = ImageChops.lighter(allowed, patch)
    allowed = allowed.filter(ImageFilter.MaxFilter(5))
    differences = np.any(np.asarray(original) != np.asarray(translated), axis=2)
    outside = differences & (np.asarray(allowed) == 0)
    assert int(outside.sum()) == 0, f"{outside.sum()} pixels modifiés hors des bulles"
    assert int(differences.sum()) > 100, "Aucune vraie traduction affichée"
    return dict(changedPixels=int(differences.sum()), outsideMaskPixels=int(outside.sum()))


def run():
    create(ROOT / "fixtures")
    measurements = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(viewport={"width": 1280, "height": 1000}, service_workers="block")
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(URL)
        page.wait_for_function("document.getElementById('capabilityLine').textContent.includes('Qwen')")
        assert page.locator("#emptyState").is_visible()
        assert page.locator("#imageInput").count() == 1
        page.screenshot(path=str(ROOT / "desktop-empty.png"), full_page=True)
        start = time.perf_counter()
        page.locator("#imageInput").set_input_files([str(ROOT / "fixtures/en.png"), str(ROOT / "fixtures/zh.png")])
        page.wait_for_selector(".dialogue-entry", state="attached", timeout=180000)
        measurements["firstDialogueSeconds"] = round(time.perf_counter()-start, 3)
        wait_ready(page, 6)
        measurements["twoPagesSeconds"] = round(time.perf_counter()-start, 3)
        assert page.locator(".reader-page").count() == 2
        assert "Noyau" in page.locator(".dialogue-list").first.text_content()
        measurements["desktop"] = fit_assertions(page)
        assert measurements["desktop"]["adjusted"] >= 3
        measurements["painting"] = paint_assertions(page)
        page.locator(".reader-page").first.scroll_into_view_if_needed()
        page.screenshot(path=str(ROOT / "desktop-reader.png"), full_page=True)
        page.locator("#showOriginal").check()
        assert page.locator(".overlay").first.evaluate("el => getComputedStyle(el).visibility") == "hidden"
        page.locator("#showOriginal").uncheck()
        page.set_viewport_size({"width": 390, "height": 844})
        page.wait_for_timeout(350)
        measurements["mobile"] = fit_assertions(page)
        page.screenshot(path=str(ROOT / "mobile-reader.png"), full_page=True)
        # Une très longue traduction n'est jamais tronquée ni peinte hors d'une zone.
        page.evaluate("""() => {
          const target = document.querySelector('.overlay');
          WebtoonLayout.render(target, {
            id: 'long-test', sourceText: 'Wait!', translatedText: 'Très longue traduction française. '.repeat(80),
            boundingBox: {x: .1, y: .1, width: .12, height: .02},
            rawBoundingBox: {x: .1, y: .1, width: .12, height: .02},
            textBox: {x: .1, y: .1, width: .12, height: .02},
            imageWidth: 800, fontSizeSource: 15, renderMode: 'replace',
            maskData: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jmXkAAAAASUVORK5CYII='
          });
        }""")
        assert page.locator('.bubble[data-segment-id="long-test"]').get_attribute("data-fit") == "false"
        assert "Original conservé" in page.locator('.dialogue-entry[data-segment-id="long-test"]').text_content()
        # Correction persistée et effectivement appliquée à un dialogue réel.
        page.locator(".glossary-panel summary").click()
        page.locator("#termSource").fill("Golden Core realm")
        page.locator("#termFrench").fill("Royaume doré")
        page.locator("#glossaryForm button").click()
        page.wait_for_function("document.querySelector('.dialogue-list')?.textContent.includes('Royaume doré')", timeout=180000)
        wait_ready(page, 6)
        assert "Royaume doré" in page.locator("#glossaryOverrides").inner_text()
        page.reload()
        page.locator(".glossary-panel summary").click()
        assert "Royaume doré" in page.locator("#glossaryOverrides").inner_text()
        # Petite image, texte sur l'illustration : alternative explicite.
        page.locator("#imageInput").set_input_files(str(ROOT / "fixtures/small.png"))
        wait_ready(page, 2)
        assert page.locator(".bubble[data-fit='false']").count() >= 1
        measurements["small"] = fit_assertions(page)
        # Page longue : progression à la lecture, puis deuxième moitié.
        page.locator("#imageInput").set_input_files(str(ROOT / "fixtures/tall.png"))
        wait_ready(page, 2)
        page.locator(".reader-page img").evaluate("el => scrollTo(0, el.getBoundingClientRect().top + scrollY + el.height * .8)")
        page.wait_for_function("document.querySelector('.dialogue-list')?.textContent.includes('Page 7')", timeout=180000)
        measurements["tall"] = fit_assertions(page)
        # Navigation : ne devine pas à partir d'un identifiant aléatoire.
        page.locator("#webtoonUrl").fill("https://example.org/series-123/")
        page.locator("#webtoonUrl").dispatch_event("input")
        assert page.locator("#nextChapterButton").is_disabled()
        page.locator("#webtoonUrl").fill("https://example.org/chapter-003/")
        page.locator("#webtoonUrl").dispatch_event("input")
        assert page.locator("#nextChapterButton").is_enabled()
        # Extraction et proxy réels, sur un chapitre original servi en loopback.
        for number, image in ((1, "en.png"), (2, "zh.png")):
            (ROOT / "fixtures" / f"chapter-{number:03}.html").write_text(
                f'<!doctype html><html><body><img src="/{image}" alt="Page originale"></body></html>',
                encoding="utf-8")
        chapter_server = ThreadingHTTPServer(("127.0.0.1", 0),
            partial(SimpleHTTPRequestHandler, directory=str(ROOT / "fixtures")))
        threading.Thread(target=chapter_server.serve_forever, daemon=True).start()
        try:
            chapter_url = f"http://127.0.0.1:{chapter_server.server_port}/chapter-001.html"
            page.locator("#webtoonUrl").fill(chapter_url)
            page.locator("#openUrlButton").click()
            page.wait_for_function("document.getElementById('openUrlButton').disabled === false")
            wait_ready(page, 3)
            assert page.locator(".reader-page").count() == 1
            page.locator("#nextChapterButton").click()
            page.wait_for_function("document.getElementById('webtoonUrl').value.includes('chapter-002')")
            wait_ready(page, 3)
            assert "énergie spirituelle" in page.locator(".dialogue-list").text_content()
            measurements["chapterExtractionAndNavigation"] = "OK"
        finally:
            chapter_server.shutdown()
            chapter_server.server_close()
        # Extraction contrôlée d'un chapitre public synthétique, images réelles.
        # Erreur API visible, pas de faux succès ni boucle automatique.
        page.route("**/v1/webtoon/extract?**", lambda route: route.fulfill(status=502, json={"error": "Chapitre indisponible."}))
        page.locator("#openUrlButton").click()
        page.wait_for_function("document.getElementById('statusLine').textContent.includes('Chapitre indisponible')")
        assert page.locator("#openUrlButton").is_enabled()
        failed_requests = []
        def ocr_error(route):
            failed_requests.append(1)
            route.fulfill(status=503, json={"error": "OCR indisponible pour ce test."})
        page.route("**/v1/webtoon/ocr", ocr_error)
        page.locator("#imageInput").set_input_files(str(ROOT / "fixtures/en.png"))
        page.wait_for_function("document.getElementById('statusLine').textContent.includes('OCR indisponible')")
        page.wait_for_timeout(700)
        assert len(failed_requests) == 1, "Boucle de relance sur erreur"
        assert "Relancer" in page.locator("#statusLine").inner_text()
        assert not errors, errors
        measurements["javascriptErrors"] = errors
        browser.close()
    (ROOT / "browser-results.json").write_text(json.dumps(measurements, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(measurements, indent=2, ensure_ascii=False))
    print("Import, original, glossaire, mobile, texte long, page longue et erreurs : OK.")


if __name__ == "__main__":
    run()
