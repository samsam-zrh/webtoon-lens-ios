"""Interface compacte : bureau/mobile, clavier, réglages masqués et vraie lecture."""
import json
from pathlib import Path
import sys

from playwright.sync_api import sync_playwright
from browser_check import URL, fit_assertions, paint_assertions
from fixtures import create


ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence/compact-ui").resolve()
BROWSER = sys.argv[2] if len(sys.argv) > 2 else "chromium"


def ready(page, count):
    page.wait_for_function("""count => document.querySelectorAll('.dialogue-entry').length === count &&
      [...document.querySelectorAll('.reader-page')].every(p => p.dataset.translationState === 'done')
    """, arg=count, timeout=180000)


def interface_assertions(page, limit):
    return page.evaluate("""limit => {
      const check = (value, message) => { if (!value) throw new Error(message); };
      const stage = document.getElementById('stage').getBoundingClientRect();
      check(stage.top <= limit, `En-tête trop haut : ${stage.top}`);
      check(document.documentElement.scrollWidth <= innerWidth, 'Débordement horizontal');
      check(getComputedStyle(document.getElementById('webtoonUrl')).fontSize === '16px',
            'Les champs mobiles doivent éviter le zoom Safari');
      const settings = document.querySelector('.internal-tools');
      check(settings.hidden && settings.inert, 'Les réglages doivent être hors du parcours utilisateur');
      check(!document.getElementById('retryButton'), 'Le bouton permanent de relance doit être supprimé');
      for (const el of document.querySelectorAll('.source-actions button, .file-button, .nav-button, .toggle-control, #ocrLanguage')) {
        check(el.getBoundingClientRect().height >= 44, 'Cible tactile trop petite');
      }
      const rgb = value => value.match(/[\\d.]+/g).slice(0,3).map(Number);
      const luminance = values => values.map(c => {
        c /= 255; return c <= .04045 ? c/12.92 : ((c+.055)/1.055)**2.4;
      }).reduce((sum,c,index) => sum+c*[.2126,.7152,.0722][index],0);
      const ratios = [];
      for (const [selector, background] of [
        ['.brand p','rgb(244,246,245)'], ['.toggle-control','rgb(244,246,245)'],
        ['.primary-status','rgb(244,246,245)'], ['#openUrlButton','rgb(23,103,82)']
      ]) {
        const foreground = luminance(rgb(getComputedStyle(document.querySelector(selector)).color));
        const behind = luminance(rgb(background));
        const ratio = (Math.max(foreground,behind)+.05)/(Math.min(foreground,behind)+.05);
        check(ratio >= 4.5, `Contraste insuffisant : ${selector}`);
        ratios.push({selector, ratio});
      }
      return {stageTop:stage.top, viewport:innerWidth, ratios};
    }""", limit)


def article_assertions(page):
    heights = page.locator(".reader-page").evaluate_all("""pages => pages.map(page => {
      const image = page.querySelector('img').getBoundingClientRect().height;
      const dialogues = page.querySelector('.dialogue-list')?.getBoundingClientRect().height || 0;
      const recovery = page.querySelector('.page-recovery')?.getBoundingClientRect().height || 0;
      return {actual:page.clientHeight, expected:image+dialogues+recovery};
    })""")
    assert all(abs(item["actual"]-item["expected"]) <= 1.5 for item in heights), heights
    return heights


