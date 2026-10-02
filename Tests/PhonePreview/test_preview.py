import base64
import io
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "PhonePreview"))
from PIL import Image, ImageDraw
from bubble_geometry import fit_dialogue, text_color
import numpy as np
from glossary import entries, protect, restore
from local_translation import generate_dialogue, parse_translations, translate, validate_french, validate_model_metadata, normalize_french_agreement
import server


class GlossaryTests(unittest.TestCase):
    def test_reviewed_concept_count(self):
        self.assertGreaterEqual(len(entries()), 150)
        self.assertLessEqual(len(entries()), 250)
        self.assertTrue(all(row["context"] and row["category"] and row["zh"] for row in entries()))

    def test_longest_and_boundaries(self):
        text, locked, used = protect("Golden Core realm, guild master, party, counterpart", [])
        self.assertEqual([term["source"] for term in used], ["Golden Core realm", "guild master", "party"])
        self.assertIn("counterpart", text)
        self.assertEqual(used[0]["translation"], "royaume du Noyau d'or")
        self.assertEqual(list(locked.values()), ["royaume du Noyau d'or"])

    def test_chinese(self):
        text, locked, used = protect("师兄，突破金丹境后", [])
        self.assertEqual([term["source"] for term in used], ["师兄", "突破", "金丹境"])

    def test_traditional(self):
        text, locked, used = protect("師兄，你的靈氣已經耗盡了！", [])
        self.assertEqual([term["source"] for term in used], ["師兄", "靈氣"])
        self.assertIn("énergie spirituelle", locked.values())

    def test_override(self):
        text, locked, _ = protect("Azure Moon and Golden Core realm",
                                 [dict(source="Azure Moon", translation="Lune bleue"),
                                  dict(source="Golden Core realm", translation="Royaume doré")])
        self.assertEqual(restore(text, locked), "Lune bleue and Royaume doré")

    def test_missing_token_explicit(self):
        with self.assertRaisesRegex(RuntimeError, "omis"):
            restore("Autre texte", {"__G0__": "Lune"})
        self.assertEqual(restore("Bonjour Lune bleue", {"__G0__": "Lune bleue"}), "Bonjour Lune bleue")
        with self.assertRaises(RuntimeError):
            restore("Lune", {"__G0__": "Lune", "__G1__": "Lune"})

    def test_invented_or_repeated_tokens_are_rejected(self):
        for text, protected, message in (
            ("Bonjour __G0__", {}, "inventé"),
            ("Bonjour __g0__", {}, "inventé"),
            ("Bonjour __G1__", {"__G0__": "Lune"}, "inventé"),
            ("__G0__ et __G0__", {"__G0__": "Lune"}, "répété"),
        ):
            with self.subTest(text=text), self.assertRaisesRegex(RuntimeError, message):
                restore(text, protected)
        self.assertEqual(restore("__G0__ et __G1__", {"__G0__": "Lune", "__G1__": "Lune"}), "Lune et Lune")


