#!/usr/bin/env python3
"""Builds the String Catalogs (Localizable.xcstrings) for every app target.

Inputs (all in Localization/):
  keys.json                 {"<target>": ["English key", ...]} — keys extracted by
                            `xcodebuild -exportLocalizations` plus the shared package's
                            L10n.string/L10n.format keys (added by this script).
  plurals.json              {"English key": {"one": "...", "other": "..."}} — English
                            plural forms for keys with a single %lld count.
  translations/<lang>.json  {"English key": "translation" | {"one": ..., "other": ...}}

Outputs: Apps/<target dir>/Localizable.xcstrings

Usage: python3 scripts/build_string_catalogs.py [--check]
  --check  fail if any key is missing a translation or a placeholder mismatch exists.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOC = ROOT / "Localization"
LANGUAGES = ["es", "ca", "pt-PT", "pt-BR", "fr", "it", "de", "nl", "sv", "da", "nb", "fi", "pl", "cs", "ru", "ar", "ja", "zh-Hans"]
TARGET_DIRS = {
    "ios": "Apps/iOS",
    "watch": "Apps/Watch",
    "ios-widget": "Apps/iOSWidget",
    "watch-widget": "Apps/WatchWidget",
}
# Targets that link the shared package and show its text.
PACKAGE_TARGETS = ["ios", "watch"]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f|%)")


def package_keys():
    keys = set()
    pattern = re.compile(r'L10n\.(?:string|format)\(\s*"((?:[^"\\]|\\.)*)"')
    for path in (ROOT / "Packages/PadelKit/Sources").rglob("*.swift"):
        for match in pattern.finditer(path.read_text()):
            keys.add(match.group(1).encode().decode("unicode_escape") if "\\" in match.group(1) else match.group(1))
    return keys


def placeholders(text):
    return sorted(p for p in PLACEHOLDER.findall(text) if p != "%%")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def entry(key, lang_value):
    if isinstance(lang_value, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in lang_value.items()}}}
    return unit(lang_value)


def main():
    check = "--check" in sys.argv
    keys = json.loads((LOC / "keys.json").read_text())
    plurals = json.loads((LOC / "plurals.json").read_text())
    translations = {lang: json.loads((LOC / "translations" / f"{lang}.json").read_text()) for lang in LANGUAGES
                    if (LOC / "translations" / f"{lang}.json").exists()}
    extra = package_keys()
    problems = []
    for target, directory in TARGET_DIRS.items():
        target_keys = set(keys.get(target, []))
        if target in PACKAGE_TARGETS:
            target_keys |= extra
        strings = {}
        for key in sorted(target_keys):
            localizations = {}
            if key in plurals:
                localizations["en"] = entry(key, plurals[key])
            for lang, table in translations.items():
                value = table.get(key)
                if value is None:
                    problems.append(f"{lang}: missing {key!r}")
                    continue
                texts = value.values() if isinstance(value, dict) else [value]
                for text in texts:
                    if placeholders(text) != placeholders(key) and not (isinstance(value, dict) and placeholders(text) == []):
                        problems.append(f"{lang}: placeholder mismatch {key!r} -> {text!r}")
                if isinstance(value, dict) and "other" not in value:
                    problems.append(f"{lang}: plural without 'other' for {key!r}")
                localizations[lang] = entry(key, value)
            item = {}
            if localizations:
                item["localizations"] = localizations
            if not PLACEHOLDER.search(key) and not re.search(r"[A-Za-z]", key):
                item["shouldTranslate"] = False
            strings[key] = item
        catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
        out = ROOT / directory / "Localizable.xcstrings"
        out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
        print(f"{out.relative_to(ROOT)}: {len(strings)} strings")
    unique = sorted(set(problems))
    for problem in unique[:80]:
        print("  " + problem)
    if unique:
        print(f"{len(unique)} problems")
    if check and unique:
        sys.exit(1)


if __name__ == "__main__":
    main()
