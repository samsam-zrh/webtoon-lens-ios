"""Traduction réelle hors bulle, isolation des pages en erreur et reprise."""
import json
from pathlib import Path
import sys

from playwright.sync_api import sync_playwright

from browser_check import fit_assertions, wait_ready
from fixtures import create


def run():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence").resolve()
    create(root / "fixtures")
    results = {}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": 1280, "height": 1000}, service_workers="block")
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto("http://127.0.0.1:8787")
        page.locator("#imageInput").set_input_files(str(root / "fixtures/announcement.png"))
        wait_ready(page, 6)
        assert page.locator(".reader-page").get_attribute("data-translation-state") != "error"
        assert page.locator(".dialogue-list").get_attribute("open") is not None
        assert page.locator(".dialogue-entry p:nth-child(2)").first.is_visible()
        text = page.locator(".dialogue-list").inner_text()
        assert "annonce" in text.casefold() and "atelier" in text.casefold()
        assert "__G" not in text
        assert page.locator(".bubble[data-fit='true']").count() == 0
        page.locator(".dialogue-list").scroll_into_view_if_needed()
        page.screenshot(path=str(root / "translation-announcement-desktop.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        fit_assertions(page)
        page.screenshot(path=str(root / "translation-announcement-mobile.png"), full_page=True)
        results["realAnnouncementTranslationVisibleWithoutPaintingArt"] = True

        page.set_viewport_size({"width": 1280, "height": 1000})
        calls = {}
        fail_first_page = True
        first_page_calls = 0
        def translation(route):
            nonlocal first_page_calls
            payload = route.request.post_data_json
            # Les identifiants de segments sont préfixés par l'index de la page.
            page_index = str(payload["segments"][0]["id"]).split("-")[0]
            calls[page_index] = calls.get(page_index, 0) + 1
            if page_index == "p0":
                first_page_calls += 1
                if fail_first_page and first_page_calls > 1:
                    route.fulfill(status=503, json={"error": "Erreur de glossaire contrôlée."})
                    return
            route.continue_()
        page.route("**/v1/webtoon/translate", translation)
        page.locator("#imageInput").set_input_files([str(root / "fixtures/en.png"), str(root / "fixtures/zh.png")])
        page.wait_for_selector('.reader-page[data-index="0"][data-translation-state="error"]', state="attached", timeout=180000)
        page.wait_for_function("""() => document.querySelector('.reader-page[data-index="1"] .dialogue-list')
          ?.textContent.includes('énergie spirituelle')""", timeout=180000)
        wait_ready(page, 4)
        assert calls["p0"] == 2, "Une erreur ne doit pas être relancée automatiquement en boucle"
        assert "en erreur" in page.locator("#statusLine").text_content()
        page.wait_for_timeout(400)
        assert calls["p0"] == 2
        results["secondPageContinuesAfterFirstPageFails"] = True
        before = page.locator(".dialogue-entry").evaluate_all("items => items.map(el => el.textContent)")
        page.evaluate("window.savedTranslationEntries = [...document.querySelectorAll('.dialogue-entry')]")
        second_page_calls = calls["p1"]
        fail_first_page = False
        page.locator("[data-page-retry]").click()
        assert page.evaluate("savedTranslationEntries.every(el => el.isConnected)")
        wait_ready(page, 6)
        assert page.locator('.reader-page[data-translation-state="error"]').count() == 0
        assert page.evaluate("savedTranslationEntries.every(el => el.isConnected)")
        after = page.locator(".dialogue-entry").evaluate_all("items => items.map(el => el.textContent)")
        assert all(text in after for text in before)
        assert calls["p1"] == second_page_calls, "La page déjà traduite ne doit pas être recalculée"
        results["retryPreservesRenderedTranslations"] = True
        assert not errors, errors
        results["javascriptErrors"] = errors
        browser.close()
    (root / "translation-recovery-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    run()
