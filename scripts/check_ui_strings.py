#!/usr/bin/env python3
"""Flags user-visible strings in the app code that are missing from Localization/keys.json.

SwiftUI turns a string literal into a localization key when it is passed to Text, Label,
Button, Toggle, Picker, navigationTitle, accessibilityLabel, String(localized:) and our
own components (SectionHeader, EmptyStateView, StepCard, …). A key that is not in
keys.json never gets translated, so the user sees English. This script finds those
literals without Xcode, so it runs on Linux CI.

It also flags *suspicious raw strings*: interpolated literals with words in them that are
built outside any localizable call (e.g. `"\\(n) courts"` returned as a plain String),
which is how "2 courts · 24 points" once reached Swedish users in English. Silence a
deliberate one with a `// l10n-ignore` comment on the same line.

Usage: python3 scripts/check_ui_strings.py [--target ios|watch|ios-widget|watch-widget|all]
Exit code 1 when a key is missing or a suspicious string is found.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET_SOURCES = {
    "ios": ["Apps/iOS", "Apps/Shared"],
    "watch": ["Apps/Watch", "Apps/Shared"],
    "ios-widget": ["Apps/iOSWidget", "Apps/LiveActivityShared"],
    "watch-widget": ["Apps/WatchWidget", "Apps/WatchShared"],
}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|lf|f)")

# Calls whose first argument is a localization key when it is a literal.
FIRST_ARGUMENT_CALLS = [
    "Text", "Label", "Button", "Toggle", "Picker", "Stepper", "TextField", "SecureField",
    "Section", "ProgressView", "DisclosureGroup", "Menu", "LabeledContent", "ShareLink",
    "SectionHeader", "promise",
    ".navigationTitle", ".confirmationDialog", ".alert", ".accessibilityLabel",
    ".accessibilityHint", ".accessibilityValue", ".help", "SharePreview",
    "LocalizedStringKey", "LocalizedStringResource",
]
# Labelled arguments that take a key in our components and SwiftUI initialisers.
LABELLED_ARGUMENTS = ["title", "message", "subtitle", "titleKey", "named"]


def read_string_literal(source, start):
    """Parses a Swift string literal starting at `source[start] == '"'`.

    Returns (end_index_after_literal, pieces) where pieces are text segments and None for
    each interpolation, or None if this is a multi-line or raw literal we do not handle.
    """
    if source.startswith('"""', start):
        return None
    i = start + 1
    pieces, text = [], []
    while i < len(source):
        ch = source[i]
        if ch == "\\":
            nxt = source[i + 1] if i + 1 < len(source) else ""
            if nxt == "(":
                pieces.append("".join(text))
                text = []
                pieces.append(None)
                i = skip_balanced(source, i + 1)
                continue
            text.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(nxt, nxt))
            i += 2
            continue
        if ch == '"':
            pieces.append("".join(text))
            return i + 1, pieces
        if ch == "\n":
            return None
        text.append(ch)
        i += 1
    return None


def skip_balanced(source, start):
    """`source[start] == '('`: returns the index after the matching ')', skipping strings."""
    depth = 0
    i = start
    while i < len(source):
        ch = source[i]
        if ch == '"':
            parsed = read_string_literal(source, i)
            i = parsed[0] if parsed else i + 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def key_of(pieces):
    """Literal pieces to the key Xcode extracts, with every placeholder as '¤'."""
    return "".join("¤" if piece is None else piece for piece in pieces)


def normalize_key(key):
    return PLACEHOLDER.sub("¤", key)


def is_translatable(key):
    return bool(re.search(r"[^\W\d_]", key.replace("¤", "")))


def top_level_literals(source, start, end):
    """String literals in source[start:end] that are not inside a nested call."""
    found = []
    depth = 0
    i = start
    while i < end:
        ch = source[i]
        if ch == '"':
            parsed = read_string_literal(source, i)
            if not parsed:
                i += 1
                continue
            if depth == 0:
                found.append((i, parsed[1]))
            i = parsed[0]
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        i += 1
    return found


def first_argument_span(source, open_paren):
    """Span of the first argument of the call whose '(' is at open_paren."""
    depth = 0
    i = open_paren
    while i < len(source):
        ch = source[i]
        if ch == '"':
            parsed = read_string_literal(source, i)
            i = parsed[0] if parsed else i + 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return open_paren + 1, i
        elif ch == "," and depth == 1:
            return open_paren + 1, i
        i += 1
    return open_paren + 1, i