def run():
    create(ROOT / "fixtures")
    results = {"browser": BROWSER, "empty": {}, "reader": {}}
    with sync_playwright() as p:
        browser = getattr(p, BROWSER).launch()
        context = browser.new_context(viewport={"width": 1280, "height": 1000}, service_workers="block")
        context.add_init_script("""
          localStorage.setItem('webtoonLensSeries','Interface');
          localStorage.setItem('webtoonLensGlossary:Interface', JSON.stringify([
            {source:'Golden Core realm',translation:'Royaume doré',isLocked:true}
          ]));
        """)
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(URL)
        page.wait_for_function("document.getElementById('capabilityLine').dataset.ready === 'true'")
        assert "Glossaire" not in page.locator("body").aria_snapshot()
        assert "Réglages avancés" not in page.locator("body").aria_snapshot()
        assert page.locator("[data-page-retry]").count() == 0
        assert page.evaluate("WebtoonGlossary.terms()[0].translation") == "Royaume doré"
        for width, height, limit in ((1280, 1000, 290), (390, 844, 420), (320, 844, 440)):
            page.set_viewport_size({"width": width, "height": height})
            page.evaluate("scrollTo(0,0)")
            results["empty"][str(width)] = interface_assertions(page, limit)
            if width != 320:
                page.screenshot(path=str(ROOT / f"{BROWSER}-empty-{width}.png"), full_page=True)

        page.set_viewport_size({"width": 1280, "height": 1000})
        page.locator("#webtoonUrl").focus()
        for expected in ("openUrlButton", "imageInput", "ocrLanguage", "showOriginal"):
            page.keyboard.press("Alt+Tab" if BROWSER == "webkit" else "Tab")
            assert page.evaluate("document.activeElement.id") == expected
        page.locator("#imageInput").focus()
        with page.expect_file_chooser() as chooser:
            page.keyboard.press("Enter")
        chooser.value.set_files([str(ROOT / "fixtures/en.png"), str(ROOT / "fixtures/zh.png")])
        ready(page, 6)
        assert "Royaume doré" in page.locator(".dialogue-list").first.text_content()
        assert page.locator("[data-page-retry]").count() == 0
        results["painting"] = paint_assertions(page)
        for width, height in ((1280, 1000), (390, 844)):
            page.set_viewport_size({"width": width, "height": height})
            page.evaluate("scrollTo(0,0)")
            page.wait_for_timeout(200)
            results["reader"][str(width)] = fit_assertions(page)
            assert results["reader"][str(width)] == {"adjusted": 6, "preserved": 0}
            results["reader"][str(width)]["articleHeights"] = article_assertions(page)
            page.screenshot(path=str(ROOT / f"{BROWSER}-reader-{width}.png"), full_page=True)
        page.locator(".dialogue-list summary").first.click()
        article_assertions(page)
        page.locator(".dialogue-list summary").first.click()
        results["expandedDialoguesInFlow"] = True
        page.locator("#showOriginal").check()
        assert page.locator(".overlay").first.evaluate("el => getComputedStyle(el).visibility") == "hidden"
        page.locator("#showOriginal").uncheck()
        page.evaluate("scrollTo(0,800)")
        assert abs(page.locator(".reading-bar").bounding_box()["y"]) <= 1
        page.evaluate("window.savedPages = [...document.querySelectorAll('.reader-page')]")
        page.route("**/v1/webtoon/extract?**", lambda route: route.fulfill(status=502, json={
            "error": "Le site refuse la récupération automatique (403). Ouvrez-le ou importez vos pages."
        }))
        page.locator("#webtoonUrl").fill("https://example.org/chapter-003/")
        page.locator("#webtoonUrl").dispatch_event("input")
        assert page.locator("#nextChapterButton").is_enabled()
        assert page.locator("#prevChapterButton").is_enabled()
        page.keyboard.press("Enter")
        page.wait_for_function("!document.getElementById('chapterError').hidden")
        assert page.locator("#openUrlButton").is_enabled()
        assert page.evaluate("savedPages.every(el => el.isConnected)")
        for width, height in ((1280, 1000), (390, 844)):
            page.set_viewport_size({"width": width, "height": height})
            page.evaluate("scrollTo(0,0)")
            assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
            page.screenshot(path=str(ROOT / f"{BROWSER}-error-{width}.png"))
        results["hiddenToolsPreserveGlossary"] = True
        results["keyboardImportAndNavigation"] = True
        results["stickyReadingControls"] = True
        results["upstreamErrorPreservesPages"] = True
        assert not errors, errors
        results["javascriptErrors"] = errors
        browser.close()
    (ROOT / f"interface-results-{BROWSER}.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    run()