class ModelTests(unittest.TestCase):
    def dialogue(self, source):
        text, protected, terms = protect(source, [])
        return dict(text=text, source=source, protected=protected, terms=terms, language="en")

    def test_no_placeholder_examples_when_no_term_is_locked(self):
        requests = []
        def request(req, timeout):
            payload = json.loads(req.data)
            requests.append(payload)
            self.assertNotIn("__G", json.dumps(payload["messages"]))
            self.assertNotIn("Locked tokens in", payload["messages"][1]["content"])
            return io.BytesIO(json.dumps({"message": {"content": "Annonce d’un atelier."}}).encode())
        with patch("local_translation.urllib.request.urlopen", request):
            translated = generate_dialogue(self.dialogue("WORKSHOP ANNOUNCEMENT"), [],
                model="test", url="http://127.0.0.1")
        self.assertEqual(translated, "Annonce d’un atelier.")
        self.assertEqual(len(requests), 1)

    def test_invalid_generation_is_retried_and_validated(self):
        for source, invalid, valid, expected in (
            ("WORKSHOP ANNOUNCEMENT", "__G0__", "Annonce d’un atelier.", "Annonce d’un atelier."),
            ("Your cultivation is strong.", "__G0__ __G0__", "Ta __G0__ est puissante.", "Ta cultivation est puissante."),
            ("Your cultivation is strong.", "Ta force est puissante.", "Ta __G0__ est puissante.", "Ta cultivation est puissante."),
            ("We are waiting at school.", "我们 attendons.", "Nous attendons à l’école.", "Nous attendons à l’école."),
        ):
            requests = []
            def request(req, timeout):
                requests.append(json.loads(req.data))
                text = invalid if len(requests) == 1 else valid
                return io.BytesIO(json.dumps({"message": {"content": text}}).encode())
            with self.subTest(source=source, invalid=invalid), patch("local_translation.urllib.request.urlopen", request):
                result = generate_dialogue(self.dialogue(source), [], model="test", url="http://127.0.0.1")
                self.assertEqual(result, expected)
                self.assertEqual(len(requests), 2)
                self.assertIn("previous response failed validation", requests[1]["messages"][1]["content"])

    def test_repeated_invalid_generation_is_not_cached(self):
        calls = []
        def request(req, timeout):
            calls.append(req)
            return io.BytesIO(json.dumps({"message": {"content": "__G9__"}}).encode())
        with tempfile.TemporaryDirectory() as directory, patch("local_translation.urllib.request.urlopen", request), patch("local_translation.check_model"):
            with self.assertRaisesRegex(RuntimeError, "inventé"):
                translate(dict(segments=[dict(id="bad", text="Workshop announcement")]),
                    model="test", url="http://127.0.0.1", cache_dir=Path(directory))
            self.assertEqual(len(calls), 2)
            self.assertFalse(list(Path(directory).rglob("*.json")))

    def test_connection_failures_are_not_generation_retries(self):
        with patch("local_translation.urllib.request.urlopen", side_effect=urllib.error.URLError("offline")) as request:
            with self.assertRaises(urllib.error.URLError):
                generate_dialogue(self.dialogue("Workshop announcement"), [], model="test", url="http://127.0.0.1")
            self.assertEqual(request.call_count, 1)

    def test_valid(self):
        self.assertEqual(parse_translations('{"translations":[{"id":"a","text":"Bonjour."}]}', ["a"]), {"a": "Bonjour."})

    def test_bad_outputs(self):
        for content in ('[]', '{}', 'not json', '{"translations":[]}',
                        '{"translations":[{"id":"a","text":""}]}',
                        '{"translations":[{"id":"b","text":"Oui"}]}',
                        '{"translations":[{"id":"a","text":"Oui"},{"id":"a","text":"Non"}]}'):
            with self.subTest(content=content), self.assertRaises(RuntimeError):
                parse_translations(content, ["a"])

    def test_cache_and_override_invalidation(self):
        calls = []
        def request(req, timeout):
            payload = json.loads(req.data)
            self.assertFalse(payload["think"])
            self.assertNotIn("format", payload)
            calls.append(payload["messages"][1]["content"])
            return io.BytesIO(json.dumps({"message": {"content": "Bonjour __G0__"}}).encode())
        payload = dict(segments=[dict(id="a", text="Azure Moon")], targetLanguage="fr",
                       glossary=[dict(source="Azure Moon", translation="Lune bleue")])
        with tempfile.TemporaryDirectory() as directory, patch("local_translation.urllib.request.urlopen", request), patch("local_translation.check_model"):
            first = translate(payload, model="test", url="http://127.0.0.1", cache_dir=Path(directory))
            repeat = translate(payload, model="test", url="http://127.0.0.1", cache_dir=Path(directory))
            self.assertEqual(repeat["timing"]["cacheHits"], 1)
            payload["glossary"][0]["translation"] = "Lune rouge"
            changed = translate(payload, model="test", url="http://127.0.0.1", cache_dir=Path(directory))
            self.assertIn("Lune rouge", changed["segments"][0]["translatedText"])
            self.assertEqual(len(calls), 2)

    def test_thinking_only_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "thinking-only"):
            validate_model_metadata({"thinking": {"values": [True]}})
        with self.assertRaisesRegex(RuntimeError, "réflexion"):
            validate_model_metadata({"template": "assistant\\n<think>"})
        validate_model_metadata({"template": "assistant", "capabilities": ["thinking"]})
        validate_model_metadata({"template": "{% if history %}<think>{% endif %}\n{% if add_generation_prompt %}{{ '<|im_start|>assistant\\n' }}{% endif %}",
                                 "capabilities": ["thinking"]})

    def test_incomplete_translation_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "caractères"):
            validate_french("你的énergie spirituelle已经耗尽了！", "你的灵气已经耗尽了！")
        with self.assertRaisesRegex(RuntimeError, "recopiée"):
            validate_french("NE PAS ATTACK YET WE NEED TO KNOW", "Don't attack yet we need to know")
        validate_french("Ton énergie spirituelle est épuisée !", "你的灵气已经耗尽了！")

    def test_web_address_can_be_preserved_but_not_a_source_sentence(self):
        for address in ("workshop.example.org", "https://workshop.example.org/join-us", "ALBA. COM"):
            with self.subTest(address=address):
                validate_french(address, address)
        with self.assertRaises(RuntimeError):
            validate_french("Visit workshop.example.org now.", "Visit workshop.example.org now.")

    def test_restored_possessive_before_vowel(self):
        self.assertEqual(normalize_french_agreement("Ta énergie et ma amie."), "Ton énergie et mon amie.")
        self.assertEqual(normalize_french_agreement("Sa force et ma sœur."), "Sa force et ma sœur.")

    def test_bad_payload(self):
        for payload in ([], {}, dict(segments="bad"), dict(segments=[dict(text="")]),
                        dict(segments=[], targetLanguage="en")):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                translate(payload, model="test", url="local", cache_dir=Path("."))


