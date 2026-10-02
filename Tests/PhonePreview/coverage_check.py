"""Aucune zone oubliée, aucun dialogue répété perdu, chapitre complet sans défilement."""
import json
from pathlib import Path
import sys

from playwright.sync_api import sync_playwright
from browser_check import URL, fit_assertions, paint_assertions, wait_ready
from fixtures import create


ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence").resolve()


def run():
    create(ROOT / "fixtures")
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1280, "height": 1000}, service_workers="block")
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.goto(URL)
        page.wait_for_function("document.getElementById('capabilityLine').textContent.includes('Qwen')")
        page.evaluate("""() => {
          const check = (condition, message) => { if (!condition) throw new Error(message); };
          const fake = windows => ({
            __ocrWindows: windows, querySelector: () => ({naturalHeight: 10000})
          });
          const tail = fake([{y: 0, height: .95}]);
          check(!pageFullyCovered(tail), 'Les derniers 5 % ne doivent pas être ignorés');
          check(Math.abs(nextSequentialWindow(tail).y - .95) < 1e-8, 'Queue de page oubliée');
          const gap = fake([{y: 0, height: .4}, {y: .405, height: .595}]);
          check(!pageFullyCovered(gap), 'Trou entre deux fenêtres oublié');
          const next = nextSequentialWindow(gap);
          check(Math.abs(next.y - .4) < 1e-8 && Math.abs(next.height - .005) < 1e-8,
                'La fenêtre suivante doit analyser exactement le trou');
          check(mergeWindows([{y: .5, height: .0005}]).length === 1, 'Petite fenêtre supprimée');
          check(visibleWindowAlreadyCovered(fake([{y:.5,height:.00005}]), {y:.5,height:.00005}),
                'Une petite fenêtre déjà analysée ne doit pas boucler');
          check(!visibleWindowAlreadyCovered(fake([{y:0,height:.75}]), {y:0,height:1}),
                '75 % ne signifie pas tout analysé');
          const a = {id:'first', sourceText:'Wait!', rawBoundingBox:{x:.1,y:.1,width:.12,height:.0005}};
          const b = {...a,id:'second',rawBoundingBox:{...a.rawBoundingBox,y:.102}};
          const shifted = {...a,rawBoundingBox:{...a.rawBoundingBox,y:.10005}};
          check(!sameDialogue(a,b), 'Deux bulles identiques à des positions distinctes ont été confondues');
          check(sameDialogue(a,shifted), 'Le chevauchement OCR doit être dédupliqué');
          check(newSegmentsForPage({__translatedSegments:[a]},[shifted,b]).length === 1,
                'La seconde bulle doit encore être traduite');
          check(mergeSegmentLists([a],[shifted,b]).length === 2, 'Contexte de dialogue incomplet');
          check(!sameDialogue({...a,sourceText:'a'.repeat(100)+'one'},
                              {...a,sourceText:'a'.repeat(100)+'two'}), 'Fin de dialogue ignorée');
          const halo = mapCropSegmentsToPage([{...a,renderMode:'replace',maskData:'mask'}], {
            window:{y:.2,height:.1},mappingWindow:{y:.1,height:.4},
            imageWidth:800,imageHeight:10000,cacheKey:'halo'
          },{dataset:{index:'0'}});
          check(halo.length === 1 && !halo[0].withinWindow,
                'Le meilleur masque trouvé dans le chevauchement ne doit pas être jeté');
          const previous = {...a,renderMode:'inspect',translatedText:'Attends !'};
          const incoming = {...shifted,renderMode:'replace',maskData:'mask',
                            textBox:{x:.1,y:.1,width:.2,height:.01}};
          const saved = WebtoonLayout.render;
          const upgraded = [];
          try {
            WebtoonLayout.render = (_,segment) => upgraded.push(segment);
            upgradeTranslatedRegions({__translatedSegments:[previous],querySelector:()=>null},[incoming]);
          } finally { WebtoonLayout.render = saved; }
          check(upgraded.length === 1 && upgraded[0].id === 'first' &&
                upgraded[0].translatedText === 'Attends !', 'Le meilleur masque doit réutiliser le français');
          const reader = document.getElementById('imageReader');
          const pending = [];
          try {
            for (let index = 0; index < 8; index++) {
              const item = document.createElement('article');
              item.className = 'reader-page';
              const img = document.createElement('img');
              img.loading = index < 4 ? 'eager' : 'lazy';
              item.append(img);
              reader.append(item);
              if (index === 0) item.dataset.translationState = 'done';
              else if (index === 1) item.dataset.translationState = 'error';
              else if (index === 2) item.classList.add('load-error');
              else pending.push(item);
            }
            preloadTranslationPages();
            check(pending.filter(item => item.querySelector('img').loading === 'eager').length === 3,
                  'Les pages terminées ou en erreur ne doivent pas bloquer le préchargement');
            check(pending.filter(item => item.querySelector('img').loading === 'lazy').length === 2,
                  'Le préchargement doit rester borné');
          } finally { reader.replaceChildren(); }
        }""")
        # Le cinquième fichier était hors de la limite de traduction/préchargement.
        data = (ROOT / "fixtures/en.png").read_bytes()
        page.locator("#imageInput").set_input_files([
            {"name": f"page-{index}.png", "mimeType": "image/png", "buffer": data}
            for index in range(5)
        ])
        page.wait_for_selector(".bubble[data-fit='true']", state="attached", timeout=180000)
        assert page.locator('.reader-page[data-translation-state="done"]').count() < 5, \
            "La première traduction doit être visible avant la fin du chapitre"
        page.wait_for_function("""() =>
          document.querySelectorAll('.reader-page[data-translation-state="done"]').length === 5
        """, timeout=180000)
        assert page.evaluate("scrollY") == 0, "Le chapitre doit avancer sans devoir défiler"
        assert page.locator(".dialogue-entry").count() == 15
        assert all(count == 3 for count in page.locator(".reader-page").evaluate_all(
            "pages => pages.map(page => page.querySelectorAll('.dialogue-entry').length)"))
        assert fit_assertions(page) == {"adjusted": 15, "preserved": 0}
        page.locator("#imageInput").set_input_files([
            {"name": f"blocked-{index}.png", "mimeType": "image/png", "buffer": b"not an image"}
            for index in range(3)
        ] + [
            {"name": f"valid-{index}.png", "mimeType": "image/png", "buffer": data}
            for index in range(2)
        ])
        page.wait_for_function("""() =>
          document.querySelectorAll('.reader-page.load-error').length === 3 &&
          document.querySelectorAll('.reader-page[data-translation-state="done"]').length === 2
        """, timeout=180000)
        assert page.locator(".dialogue-entry").count() == 6
        page.locator("#imageInput").set_input_files(str(ROOT / "fixtures/thin-white.png"))
        wait_ready(page, 1)
        desktop = fit_assertions(page)
        assert desktop == {"adjusted": 1, "preserved": 0}, desktop
        painting = paint_assertions(page)
        assert "école" in page.locator(".dialogue-entry").text_content().casefold()
        page.screenshot(path=str(ROOT / "thin-white-desktop.png"), full_page=True)
        page.set_viewport_size({"width": 390, "height": 844})
        page.wait_for_timeout(350)
        mobile = fit_assertions(page)
        assert mobile == {"adjusted": 1, "preserved": 0}, mobile
        page.screenshot(path=str(ROOT / "thin-white-mobile.png"), full_page=True)
        assert not errors, errors
        result = dict(allFivePagesWithoutScrolling=True, dialogues=15, exactCoverage=True,
                      repeatedDialoguesPreserved=True, improvedMasksReuseTranslation=True,
                      boundedPrefetchPastErrors=True,
                      firstBubbleBeforeChapterCompletion=True, loadedPastThreeFailedImages=True,
                      thinWhite=dict(desktop=desktop, mobile=mobile, painting=painting),
                      javascriptErrors=errors)
        (ROOT / "coverage-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        browser.close()


if __name__ == "__main__":
    run()
