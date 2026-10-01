import base64
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "PhonePreview"))
from PIL import Image, ImageDraw
from bubble_geometry import fit_dialogue
from glossary import entries, protect, restore
from local_translation import parse_translations, translate, validate_french, validate_model_metadata, normalize_french_agreement
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


class ModelTests(unittest.TestCase):
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

    def test_restored_possessive_before_vowel(self):
        self.assertEqual(normalize_french_agreement("Ta énergie et ma amie."), "Ton énergie et mon amie.")
        self.assertEqual(normalize_french_agreement("Sa force et ma sœur."), "Sa force et ma sœur.")

    def test_bad_payload(self):
        for payload in ([], {}, dict(segments="bad"), dict(segments=[dict(text="")]),
                        dict(segments=[], targetLanguage="en")):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                translate(payload, model="test", url="local", cache_dir=Path("."))


class GeometryTests(unittest.TestCase):
    def image(self, white_background=False):
        image = Image.new("RGB", (400, 300), "white" if white_background else "#345566")
        if not white_background:
            ImageDraw.Draw(image).ellipse((40, 30, 360, 270), fill="white", outline="black", width=4)
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

    def test_unverified_preserves_art(self):
        results = fit_dialogue(self.image(True), self.lines())
        self.assertTrue(all(r["renderMode"] == "inspect" and "maskData" not in r for r in results))

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


if __name__ == "__main__":
    unittest.main()