def line_of(source, index):
    return source.count("\n", 0, index) + 1


def scan(path, keys):
    source = path.read_text(encoding="utf-8")
    lines = source.split("\n")
    missing, suspicious = [], []
    localized_literals = set()

    def check_literal(index, pieces):
        localized_literals.add(index)
        key = key_of(pieces)
        if not is_translatable(key):
            return
        if normalize_key(key) not in keys:
            missing.append((line_of(source, index), key))

    for name in FIRST_ARGUMENT_CALLS:
        prefix = r"(?<![\w.])" if not name.startswith(".") else ""
        pattern = re.compile(prefix + re.escape(name) + r"\s*\(")
        for match in pattern.finditer(source):
            open_paren = match.end() - 1
            start, end = first_argument_span(source, open_paren)
            argument = source[start:end].strip()
            if re.match(r"(verbatim|systemName|item|selection|value)\s*:", argument):
                continue
            for index, pieces in top_level_literals(source, start, end):
                check_literal(index, pieces)

    for match in re.finditer(r"(?<![\w.])String\s*\(\s*localized\s*:\s*", source):
        start, end = first_argument_span(source, source.index("(", match.start()))
        for index, pieces in top_level_literals(source, match.end(), end):
            check_literal(index, pieces)

    for label in LABELLED_ARGUMENTS:
        for match in re.finditer(r"[(,]\s*" + label + r"\s*:\s*", source):
            value_start = match.end()
            depth = 0
            i = value_start
            while i < len(source):
                ch = source[i]
                if ch == '"':
                    parsed = read_string_literal(source, i)
                    i = parsed[0] if parsed else i + 1
                    continue
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                elif ch == "," and depth == 0:
                    break
                i += 1
            for index, pieces in top_level_literals(source, value_start, i):
                check_literal(index, pieces)

    # Suspicious raw strings: interpolated literals with words, outside localizable calls.
    i = 0
    while i < len(source):
        if source.startswith("//", i):
            i = source.find("\n", i)
            if i < 0:
                break
            continue
        if source[i] == '"':
            parsed = read_string_literal(source, i)
            if not parsed:
                i += 1
                continue
            end, pieces = parsed
            if i not in localized_literals and None in pieces:
                text = " ".join(piece for piece in pieces if piece)
                line_number = line_of(source, i)
                line = lines[line_number - 1]
                context = source[max(0, i - 60):i]
                exempt = (
                    "l10n-ignore" in line
                    or re.search(r"(accessibilityIdentifier|verbatim:|L10n\.\w+|systemName:|systemImage:|\.id|URL|print|Logger|uuidString|forKey|withName|appendingPathComponent)\s*\(?\s*$", context)
                    or re.search(r"String\(localized:\s*$", context)
                )
                if not exempt and "://" not in text and re.search(r"[^\W\d_]{3,}", text):
                    suspicious.append((line_number, key_of(pieces)))
            i = end
            continue
        i += 1
    return missing, suspicious


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target", default="ios", choices=list(TARGET_SOURCES) + ["all"])
    args = parser.parse_args()
    all_keys = json.loads((ROOT / "Localization/keys.json").read_text(encoding="utf-8"))
    targets = list(TARGET_SOURCES) if args.target == "all" else [args.target]
    failed = False
    for target in targets:
        keys = {normalize_key(key) for key in all_keys.get(target, [])}
        problems = 0
        for directory in TARGET_SOURCES[target]:
            for path in sorted((ROOT / directory).rglob("*.swift")):
                missing, suspicious = scan(path, keys)
                relative = path.relative_to(ROOT)
                for line, key in missing:
                    print(f"{relative}:{line}: not in keys.json[{target!r}]: {key!r}")
                for line, key in suspicious:
                    print(f"{relative}:{line}: interpolated text outside a localized call: {key!r} (wrap it in String(localized:) or mark // l10n-ignore)")
                problems += len(missing) + len(suspicious)
        print(f"{target}: {'OK' if problems == 0 else str(problems) + ' problems'}")
        failed |= problems > 0
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
