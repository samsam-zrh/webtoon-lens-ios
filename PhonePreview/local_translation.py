"""Traduction locale stricte, cache par dialogue et glossaire réellement verrouillé."""
from __future__ import annotations

import hashlib
import json
import logging
from pathlib import Path
import re
import threading
import time
import urllib.error
import urllib.request

from glossary import protect, restore

LOCK = threading.Lock()
VERSION = "local-fr-plain-v15"
MODEL_CHECKS = {}


class DialogueTranslationError(RuntimeError):
    def __init__(self, segment_id: str, message: str):
        super().__init__(message)
        self.segment_id = segment_id


def nearby_context(context: list, segment_id: str) -> list:
    index = next((index for index, item in enumerate(context)
                  if isinstance(item, dict) and str(item.get("id")) == segment_id), None)
    candidates = context[max(0, index-2):index+3] if index is not None else context[-3:]
    return [{"text": str(item.get("text", ""))} for item in candidates if isinstance(item, dict)]


def validate_model_metadata(metadata: dict) -> None:
    thinking = metadata.get("thinking")
    if isinstance(thinking, dict) and thinking.get("values") == [True]:
        raise RuntimeError("Modèle thinking-only incompatible. Installez qwen3:4b-instruct-2507-q4_K_M.")
    template = metadata.get("template", "")
    # Certains tags annoncent 'thinking' par famille, malgré un template Instruct.
    if re.search(r"<think>\s*(?:{{[^}]*}}\s*)*$", template) and not any(flag in template for flag in (".Think", "enable_thinking")):
        raise RuntimeError("Ce template impose la réflexion. Utilisez le tag Qwen Instruct, pas qwen3:4b.")


