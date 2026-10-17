#!/usr/bin/env python3
"""Render the public live leaderboard page (docs/live) offline for the App Store screenshots.

The page normally reads its board from CloudKit; it also accepts an injected fetcher
(`window.PADELOS_LIVE_FETCH`) for local previews. This script writes a preview copy of the
page that serves the given board JSON (written by the app in the screenshot run, see
`AppModel.seedStoreDemo`, `-demoScreen leaderboard`) and screenshots it with headless
Chrome at TV size.

    python scripts/store/render_live_board.py --board live-board.json --lang es --out board.png
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "live"
TOKEN = "q7Rk2PadelOSdemo9Xw4LmZt"
CHROME_CANDIDATES = [
    os.environ.get("CHROME", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome", "chromium", "chromium-browser",
]


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if candidate and (Path(candidate).exists() or shutil.which(candidate)):
            return candidate
    sys.exit("Chrome not found (set CHROME=/path/to/chrome)")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--board", required=True, help="board JSON (LiveBoardSnapshot.json())")
    parser.add_argument("--lang", default="en", help="page language (en, es, sv; others fall back to English)")
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", default="1920,1080")
    args = parser.parse_args(argv)

    board = json.loads(Path(args.board).read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as temp:
        site = Path(temp)
        for name in ("app.js", "style.css"):
            shutil.copy(PAGE / name, site / name)
        html = (PAGE / "index.html").read_text(encoding="utf-8")
        # No CloudKit: serve the board from memory and pin the language.
        html = "\n".join(line for line in html.splitlines() if "cloudkit.js" not in line)
        inject = (
            "<script>\n"
            f"Object.defineProperty(navigator, 'languages', {{ get: () => [{json.dumps(args.lang)}] }});\n"
            f"Object.defineProperty(navigator, 'language', {{ get: () => {json.dumps(args.lang)} }});\n"
            f"const BOARD = {json.dumps(board, ensure_ascii=False)};\n"
            "window.PADELOS_LIVE_FETCH = async () => ({ board: BOARD, updatedAt: Date.now() });\n"
            "</script>\n"
        )
        html = html.replace('<script src="app.js" defer></script>', inject + '<script src="app.js" defer></script>')
        (site / "index.html").write_text(html, encoding="utf-8")
        out = Path(args.out).resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        url = (site / "index.html").as_uri() + "#" + TOKEN
        command = [
            find_chrome(), "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
            "--force-device-scale-factor=1", f"--window-size={args.size}", f"--lang={args.lang}",
            "--virtual-time-budget=6000", f"--screenshot={out}", url,
        ]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
    if not out.exists():
        sys.exit(f"No screenshot written to {out}")
    print(out)


if __name__ == "__main__":
    main()
