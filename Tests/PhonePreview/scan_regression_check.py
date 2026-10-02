"""Bulles reliées, encre rouge ombrée, bas de page et échec d'un seul dialogue."""
import json
import base64
import io
from pathlib import Path
import sys

from playwright.sync_api import sync_playwright
from PIL import Image
import numpy as np
from browser_check import URL, fit_assertions, paint_assertions
from fixtures import create


ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence").resolve()


def done(page, count):
    page.wait_for_function("""count => document.querySelectorAll('.dialogue-entry').length === count &&
      [...document.querySelectorAll('.reader-page')].every(p => p.dataset.translationState === 'done')
    """, arg=count, timeout=180000)


def run():
    create(ROOT / "fixtures")
    results = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1280, "height": 1000}, service_workers="block")
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(URL)
        page.wait_for_function("document.getElementById('capabilityLine').textContent.includes('Qwen')")
        for name, count in (("joined", 2), ("joined-clipped", 2), ("styled", 1), ("tail", 4)):
            page.set_viewport_size({"width": 1280, "height": 1000})
            page.evaluate("scrollTo(0, 0)")
            page.locator("#imageInput").set_input_files(str(ROOT / "fixtures" / f"{name}.png"))
            done(page, count)
            desktop = fit_assertions(page)
            assert desktop == {"adjusted": count, "preserved": 0}, (name, desktop)
            if name == "tail":
                assert page.evaluate("scrollY") == 0, "Le bas de page doit se traduire sans défilement"
            painting = paint_assertions(page)
            if name.startswith("joined"):
                boxes = page.locator(".reader-page").evaluate("p => p.__translatedSegments.map(s => s.textBox)")
                assert boxes[0]["y"]+boxes[0]["height"] < .5 and boxes[1]["y"] > .5, boxes
            if name == "styled":
                ink = page.locator(".bubble-text").evaluate("el => getComputedStyle(el).color")
                assert ink not in ("rgb(17, 17, 17)", "rgb(0, 0, 0)", "rgb(255, 255, 255)"), ink
                assert float(page.locator(".bubble").get_attribute("data-font-size")) > 48
                data = page.locator(".reader-page").evaluate("p => p.__translatedSegments[0].replacementData")
                rgba = np.asarray(Image.open(io.BytesIO(base64.b64decode(data.split(",")[1]))))
                assert not np.any((rgba[:, :, 0].astype(int)-rgba[:, :, 1].astype(int) > 12)
                                  & (rgba[:, :, 3] > 0)), "Des lettres rouges originales restent sous le français"
            if name == "tail":
                assert "4" in page.locator(".dialogue-entry").last.text_content()
            else:
                page.screenshot(path=str(ROOT / f"{name}-desktop.png"), full_page=True)
            page.set_viewport_size({"width": 390, "height": 844})
            page.wait_for_timeout(300)
            mobile = fit_assertions(page)
            assert mobile == {"adjusted": count, "preserved": 0}, (name, mobile)
            if name != "tail":
                page.screenshot(path=str(ROOT / f"{name}-mobile.png"), full_page=True)
            results[name] = dict(desktop=desktop, mobile=mobile, painting=painting)

        page.set_viewport_size({"width": 1280, "height": 1000})
        failed_id = None
        should_fail = True
        calls = []
        def fail_dialogue(route):
            nonlocal failed_id
            segments = route.request.post_data_json["segments"]
            calls.append([s["id"] for s in segments])
            if failed_id is None and len(calls) == 2:
                failed_id = segments[0]["id"]
            if should_fail and any(s["id"] == failed_id for s in segments):
                route.fulfill(status=503, json={"error": "Échec contrôlé du dialogue.",
                              "code": "dialogue_translation_failed", "failedSegmentID": failed_id})
            else:
                route.continue_()
        page.route("**/v1/webtoon/translate", fail_dialogue)
        page.locator("#imageInput").set_input_files(str(ROOT / "fixtures/en.png"))
        page.wait_for_function("document.querySelector('.reader-page')?.dataset.translationState === 'partial'",
                               timeout=180000)
        assert page.locator(".dialogue-entry").count() == 2
        assert page.locator(".dialogue-error").count() == 1
        assert "Échec contrôlé" in page.locator(".dialogue-error").text_content()
        assert "bulle(s)" in page.locator("#statusLine").text_content()
        requests_before = len(calls)
        page.wait_for_timeout(600)
        assert len(calls) == requests_before, "Pas de boucle de retry"
        page.evaluate("window.savedGoodDialogues = [...document.querySelectorAll('.dialogue-entry')]")
        should_fail = False
        page.locator("#retryButton").click()
        done(page, 3)
        assert page.locator(".dialogue-error").count() == 0
        assert page.evaluate("savedGoodDialogues.every(el => el.isConnected)")
        assert calls[requests_before:] == [[failed_id]], calls
        results["failureIsolatedAndOnlyFailedDialogueRetried"] = True
        assert not errors, errors
        results["javascriptErrors"] = errors
        browser.close()
    (ROOT / "scan-regression-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    run()