def check_model(model: str, url: str) -> None:
    key = (model, url)
    if time.monotonic() - MODEL_CHECKS.get(key, 0) < 60:
        return
    request = urllib.request.Request(url.rstrip("/")+"/api/show",
        data=json.dumps({"model": model}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        validate_model_metadata(json.load(response))
    MODEL_CHECKS[key] = time.monotonic()


def is_web_address(text: str) -> bool:
    return re.fullmatch(
        r"(?:https?://)?(?:[A-Za-z0-9-]+\s*\.\s*)+[A-Za-z]{2,}(?:[/:?#][^\s]*)?",
        text.strip(),
    ) is not None


def validate_french(text: str, source: str) -> None:
    if not text.strip() or text.startswith(("[fr]", "{", "```")) or "<think>" in text:
        raise RuntimeError("Le modèle n'a pas renvoyé un dialogue français exploitable.")
    if re.search(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", text):
        raise RuntimeError("Traduction refusée : des caractères de la langue source subsistent.")
    if re.match(r"^\s*(?:était|étaient|est|sont|sera|seront)[ -]+nous\b", text, flags=re.IGNORECASE):
        raise RuntimeError("Accord français invalide : le sujet « nous » exige la première personne du pluriel, ou une construction présentative correctement accordée.")
    fragment = re.match(r"^\s*(?:was|were|is|are)\s+(?:me|us|him|her|them)\b", source, flags=re.IGNORECASE)
    if fragment and "?" not in source and re.match(
            r"^\s*(?:sommes|étions|étais|était|étaient|est|sont)[- ]+(?:nous|je|il|elle|ils|elles)\b",
            text, flags=re.IGNORECASE):
        raise RuntimeError("Un fragment déclaratif anglais a été transformé en question. Traduisez le prédicat comme une affirmation française naturelle, à l'aide du contexte.")
    original = re.findall(r"[a-z]+", source.casefold())
    output = re.findall(r"[a-z]+", text.casefold())
    if output == original and is_web_address(source):
        return
    if output == original and original and all(word in {"ah", "ha", "oh", "hm", "hmm", "mm", "mmm"} for word in original):
        return
    for index in range(max(0, len(original)-3)):
        phrase = original[index:index+4]
        if any(output[j:j+4] == phrase for j in range(max(0, len(output)-3))):
            raise RuntimeError("Traduction refusée : une phrase anglaise a été recopiée.")
    if len(original) >= 3 and output == original:
        raise RuntimeError("Traduction refusée : dialogue inchangé.")


def generate_dialogue(item: dict, context: list, *, model: str, url: str) -> str:
    terminology = "\n".join(f'{term["source"]} = {term["translation"]} ({term["context"]})'
                            for term in item["terms"])
    text = item["text"]
    letters = re.findall("[A-Za-z]", text)
    if letters and all(letter.isupper() for letter in letters):
        parts = re.split(r"(__G\d+__)", text)
        text = "".join(part if re.fullmatch(r"__G\d+__", part) else part.lower() for part in parts)
        text = text[:1].upper()+text[1:]
    context_text = "\n".join(str(c.get("text", "")) for c in context if isinstance(c, dict))
    if item["protected"]:
        locked_meanings = "\n".join(f"{token} = {target}" for token, target in item["protected"].items())
        locked_section = (
            "Locked tokens in this dialogue (copy each listed token exactly once; "
            "use its French meaning for articles and agreement):\n"
            f"{locked_meanings}\n\n"
        )
        locked_instruction = (
            "Preserve ONLY the locked tokens listed for this dialogue, each exactly once. "
            "Never introduce other tokens or replace an ordinary word with a token. "
        )
    else:
        locked_section = ""
        locked_instruction = ""
    address_instruction = "This item is a web address: copy it exactly, without translating its parts. " if is_web_address(item["source"]) else ""
    content = f"Terminology preferences (choose the appropriate grammar and gender):\n{terminology}\n\n" if terminology else ""
    content += locked_section
    if context_text:
        content += f"Nearby text for context only:\n{context_text}\n\n"
    language_name = {"en": "English", "zh": "Chinese"}.get(item["language"], item["language"])
    content += f"{language_name} text to translate:\n{text}\n\nFrench translation:"
    payload = dict(model=model, stream=False, think=False, keep_alive="10m",
                   options=dict(temperature=0, num_ctx=4096, num_predict=512),
                   messages=[
                       dict(role="system", content=(
                           "Translate the English or Chinese input into natural French. "
                           "Output only the complete French translation. Translate headings too. "
                           "The nearby text is context only. "
                           "Use it to resolve sentence fragments in natural French. "
                           "Keep statements as statements, not questions. "
                           + locked_instruction + address_instruction
                       )),
                       dict(role="user", content=content),
                   ])
    for attempt in range(2):
        request = urllib.request.Request(url.rstrip("/")+"/api/chat", data=json.dumps(payload, ensure_ascii=False).encode(),
                                         headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(request, timeout=120) as response:
            raw = json.load(response)
        if raw.get("done_reason") == "length":
            raise RuntimeError("Traduction tronquée par le modèle.")
        translated = raw.get("message", {}).get("content")
        if not isinstance(translated, str):
            raise RuntimeError("Réponse du modèle mal formée : dialogue absent.")
        translated = translated.strip()
        try:
            validate_french(translated, item["text"])
            restored = normalize_french_agreement(restore(translated, item["protected"]))
            validate_french(restored, item["source"])
        except RuntimeError as error:
            if attempt:
                raise
            logging.warning("Traduction rejetée, une nouvelle génération est tentée : %s", error)
            payload["messages"][1]["content"] = content + (
                "\n\nThe previous response failed validation: " + str(error) +
                "\nTranslate this dialogue again in complete French. Follow the exact listed locked terms, "
                "do not introduce any unlisted placeholder, and do not copy source sentences. "
                "Return only the corrected translation."
            )
        else:
            return restored
    raise RuntimeError("Le modèle n’a pas produit de traduction valide.")


def normalize_french_agreement(text: str) -> str:
    # Après restauration, « ta __G0__ » peut devenir « ta énergie ».
    possessives = {"ma": "mon", "ta": "ton", "sa": "son"}
    def replace(match):
        word = match.group(1)
        replacement = possessives[word.lower()]
        return replacement.capitalize() if word[0].isupper() else replacement
    return re.sub(r"\b(ma|ta|sa)(?=\s+[aeiouàâäéèêëîïôöùûüœ])", replace, text, flags=re.IGNORECASE)


def parse_translations(content: str, expected: list[str]) -> dict[str, str]:
    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Le modèle a renvoyé un JSON invalide.") from exc
    items = parsed.get("translations") if isinstance(parsed, dict) else None
    if not isinstance(items, list):
        raise RuntimeError("Réponse du modèle : liste translations manquante.")
    result = {}
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("text"), str):
            raise RuntimeError("Réponse du modèle : traduction mal formée.")
        key = item.get("id")
        text = item["text"].strip()
        if key not in expected or key in result or not text or text.startswith("[fr]"):
            raise RuntimeError("Réponse du modèle : identifiant, doublon ou texte invalide.")
        result[key] = text
    if set(result) != set(expected):
        raise RuntimeError("Le modèle a omis des bulles. Relancez la traduction.")
    return result


def translate(payload: dict, *, model: str, url: str, cache_dir: Path, fallback=None) -> dict:
    if not isinstance(payload, dict) or not isinstance(payload.get("segments"), list):
        raise ValueError("La requête doit contenir une liste segments.")
    if payload.get("targetLanguage", "fr") != "fr":
        raise ValueError("Ce lecteur traduit uniquement vers le français.")
    segments = payload["segments"]
    if len(segments) > 32:
        raise ValueError("Au plus 32 bulles par requête.")
    started = time.perf_counter()
    prepared, cached, keys = [], {}, {}
    glossary = payload.get("glossary", [])
    full_context = payload.get("contextSegments", [])
    if not isinstance(full_context, list):
        raise ValueError("Le contexte doit être une liste.")
    source_ids = set()
    for index, segment in enumerate(segments):
        if not isinstance(segment, dict):
            raise ValueError("Segment invalide.")
        source = segment.get("sourceText") or segment.get("text", "")
        key = str(segment.get("id", f"segment-{index}"))
        if key in source_ids or not isinstance(source, str) or not source.strip() or len(source) > 4000:
            raise ValueError("Texte vide, trop long ou identifiant répété.")
        source_ids.add(key)
        text, protected, used = protect(source, glossary)
        language = payload.get("sourceLanguage", "auto")
        if language == "auto":
            language = "zh" if re.search(r"[\u3400-\u9fff]", source) else "en"
        context = nearby_context(full_context, key)
        seed = dict(version=VERSION, model=model, source=source, language=language,
                    terms=used, context=context, style=payload.get("style", ""))
        digest = hashlib.sha256(json.dumps(seed, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        path = cache_dir / "dialogue" / f"{digest}.json"
        keys[key] = path
        if path.exists():
            try:
                entry = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(entry.get("text"), str) and entry["text"]:
                    cached[key] = entry["text"]
                    continue
            except (OSError, json.JSONDecodeError) as exc:
                logging.warning("Cache de traduction illisible %s : %s", path, exc)
        prepared.append(dict(id=key, text=text, source=source, protected=protected,
                             terms=used, language=language, context=context))
    hits = len(cached)
    if prepared:
        with LOCK:
            # Une autre requête peut avoir rempli ces entrées pendant l'attente.
            remaining = []
            for item in prepared:
                path = keys[item["id"]]
                if path.exists():
                    try:
                        cached[item["id"]] = json.loads(path.read_text(encoding="utf-8"))["text"]
                        hits += 1
                        continue
                    except (OSError, ValueError, KeyError) as exc:
                        logging.warning("Cache concurrent illisible : %s", exc)
                remaining.append(item)
            prepared = remaining
            for item in prepared:
                try:
                    check_model(model, url)
                    try:
                        cached[item["id"]] = generate_dialogue(item, item["context"], model=model, url=url)
                    except RuntimeError as exc:
                        raise DialogueTranslationError(item["id"], str(exc)) from exc
                except (urllib.error.URLError, TimeoutError, OSError) as exc:
                    if fallback is None:
                        raise RuntimeError(f"Ollama indisponible ({model}). Démarrez Ollama et installez le modèle.") from exc
                    logging.warning("Ollama indisponible, moteur portable local : %s", exc)
                    if item["protected"]:
                        raise RuntimeError("Le moteur portable ne garantit pas ce glossaire. Activez Ollama.") from exc
                    cached[item["id"]] = fallback(item["source"], item["language"])
                    validate_french(cached[item["id"]], item["source"])
                path = keys[item["id"]]
                try:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    temporary = path.with_suffix(".tmp")
                    temporary.write_text(json.dumps(dict(text=cached[item["id"]]), ensure_ascii=False), encoding="utf-8")
                    temporary.replace(path)
                except OSError as exc:
                    logging.warning("Cache non enregistré : %s", exc)
    result = []
    for index, segment in enumerate(segments):
        key = str(segment.get("id", f"segment-{index}"))
        result.append({**segment, "id": key,
                       "sourceText": segment.get("sourceText") or segment.get("text", ""),
                       "translatedText": cached[key],
                       "boundingBox": segment.get("boundingBox", dict(x=0, y=0, width=0, height=0)),
                       "confidence": float(segment.get("confidence", 0.7)),
                       "readingOrder": int(segment.get("readingOrder", index))})
    return dict(segments=result, detectedSourceLanguage=payload.get("sourceLanguage", "auto"),
                glossaryUpdates=[], confidence=0.7,
                timing=dict(totalMs=round((time.perf_counter()-started)*1000, 1), cacheHits=hits, translated=len(prepared)))
