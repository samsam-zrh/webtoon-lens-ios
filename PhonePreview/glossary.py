"""Petit lexique éditable, priorités par série et correspondances les plus longues."""
from __future__ import annotations

import csv
from functools import lru_cache
from pathlib import Path
import re
from collections import Counter
from opencc import OpenCC

TRADITIONAL = OpenCC("s2t")


@lru_cache(maxsize=1)
def entries() -> list[dict]:
    with Path(__file__).with_name("glossary.tsv").open(encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def term_pattern(source: str) -> str:
    escaped = re.escape(source)
    if re.search(r"[A-Za-z]", source):
        return r"(?<!\w)" + escaped + r"(?!\w)"
    return escaped


def protect(text: str, overrides: list[dict]) -> tuple[str, dict[str, str], list[dict]]:
    terms = {}
    for entry in entries():
        for source in (entry["en"], entry["zh"], TRADITIONAL.convert(entry["zh"])):
            terms[source.casefold()] = dict(
                source=source, translation=entry["fr"],
                category=entry["category"], context=entry["context"], locked=entry.get("policy") == "literal",
            )
    if not isinstance(overrides, list) or len(overrides) > 500:
        raise ValueError("Le glossaire doit contenir au plus 500 corrections.")
    for item in overrides:
        if not isinstance(item, dict):
            raise ValueError("Correction de glossaire invalide.")
        source = str(item.get("source", "")).strip()
        translation = str(item.get("translation", "")).strip()
        if not source or not translation or len(source) > 120 or len(translation) > 200:
            raise ValueError("Chaque correction doit avoir un terme et une traduction courts.")
        if item.get("isLocked", True):
            terms[source.casefold()] = dict(source=source, translation=translation,
                                            category=item.get("category", "unknown"),
                                            context="Correction exacte de la série.", locked=True)
    ordered = sorted(terms.values(), key=lambda term: len(term["source"]), reverse=True)
    pattern = re.compile("|".join(f"(?:{term_pattern(term['source'])})" for term in ordered), re.IGNORECASE)
    protected = {}
    used = []

    def substitute(match):
        term = terms[match.group().casefold()]
        used.append(term)
        if not term["locked"]:
            return match.group()
        token = f"__G{len(protected)}__"
        protected[token] = term["translation"]
        return token

    return pattern.sub(substitute, text), protected, used


def restore(text: str, protected: dict[str, str]) -> str:
    missing = Counter(target for token, target in protected.items() if token not in text)
    for target, count in missing.items():
        if len(re.findall(re.escape(target), text, re.IGNORECASE)) < count:
            raise RuntimeError(f"Le modèle a omis le terme verrouillé « {target} ». Relancez la traduction.")
    for token, target in protected.items():
        text = text.replace(token, target)
    if re.search(r"__G\d+__", text):
        raise RuntimeError("Le modèle a inventé un terme de glossaire.")
    return text
