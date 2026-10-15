#!/usr/bin/env python3
"""Checks Localization/translations/<lang>.json against Localization/source-strings.json.

Usage: python3 scripts/check_translation.py <lang> [<lang> ...]
Exit code 1 if any problem is found.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDER = re.compile(r"%(\d+\$)?(lld|ld|d|@|lf|f)")
PLURAL_FORMS = {"zero", "one", "two", "few", "many", "other"}


def types(text):
    """Placeholder types in argument order (positional %1$@ forms are resolved)."""
    found = PLACEHOLDER.findall(text)
    if any(position for position, _ in found):
        return sorted((int(position[:-1]) if position else index + 1, kind) for index, (position, kind) in enumerate(found))
    return [(index + 1, kind) for index, (_, kind) in enumerate(found)]


def check(lang):
    source = json.loads((ROOT / "Localization/source-strings.json").read_text())
    keys = source["keys"]
    path = ROOT / "Localization/translations" / f"{lang}.json"
    table = json.loads(path.read_text())
    problems = []
    for key in keys:
        if key not in table:
            problems.append(f"missing: {key!r}")
            continue
        value = table[key]
        expected = types(key)
        if isinstance(value, dict):
            if [k for _, k in expected] != ["lld"]:
                problems.append(f"plural object only allowed for keys with exactly one %lld: {key!r}")
            if "other" not in value or set(value) - PLURAL_FORMS:
                problems.append(f"plural forms must be among {sorted(PLURAL_FORMS)} and include 'other': {key!r}")
            texts = value.values()
        elif isinstance(value, str):
            texts = [value]
        else:
            problems.append(f"value must be a string or plural object: {key!r}")
            continue
        for text in texts:
            if not isinstance(text, str) or not text.strip() and key.strip():
                problems.append(f"empty translation: {key!r}")
                continue
            got = types(text)
            # A plural form may omit the number ("one" -> "a court") in some languages.
            if got != expected and not (isinstance(value, dict) and got == []):
                problems.append(f"placeholders differ: {key!r} -> {text!r}")
            if key.count("\n") != text.count("\n"):
                problems.append(f"line breaks differ ({key.count(chr(10))} expected): {key!r} -> {text!r}")
    for extra in set(table) - set(keys):
        problems.append(f"unknown key: {extra!r}")
    return problems


def main():
    failed = False
    for lang in sys.argv[1:]:
        problems = check(lang)
        print(f"{lang}: {'OK' if not problems else str(len(problems)) + ' problems'}")
        for problem in problems[:60]:
            print("  " + problem)
        failed |= bool(problems)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
