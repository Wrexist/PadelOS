#!/usr/bin/env python3
"""Validate App Store metadata in docs/app-store/metadata/<locale>.json.

Stdlib only. Prints a per-locale table of field lengths and every violation,
and exits non-zero when any violation is found.

    python3 scripts/store/validate_metadata.py [metadata_dir]
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "docs" / "app-store" / "metadata"

EXPECTED_LOCALES = [
    "en-US", "en-GB", "es-ES", "es-MX", "sv", "it", "fr-FR", "de-DE", "pt-BR", "nl-NL",
]

LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}
KEYWORDS_TARGET_MIN = 90  # warning only: unused keyword space is wasted ranking potential

SCREENSHOT_IDS = [
    "01-dashboard", "02-watch", "03-schedule", "04-shared",
    "05-live-activity", "06-playoffs", "07-formats",
]
WATCH_IDS = ["w01-scoring", "w02-home", "w03-standings"]
HEADLINE_LINE_SOFT = 16  # warning above this
HEADLINE_LINE_MAX = 18
SUBLINE_MAX = 60

# Competitor brands and other trademarks seen in the App Store padel category, plus
# words App Review rejects or that we must not claim. Matched as whole words/phrases,
# case-insensitive, in every text field.
BANNED = [
    "playtomic", "padelfast", "padel fast", "padel40", "padelzone", "padelpro", "padelore",
    "padelgod", "padeltick", "padelboard", "padel puffin", "banana padel", "padelscore",
    "padelscoring", "padel mate", "padelmate", "rankedin", "matchi", "padel set&play",
    "padel americano go", "americano padel manager", "padel americano generator",
    "premier padel", "world padel tour", "hexagon cup",
    # No price claims.
    "free", "gratis", "gratuit", "gratuite", "gratuito", "gratuita", "kostenlos", "kostenlose",
    "gratuitement", "gratuitamente",
    # Platform names that are not ours to rank on / App Review flags.
    "android", "google play",
]
KEYWORD_FILLER = {"app", "apps", "iphone", "ios", "ipad", "best", "top", "new"}
DESCRIPTION_MARKUP = ["**", "__", "#", "`", "<", ">", "](", "[ ]"]

LETTERS = re.compile(r"[^\W\d_]+", re.UNICODE)


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def words(s: str) -> list[str]:
    return [w.casefold() for w in LETTERS.findall(nfc(s))]


def contains_phrase(text: str, phrase: str) -> bool:
    pattern = r"(?<![\w])" + re.escape(phrase) + r"(?![\w])"
    return re.search(pattern, nfc(text), re.IGNORECASE | re.UNICODE) is not None


def check_caption(errors: list, warnings: list, where: str, cap, expected_id: str) -> None:
    if not isinstance(cap, dict):
        errors.append(f"{where}: must be an object")
        return
    for key in ("id", "headline", "highlight", "subline"):
        if not isinstance(cap.get(key), str) or not cap.get(key).strip():
            errors.append(f"{where}: missing or empty '{key}'")
    if errors and any(e.startswith(where) for e in errors):
        return
    if cap["id"] != expected_id:
        errors.append(f"{where}: id '{cap['id']}' != expected '{expected_id}'")
    lines = cap["headline"].split("\n")
    if len(lines) != 2:
        errors.append(f"{where}: headline must have exactly 2 lines, has {len(lines)}")
    for i, line in enumerate(lines, 1):
        n = len(nfc(line))
        if line != line.strip() or not line:
            errors.append(f"{where}: headline line {i} empty or padded")
        if n > HEADLINE_LINE_MAX:
            errors.append(f"{where}: headline line {i} is {n} chars (max {HEADLINE_LINE_MAX}): {line!r}")
        elif n > HEADLINE_LINE_SOFT:
            warnings.append(f"{where}: headline line {i} is {n} chars (aim <= {HEADLINE_LINE_SOFT})")
    hl = cap["highlight"]
    if hl not in cap["headline"].replace("\n", " ") and hl not in lines:
        errors.append(f"{where}: highlight {hl!r} does not occur verbatim in headline")
    if "\n" in hl or len(hl.split()) > 2:
        errors.append(f"{where}: highlight must be one word or a two-word unit: {hl!r}")
    sub = cap["subline"]
    if "\n" in sub:
        errors.append(f"{where}: subline must be a single line")
    if len(nfc(sub)) > SUBLINE_MAX:
        errors.append(f"{where}: subline is {len(nfc(sub))} chars (max {SUBLINE_MAX})")


def validate(locale: str, data) -> tuple[list[str], list[str], dict]:
    errors: list[str] = []
    warnings: list[str] = []
    lengths: dict = {}

    if not isinstance(data, dict):
        return [f"{locale}: top level must be an object"], warnings, lengths
    if "locale" in data and data["locale"] != locale:
        errors.append(f"locale field {data['locale']!r} does not match file name")

    for field, limit in LIMITS.items():
        value = data.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{field}: missing or empty string")
            continue
        n = len(nfc(value))
        lengths[field] = n
        if n > limit:
            errors.append(f"{field}: {n} chars (max {limit})")
        if value != value.strip():
            errors.append(f"{field}: leading or trailing whitespace")
    if errors:
        return errors, warnings, lengths

    name, subtitle, keywords = data["name"], data["subtitle"], data["keywords"]

    if not name.startswith("PadelOS"):
        errors.append("name: must start with the brand 'PadelOS'")
    if "\n" in name or "\n" in subtitle or "\n" in keywords:
        errors.append("name/subtitle/keywords: must be single-line")

    # Keywords.
    if ", " in keywords or " ," in keywords:
        errors.append("keywords: no spaces around commas")
    items = keywords.split(",")
    indexed = set(words(name)) | set(words(subtitle))
    seen: set[str] = set()
    for item in items:
        if not item:
            errors.append("keywords: empty item (double or trailing comma)")
            continue
        if item != item.strip():
            errors.append(f"keywords: item {item!r} has surrounding whitespace")
        key = nfc(item).casefold()
        if key in seen:
            errors.append(f"keywords: duplicate item {item!r}")
        seen.add(key)
        for w in words(item):
            if w in indexed:
                errors.append(f"keywords: {item!r} repeats {w!r} from name/subtitle")
            if w in KEYWORD_FILLER:
                errors.append(f"keywords: filler word {w!r}")
    if lengths["keywords"] < KEYWORDS_TARGET_MIN:
        warnings.append(f"keywords: only {lengths['keywords']} of 100 chars used")

    # Banned words in every text field.
    texts = {f: data[f] for f in LIMITS}
    for group in ("screenshotCaptions", "watchCaptions"):
        for i, cap in enumerate(data.get(group) or []):
            if isinstance(cap, dict):
                for k in ("headline", "subline"):
                    if isinstance(cap.get(k), str):
                        texts[f"{group}[{i}].{k}"] = cap[k]
    for field, text in texts.items():
        for banned in BANNED:
            if contains_phrase(text, banned):
                errors.append(f"{field}: banned word/trademark {banned!r}")

    # Description is plain text.
    desc = data["description"]
    for mark in DESCRIPTION_MARKUP:
        if mark in desc:
            errors.append(f"description: markup character {mark!r} (App Store shows plain text)")
    if "\n\n\n" in desc:
        warnings.append("description: more than one blank line in a row")

    # Captions.
    for group, ids in (("screenshotCaptions", SCREENSHOT_IDS), ("watchCaptions", WATCH_IDS)):
        caps = data.get(group)
        if not isinstance(caps, list):
            errors.append(f"{group}: missing or not an array")
            continue
        if len(caps) != len(ids):
            errors.append(f"{group}: expected {len(ids)} items, found {len(caps)}")
        for i, (cap, expected) in enumerate(zip(caps, ids)):
            check_caption(errors, warnings, f"{group}[{i}]", cap, expected)

    known = set(LIMITS) | {"locale", "screenshotCaptions", "watchCaptions"}
    for key in data:
        if key not in known:
            warnings.append(f"unknown field {key!r}")
    return errors, warnings, lengths


def main(argv: list[str]) -> int:
    directory = Path(argv[1]) if len(argv) > 1 else DEFAULT_DIR
    files = sorted(directory.glob("*.json"))
    total_errors = 0
    rows = []
    report = []

    found = {f.stem for f in files}
    for missing in [l for l in EXPECTED_LOCALES if l not in found]:
        report.append(f"[{missing}] ERROR file missing")
        total_errors += 1

    for path in files:
        locale = path.stem
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            report.append(f"[{locale}] ERROR cannot read JSON: {exc}")
            total_errors += 1
            continue
        errors, warnings, lengths = validate(locale, data)
        total_errors += len(errors)
        rows.append((locale, lengths, "FAIL" if errors else "ok"))
        report += [f"[{locale}] ERROR {e}" for e in errors]
        report += [f"[{locale}] warn  {w}" for w in warnings]

    header = f"{'locale':<7} {'name':>4}/30 {'sub':>4}/30 {'kw':>4}/100 {'promo':>5}/170 {'desc':>5}/4000  status"
    print(header)
    print("-" * len(header))
    for locale, ln, status in rows:
        g = lambda k, w: str(ln.get(k, "-")).rjust(w)
        print(f"{locale:<7} {g('name', 4)}/30 {g('subtitle', 4)}/30 {g('keywords', 4)}/100 "
              f"{g('promotionalText', 5)}/170 {g('description', 5)}/4000  {status}")
    if report:
        print()
        print("\n".join(report))
    print()
    print(f"{len(rows)} locale file(s), {total_errors} error(s)")
    return 1 if total_errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
