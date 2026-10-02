"""Refus HTTP réel, conservation du lecteur et récupération par import."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import threading

from playwright.sync_api import sync_playwright

from browser_check import fit_assertions, wait_ready
from fixtures import create


def run():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".runtime/evidence").resolve()
    create(root / "fixtures")
    started, release = threading.Event(), threading.Event()

    class SourceHandler(SimpleHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/forbidden.html":
                self.send_error(403, "PRIVATE UPSTREAM ERROR")
            elif self.path == "/empty.html":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"<html><body>JavaScript required</body></html>")
            elif self.path == "/slow-chapter.html":
                started.set()
                release.wait(timeout=10)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'<img src="/zh.png">')
            else:
                super().do_GET()

        def log_message(self, *args):
            pass

    source = ThreadingHTTPServer(("127.0.0.1", 0), partial(SourceHandler, directory=str(root / "fixtures")))
    threading.Thread(target=source.serve_forever, daemon=True).start()
    origin = f"http://127.0.0.1:{source.server_port}"
    results = {}
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            page = browser.new_page(viewport={"width": 1280, "height": 1000}, service_workers="block")
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto("http://127.0.0.1:8787")
            assert page.locator("#chapterError").is_hidden()
            page.locator("#imageInput").set_input_files(str(root / "fixtures/en.png"))
            wait_ready(page, 3)
            original_url = page.locator(".reader-page img").get_attribute("src")
            original_text = page.locator(".dialogue-list").text_content()
            original_session = page.locator(".reader-page").get_attribute("data-session-id")
            saved_url = page.evaluate("localStorage.getItem('webtoonLensUrl')")

            for path, code in (("/forbidden.html", "source_access_denied"),
                               ("/empty.html", "chapter_images_missing")):
                page.locator("#webtoonUrl").fill(origin + path)
                with page.expect_response("**/v1/webtoon/extract?**") as response:
                    page.locator("#openUrlButton").click()
                assert response.value.json()["code"] == code
                page.wait_for_function("!document.getElementById('openUrlButton').disabled")
                assert page.locator("#chapterError").is_visible()
                assert page.locator("#openSourceLink").get_attribute("href") == origin + path
                assert page.locator("#openSourceLink").get_attribute("rel") == "noopener noreferrer"
                assert page.locator("#webtoonUrl").get_attribute("aria-invalid") == "true"
                assert page.locator(".reader-page img").get_attribute("src") == original_url
                assert page.locator(".reader-page").get_attribute("data-session-id") == original_session
                assert page.locator(".dialogue-list").text_content() == original_text
                assert page.evaluate("localStorage.getItem('webtoonLensUrl')") == saved_url
                assert page.evaluate("url => fetch(url).then(r => r.ok)", original_url)
                assert "Error response" not in page.locator("body").inner_text()
                assert "PRIVATE" not in page.locator("body").inner_text()
            results["upstream403AndEmptyChapterPreserveReader"] = True
            page.screenshot(path=str(root / "access-desktop.png"), full_page=True)
            for width in (390, 320):
                page.set_viewport_size({"width": width, "height": 844})
                page.wait_for_function("""() => [...document.querySelectorAll('.bubble[data-fit="true"] .bubble-text')]
                  .every(text => text.scrollHeight <= text.clientHeight + 1 &&
                                 text.scrollWidth <= text.clientWidth + 1)""", timeout=5000)
                fit_assertions(page)
                assert page.locator("#importAfterError").bounding_box()["height"] >= 44
                assert page.locator("#openSourceLink").bounding_box()["height"] >= 44
            page.screenshot(path=str(root / "access-mobile.png"), full_page=True)
            results["mobileWithoutOverflow"] = [390, 320]

            page.route("**/v1/webtoon/extract?**", lambda route: route.fulfill(
                status=502, content_type="text/html",
                body="<html><body>Error response PRIVATE UPSTREAM ERROR</body></html>"), times=1)
            page.locator("#openUrlButton").click()
            page.wait_for_function("!document.getElementById('openUrlButton').disabled")
            assert "HTTP 502" in page.locator("#chapterErrorMessage").text_content()
            assert "PRIVATE" not in page.locator("body").inner_text()
            page.locator("#webtoonUrl").fill("file:///tmp/page.png")
            page.locator("#openUrlButton").click()
            page.wait_for_function("!document.getElementById('openUrlButton').disabled")
            assert page.locator("#openSourceLink").is_hidden()
            results["legacyHtmlAndInvalidUrl"] = True

            page.locator("#importAfterError").focus()
            with page.expect_file_chooser() as chooser:
                page.keyboard.press("Enter")
            chooser.value.set_files(str(root / "fixtures/zh.png"))
            wait_ready(page, 3)
            assert page.locator("#chapterError").is_hidden()
            assert page.locator("#webtoonUrl").get_attribute("aria-invalid") is None
            assert "énergie spirituelle" in page.locator(".dialogue-list").text_content()
            results["keyboardImportAndRealChineseTranslation"] = True

            for interrupt in ("import", "language"):
                started.clear()
                release.clear()
                page.locator("#webtoonUrl").fill(origin + "/slow-chapter.html")
                page.locator("#openUrlButton").click()
                assert started.wait(timeout=5), "Requête amont non reçue"
                if interrupt == "import":
                    page.locator("#imageInput").set_input_files(str(root / "fixtures/en.png"))
                else:
                    page.locator("#ocrLanguage").select_option("en")
                expected_url = page.locator(".reader-page img").get_attribute("src")
                release.set()
                page.wait_for_function("!document.getElementById('openUrlButton').disabled")
                wait_ready(page, 3)
                assert page.locator(".reader-page img").get_attribute("src") == expected_url
                assert page.locator("#chapterError").is_hidden()
                assert page.evaluate("localStorage.getItem('webtoonLensUrl')") == saved_url
            results["staleRequestIgnoredAfterImportAndLanguageChange"] = True
            assert not errors, errors
            results["javascriptErrors"] = errors
            browser.close()
    finally:
        release.set()
        source.shutdown()
        source.server_close()
    (root / "access-results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    run()