class GeometryTests(unittest.TestCase):
    def image(self, white_background=False, color="white"):
        image = Image.new("RGB", (400, 300), color if white_background else "#345566")
        if not white_background:
            ImageDraw.Draw(image).ellipse((40, 30, 360, 270), fill=color, outline="black", width=4)
        data = io.BytesIO()
        image.save(data, format="PNG")
        return data.getvalue()

    def lines(self):
        return [dict(sourceText="师兄，突破金丹", boundingBox=dict(x=.25, y=.4, width=.5, height=.08)),
                dict(sourceText="境后，我们加入宗门。", boundingBox=dict(x=.25, y=.5, width=.5, height=.08))]

    def test_group_cjk_and_mask(self):
        result = fit_dialogue(self.image(), self.lines())
        self.assertEqual(len(result), 1)
        self.assertIn("金丹境", result[0]["sourceText"])
        self.assertEqual(result[0]["renderMode"], "replace")
        self.assertIn("maskData", result[0])
        mask = Image.open(io.BytesIO(base64.b64decode(result[0]["maskData"].split(",")[1])))
        self.assertEqual(mask.mode, "RGBA")
        self.assertEqual(mask.getpixel((0, 0))[3], 0)
        self.assertEqual(mask.getpixel((mask.width//2, mask.height//2))[3], 255)

    def test_english_spacing(self):
        lines = self.lines()
        lines[0]["sourceText"] = "GOLDEN"
        lines[1]["sourceText"] = "CORE"
        self.assertEqual(fit_dialogue(self.image(), lines)[0]["sourceText"], "GOLDEN CORE")

    def test_thin_outlines_on_matching_background(self):
        for color, outline in (("white", "black"), ("black", "white")):
            for thickness in (1, 2, 3):
                with self.subTest(color=color, thickness=thickness):
                    image = Image.new("RGB", (400, 300), color)
                    ImageDraw.Draw(image).ellipse((40, 30, 360, 270), fill=color,
                                                 outline=outline, width=thickness)
                    data = io.BytesIO()
                    image.save(data, format="PNG")
                    results = fit_dialogue(data.getvalue(), self.lines())
                    self.assertEqual(len(results), 1)
                    self.assertEqual(results[0]["renderMode"], "replace")

    def test_large_closed_bubble_not_rejected_by_size(self):
        image = Image.new("RGB", (400, 300), "#345566")
        ImageDraw.Draw(image).ellipse((5, 5, 395, 295), fill="white", outline="black", width=2)
        data = io.BytesIO()
        image.save(data, format="PNG")
        result = fit_dialogue(data.getvalue(), self.lines())
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["renderMode"], "replace")

    def test_closed_outline_on_image_border(self):
        for color, outline in (("white", "black"), ("black", "white")):
            with self.subTest(color=color):
                image = Image.new("RGB", (400, 300), color)
                ImageDraw.Draw(image).ellipse((0, 0, 399, 299), fill=color, outline=outline, width=1)
                data = io.BytesIO()
                image.save(data, format="PNG")
                results = fit_dialogue(data.getvalue(), self.lines())
                self.assertEqual(len(results), 1)
                self.assertEqual(results[0]["renderMode"], "replace")

    def test_line_union_can_cross_curve_without_crossing_text(self):
        lines = [
            dict(text="Hello", boundingBox=dict(x=.44, y=.20, width=.12, height=.06)),
            dict(text="A much longer sentence", boundingBox=dict(x=.21, y=.47, width=.58, height=.06)),
        ]
        results = fit_dialogue(self.image(), lines)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["renderMode"], "replace")
        self.assertEqual(results[0]["sourceText"], "Hello A much longer sentence")
        self.assertLess(results[0]["textBox"]["width"], results[0]["rawBoundingBox"]["width"])

    def test_unverified_preserves_art(self):
        results = fit_dialogue(self.image(True), self.lines())
        self.assertTrue(all(r["renderMode"] == "inspect" and "maskData" not in r for r in results))

    def test_dark_and_colored_interiors(self):
        for color, ink in (("#000000", "#ffffff"), ("#27365a", "#ffffff"),
                           ("#ffd966", "#111111"), ("#d98fa6", "#111111"), ("#e1bbcf", "#111111"),
                           ("#68c4b0", "#111111"), ("#b45555", "#ffffff"),
                           ("#777777", "#000000")):
            with self.subTest(color=color):
                result = fit_dialogue(self.image(color=color), self.lines())
                self.assertEqual(len(result), 1)
                self.assertEqual(result[0]["renderMode"], "replace")
                self.assertEqual(result[0]["style"]["fillColor"], color)
                self.assertEqual(result[0]["style"]["textColor"], ink)
                mask = Image.open(io.BytesIO(base64.b64decode(result[0]["maskData"].split(",")[1])))
                self.assertEqual(mask.mode, "RGBA")
                self.assertEqual(mask.getpixel((0, 0))[3], 0)
                self.assertEqual(mask.getpixel((mask.width//2, mask.height//2))[3], 255)

    def test_open_colored_background_preserved(self):
        for color in ("#000000", "#27365a", "#ffd966"):
            with self.subTest(color=color):
                results = fit_dialogue(self.image(True, color=color), self.lines())
                self.assertTrue(all(r["renderMode"] == "inspect" and "maskData" not in r for r in results))

    def test_colored_art_holes_not_filled(self):
        image = Image.open(io.BytesIO(self.image(color="#000000")))
        ImageDraw.Draw(image).rectangle((175, 200, 225, 220), fill="#ff5555")
        data = io.BytesIO()
        image.save(data, format="PNG")
        result = fit_dialogue(data.getvalue(), self.lines())[0]
        self.assertEqual(result["renderMode"], "replace")
        mask = Image.open(io.BytesIO(base64.b64decode(result["maskData"].split(",")[1])))
        x, y = round(result["boundingBox"]["x"]*400), round(result["boundingBox"]["y"]*300)
        self.assertEqual(mask.getpixel((200-x, 210-y))[3], 0)

    def test_white_art_and_unused_background_not_painted(self):
        image = Image.open(io.BytesIO(self.image()))
        ImageDraw.Draw(image).rectangle((175, 210, 225, 230), fill="black")
        data = io.BytesIO()
        image.save(data, format="PNG")
        result = fit_dialogue(data.getvalue(), self.lines())[0]
        self.assertEqual(result["renderMode"], "replace")
        mask = Image.open(io.BytesIO(base64.b64decode(result["maskData"].split(",")[1])))
        x, y = round(result["boundingBox"]["x"]*400), round(result["boundingBox"]["y"]*300)
        self.assertEqual(mask.getpixel((200-x, 220-y))[3], 0)
        self.assertEqual(mask.getpixel((200-x, 50-y))[3], 0)

    def test_nearby_punctuation_in_mask(self):
        image = Image.open(io.BytesIO(self.image(color="#000000")))
        ImageDraw.Draw(image).ellipse((197, 185, 204, 192), outline="white", width=2)
        data = io.BytesIO()
        image.save(data, format="PNG")
        result = fit_dialogue(data.getvalue(), self.lines())[0]
        self.assertEqual(result["renderMode"], "replace")
        mask = Image.open(io.BytesIO(base64.b64decode(result["maskData"].split(",")[1])))
        x, y = round(result["boundingBox"]["x"]*400), round(result["boundingBox"]["y"]*300)
        self.assertEqual(mask.getpixel((200-x, 188-y))[3], 255)
        self.assertGreater(result["textBox"]["height"]*300, 80)

    def test_text_contrast_floor(self):
        def luminance(rgb):
            values = [value/255 for value in rgb]
            linear = [value/12.92 if value <= .04045 else ((value+.055)/1.055)**2.4 for value in values]
            return sum(value*weight for value, weight in zip(linear, (.2126, .7152, .0722)))
        colors = [(value, value, value) for value in range(256)]
        colors += [(4, 130, 197), (4.5, 130.5, 197.5)]
        for rgb in colors:
            fill = np.array(rgb[::-1], dtype=float)
            ink = text_color(fill)
            foreground = luminance([int(ink[i:i+2], 16) for i in (1, 3, 5)])
            background = luminance([int(value) for value in rgb])
            ratio = (max(foreground, background)+.05)/(min(foreground, background)+.05)
            with self.subTest(rgb=rgb):
                self.assertGreaterEqual(ratio, 4.5)

    def test_textured_text_area_preserved(self):
        image = Image.open(io.BytesIO(self.image(color="#000000")))
        ImageDraw.Draw(image).rectangle((185, 100, 205, 190), fill="#cc5544")
        data = io.BytesIO()
        image.save(data, format="PNG")
        results = fit_dialogue(data.getvalue(), self.lines())
        self.assertTrue(all(r["renderMode"] == "inspect" and "maskData" not in r for r in results))

    def test_large_gradient_preserved(self):
        image = Image.new("RGB", (400, 300), "#345566")
        shape = Image.new("L", image.size, 0)
        ImageDraw.Draw(shape).ellipse((40, 30, 360, 270), fill=255)
        ramp = np.tile(np.linspace(0, 220, 400, dtype=np.uint8), (300, 1))
        gradient = Image.fromarray(np.stack((ramp, ramp, ramp), axis=2))
        image.paste(gradient, (0, 0), shape)
        data = io.BytesIO()
        image.save(data, format="PNG")
        results = fit_dialogue(data.getvalue(), self.lines())
        self.assertTrue(all(r["renderMode"] == "inspect" and "maskData" not in r for r in results))

    def test_single_clipped_edge_has_safe_interior(self):
        for color in ("white", "black"):
            with self.subTest(color=color):
                image = Image.new("RGB", (400, 300), "#345566")
                ImageDraw.Draw(image).ellipse((40, 30, 360, 340), fill=color)
                data = io.BytesIO()
                image.save(data, format="PNG")
                result = fit_dialogue(data.getvalue(), self.lines())
                self.assertEqual(len(result), 1)
                self.assertEqual(result[0]["renderMode"], "replace")

    def test_invalid_image(self):
        with self.assertRaises(ValueError):
            fit_dialogue(b"not an image", [])


class ContractTests(unittest.TestCase):
    def test_file_url_rejected(self):
        with self.assertRaises(ValueError):
            server.request_for("file:///etc/passwd")

    def test_extract(self):
        images = server.extract_images('<img src="/page-1.png"><img src="/page-2.png">', "https://example.org/chapter-1/")
        self.assertEqual([item["url"] for item in images], ["https://example.org/page-1.png", "https://example.org/page-2.png"])


class SourceAccessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        class SourceHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/chapter":
                    status, body = 200, b'<img src="/page-1.png"><img src="/page-2.png">'
                elif self.path == "/empty":
                    status, body = 200, b"<html><body>JavaScript required</body></html>"
                else:
                    status = int(self.path.lstrip("/"))
                    body = b"<html><body>PRIVATE UPSTREAM ERROR</body></html>"
                self.send_response(status)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        for name, handler in (("source", SourceHandler), ("preview", server.PreviewHandler)):
            instance = ThreadingHTTPServer(("127.0.0.1", 0), handler)
            cls.addClassCleanup(instance.server_close)
            cls.addClassCleanup(instance.shutdown)
            threading.Thread(target=instance.serve_forever, kwargs={"poll_interval": .01}, daemon=True).start()
            setattr(cls, name, f"http://127.0.0.1:{instance.server_port}")

    def request(self, endpoint, url=""):
        query = urllib.parse.urlencode({"url": url})
        try:
            response = urllib.request.urlopen(f"{self.preview}/v1/webtoon/{endpoint}?{query}", timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            self.assertEqual(response.headers.get_content_type(), "application/json")
            self.assertEqual(response.headers.get_content_charset(), "utf-8")
            return response.status, json.loads(response.read())

    def test_upstream_errors_are_json_and_do_not_reflect_html(self):
        cases = ((401, 502, "source_auth_required"), (403, 502, "source_access_denied"),
                 (404, 404, "source_not_found"), (429, 429, "source_rate_limited"),
                 (503, 502, "source_http_error"))
        for endpoint in ("extract", "image"):
            for upstream, expected, code in cases:
                with self.subTest(endpoint=endpoint, upstream=upstream):
                    status, payload = self.request(endpoint, f"{self.source}/{upstream}")
                    self.assertEqual(status, expected)
                    self.assertEqual(payload["code"], code)
                    self.assertEqual(payload["sourceStatus"], upstream)
                    self.assertNotIn("PRIVATE", payload["error"])
                    self.assertNotIn("<html>", payload["error"])
                    self.assertNotIn("images", payload)

    def test_missing_and_invalid_source(self):
        for endpoint in ("extract", "image"):
            for url, code in (("", "missing_source_url"), ("file:///tmp/page.png", "invalid_source_url"),
                              ("https://user:secret@example.org/", "invalid_source_url"),
                              ("http://127.0.0.1:notaport/", "invalid_source_url")):
                with self.subTest(endpoint=endpoint, url=url):
                    status, payload = self.request(endpoint, url)
                    self.assertEqual(status, 400)
                    self.assertEqual(payload["code"], code)
                    self.assertNotIn("secret", payload["error"])

    def test_empty_chapter_is_an_error_but_valid_chapter_still_opens(self):
        status, payload = self.request("extract", f"{self.source}/empty")
        self.assertEqual(status, 422)
        self.assertEqual(payload["code"], "chapter_images_missing")
        status, payload = self.request("extract", f"{self.source}/chapter")
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["images"]), 2)
        self.assertEqual(payload["pageURL"], f"{self.source}/chapter")

    def test_timeouts_and_network_errors(self):
        for error in (TimeoutError("PRIVATE"), socket.timeout("PRIVATE"),
                      urllib.error.URLError(socket.timeout("PRIVATE"))):
            with self.subTest(error=error):
                status, payload = server.source_failure(error)
                self.assertEqual((status, payload["code"]), (504, "source_timeout"))
                self.assertNotIn("PRIVATE", payload["error"])
        status, payload = server.source_failure(urllib.error.URLError("PRIVATE"))
        self.assertEqual((status, payload["code"]), (502, "source_unreachable"))
        self.assertNotIn("PRIVATE", payload["error"])


if __name__ == "__main__":
    unittest.main()
