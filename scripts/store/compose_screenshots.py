#!/usr/bin/env python3
"""Compose the App Store marketing screenshots for PadelOS.

Input: raw simulator captures from the "Store screenshots" workflow
(`.github/workflows/store-screenshots.yml`), laid out as

    <raw>/iphone/<lang>/store-<screen>.png     1320x2868 (iPhone 6.9-inch)
    <raw>/watch/<lang>/watch-<screen>.png      422x514   (Apple Watch Ultra)

and the captions in `docs/app-store/metadata/<locale>.json` (`screenshotCaptions`).

Output: `docs/app-store/final/<locale>/iphone/01.png ...` (1320x2868) and
`docs/app-store/final/<locale>/watch/01.png ...` (422x514), sRGB, no alpha.

    pip install pillow
    gh run download <run-id> -n store-raw -D build/store-raw
    python scripts/store/compose_screenshots.py --raw build/store-raw

The Inter typeface (SIL Open Font License) is downloaded once into a cache folder at
run time; fonts are never committed.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[2]
METADATA = ROOT / "docs" / "app-store" / "metadata"
FINAL = ROOT / "docs" / "app-store" / "final"

# Brand (Apps/Shared/Theme.swift)
BACKGROUND = (16, 18, 16)        # #101210
SURFACE = (26, 29, 26)           # #1A1D1A
LIME = (199, 243, 107)           # #C7F36B
WHITE = (255, 255, 255)
SUBLINE = (166, 173, 165)

CANVAS = (1320, 2868)            # iPhone 6.9-inch portrait
WATCH_SIZE = (422, 514)          # Apple Watch Ultra 3 (49 mm)

INTER_URL = "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
FONT_FILES = {
    "black": "extras/ttf/InterDisplay-Black.ttf",
    "extrabold": "extras/ttf/InterDisplay-ExtraBold.ttf",
    "semibold": "extras/ttf/InterDisplay-SemiBold.ttf",
    "medium": "extras/ttf/InterDisplay-Medium.ttf",
}

# App Store locale -> language of the raw captures.
LOCALE_LANGUAGE = {
    "en-US": "en", "en-GB": "en", "es-ES": "es", "es-MX": "es", "sv": "sv",
    "fr-FR": "fr", "de-DE": "de", "it": "it", "pt-BR": "pt-BR", "nl-NL": "nl",
}

# Caption id -> how the slide is built. "screens" are tried in order (first usable wins).
SLIDES = {
    "01-dashboard": {"screens": ["store-live"]},
    "02-watch": {"screens": ["store-scoring"], "watch": "watch-scoring"},
    "03-schedule": {"screens": ["store-schedule"]},
    "04-shared": {"screens": ["store-invite"]},
    "05-live-activity": {"screens": ["store-lock-wake", "store-lock", "store-island-expanded", "store-island"], "lock": True},
    "06-playoffs": {"screens": ["store-playoffs", "store-standings"]},
    "07-formats": {"screens": ["store-create"], "chips": True},
}
WATCH_SLIDES = {"w01-scoring": "watch-scoring", "w02-home": "watch-home", "w03-standings": "watch-standings"}


# MARK: - Fonts

def font_dir(cache: Path) -> Path:
    target = cache / "inter-4.1"
    if all((target / Path(f).name).exists() for f in FONT_FILES.values()):
        return target
    target.mkdir(parents=True, exist_ok=True)
    print(f"Downloading Inter (OFL) to {target} ...")
    with urllib.request.urlopen(INTER_URL, timeout=60) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    for member in FONT_FILES.values():
        (target / Path(member).name).write_bytes(archive.read(member))
    return target


class Fonts:
    def __init__(self, directory: Path):
        self.directory = directory

    def get(self, weight: str, size: int) -> ImageFont.FreeTypeFont:
        return ImageFont.truetype(str(self.directory / Path(FONT_FILES[weight]).name), size)


# MARK: - Drawing helpers

def rounded_mask(size, radius, scale=4):
    """Anti-aliased rounded-rectangle mask."""
    w, h = size
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def radial_glow(size, center, radius, color, strength):
    """Soft radial glow as an RGBA layer."""
    w, h = size
    small = (max(1, w // 8), max(1, h // 8))
    layer = Image.new("L", small, 0)
    d = ImageDraw.Draw(layer)
    cx, cy, r = center[0] / 8, center[1] / 8, radius / 8
    steps = 60
    for i in range(steps, 0, -1):
        t = i / steps
        a = int(255 * strength * (1 - t) ** 2.2)
        d.ellipse((cx - r * t, cy - r * t, cx + r * t, cy + r * t), fill=a)
    layer = layer.filter(ImageFilter.GaussianBlur(4)).resize(size, Image.BICUBIC)
    rgba = Image.new("RGBA", size, color + (0,))
    rgba.putalpha(layer)
    return rgba


def background(size, glow_center):
    w, h = size
    base = Image.new("RGB", size, BACKGROUND)
    # Vertical depth: slightly lighter at the top.
    grad = Image.linear_gradient("L").resize((w, h))
    top = Image.new("RGB", size, (24, 27, 24))
    base = Image.composite(base, top, grad)
    base = base.convert("RGBA")
    base.alpha_composite(radial_glow(size, glow_center, w * 0.95, LIME, 0.22))
    base.alpha_composite(radial_glow(size, (w * 0.5, -h * 0.05), w * 0.9, (60, 70, 55), 0.35))
    court_lines(base)
    return base


def court_lines(img):
    """A faint padel court outline in perspective behind everything: brand texture."""
    w, h = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    color = LIME + (16,)
    # Trapezoid court seen from the baseline.
    top_y, bottom_y = h * 0.50, h * 1.04
    top_half, bottom_half = w * 0.36, w * 0.78
    cx = w / 2
    lw = 5
    pts = [(cx - top_half, top_y), (cx + top_half, top_y), (cx + bottom_half, bottom_y), (cx - bottom_half, bottom_y)]
    d.line(pts + [pts[0]], fill=color, width=lw, joint="curve")

    def lerp_y(t):
        y = top_y + (bottom_y - top_y) * t
        half = top_half + (bottom_half - top_half) * t
        return y, half

    for t in (0.18, 0.82):  # service lines
        y, half = lerp_y(t)
        d.line([(cx - half, y), (cx + half, y)], fill=color, width=lw)
    y, half = lerp_y(0.5)  # net
    d.line([(cx - half, y), (cx + half, y)], fill=LIME + (30,), width=lw + 2)
    y1, _ = lerp_y(0.18)
    y2, _ = lerp_y(0.82)
    d.line([(cx, y1), (cx, y2)], fill=color, width=lw)
    img.alpha_composite(layer)


def drop_shadow(canvas, box, radius, blur, opacity, offset=(0, 40), color=(0, 0, 0)):
    x0, y0, x1, y1 = box
    pad = blur * 3
    w, h = int(x1 - x0) + 2 * pad, int(y1 - y0) + 2 * pad
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((pad, pad, w - pad, h - pad), radius, fill=int(255 * opacity))
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    layer = Image.new("RGBA", (w, h), color + (0,))
    layer.putalpha(mask)
    canvas.alpha_composite(layer, (int(x0 - pad + offset[0]), int(y0 - pad + offset[1])))


# MARK: - Devices

def iphone(screen: Image.Image, width: int) -> Image.Image:
    """A modern iPhone (titanium band, thin black bezel, Dynamic Island) around a capture."""
    sw, sh = screen.size
    bezel = round(width * 0.028)
    band = round(width * 0.012)
    inner_w = width - 2 * (bezel + band)
    scale = inner_w / sw
    inner_h = round(sh * scale)
    height = inner_h + 2 * (bezel + band)
    outer_r = round(width * 0.165)
    screen_r = outer_r - bezel - band

    phone = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # Titanium band with a vertical sheen.
    band_img = Image.new("RGBA", (width, height))
    sheen = Image.linear_gradient("L").rotate(90, expand=True).resize((width, height))
    dark = Image.new("RGBA", (width, height), (58, 62, 58, 255))
    light = Image.new("RGBA", (width, height), (120, 126, 118, 255))
    band_img = Image.composite(light, dark, sheen.point(lambda v: int(80 + 175 * abs(math.sin(v / 255 * math.pi)))))
    phone.paste(band_img, (0, 0), rounded_mask((width, height), outer_r))
    # Black glass.
    glass = Image.new("RGBA", (width - 2 * band, height - 2 * band), (6, 7, 6, 255))
    phone.paste(glass, (band, band), rounded_mask(glass.size, outer_r - band))
    # Screen.
    shot = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    phone.paste(shot, (band + bezel, band + bezel), rounded_mask((inner_w, inner_h), screen_r))
    # Dynamic Island (440 pt wide screen: 126 x 37 pt, 11 pt from the top).
    pt = inner_w / 440
    iw, ih, top = 124 * pt, 36.5 * pt, 11 * pt
    ix0 = band + bezel + (inner_w - iw) / 2
    iy0 = band + bezel + top
    island = Image.new("RGBA", (round(iw), round(ih)), (0, 0, 0, 255))
    phone.paste(island, (round(ix0), round(iy0)), rounded_mask(island.size, round(ih / 2)))
    # Edge highlight.
    edge = ImageDraw.Draw(phone)
    edge.rounded_rectangle((1, 1, width - 2, height - 2), outer_r, outline=(170, 176, 168, 120), width=2)
    return phone


def side_buttons(canvas, box, width):
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(canvas)
    color = (78, 83, 77, 255)
    bw = max(4, round(width * 0.008))
    h = y1 - y0
    for top, length in ((0.17, 0.045), (0.245, 0.085), (0.345, 0.085)):  # action, volume
        d.rounded_rectangle((x0 - bw, y0 + h * top, x0 + 2, y0 + h * (top + length)), bw, fill=color)
    d.rounded_rectangle((x1 - 2, y0 + h * 0.27, x1 + bw, y0 + h * 0.39), bw, fill=color)  # side
    d.rounded_rectangle((x1 - 2, y0 + h * 0.56, x1 + bw, y0 + h * 0.62), bw, fill=color)  # camera control


def watch(screen: Image.Image, width: int) -> Image.Image:
    """Apple Watch Ultra-style case around a 422x514 capture."""
    sw, sh = screen.size
    margin = round(width * 0.075)
    inner_w = width - 2 * margin
    inner_h = round(sh * inner_w / sw)
    height = inner_h + 2 * margin
    case_r = round(width * 0.2)
    extra = round(width * 0.09)  # room for crown and action button
    img = Image.new("RGBA", (width + 2 * extra, height + 2 * extra), (0, 0, 0, 0))
    ox, oy = extra, extra
    d = ImageDraw.Draw(img)
    # Crown and side button (right), action button (left, International Orange).
    cw = round(width * 0.07)
    d.rounded_rectangle((ox + width - 6, oy + height * 0.26, ox + width + cw, oy + height * 0.43), cw // 3, fill=(92, 97, 90, 255))
    d.rounded_rectangle((ox + width - 6, oy + height * 0.55, ox + width + cw * 0.6, oy + height * 0.72), cw // 4, fill=(70, 74, 69, 255))
    d.rounded_rectangle((ox - cw * 0.6, oy + height * 0.30, ox + 6, oy + height * 0.50), cw // 4, fill=(255, 95, 31, 255))
    # Case.
    sheen = Image.linear_gradient("L").resize((width, height))
    case = Image.composite(Image.new("RGBA", (width, height), (52, 56, 51, 255)),
                           Image.new("RGBA", (width, height), (104, 110, 102, 255)), sheen)
    img.paste(case, (ox, oy), rounded_mask((width, height), case_r))
    bezel = Image.new("RGBA", (width - margin, height - margin), (4, 4, 4, 255))
    img.paste(bezel, (ox + margin // 2, oy + margin // 2), rounded_mask(bezel.size, case_r - margin // 2))
    shot = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    img.paste(shot, (ox + margin, oy + margin), rounded_mask((inner_w, inner_h), round(case_r * 0.62)))
    d.rounded_rectangle((ox + 1, oy + 1, ox + width - 2, oy + height - 2), case_r, outline=(185, 190, 182, 110), width=2)
    return img


# MARK: - Text

def wrap_lines(headline: str):
    return [line.strip() for line in headline.split("\n") if line.strip()]


def draw_headline(canvas, fonts, headline, highlight, top, max_width, size):
    lines = wrap_lines(headline)
    font = fonts.get("black", size)
    while size > 70 and max(font.getlength(line) for line in lines) > max_width:
        size -= 4
        font = fonts.get("black", size)
    d = ImageDraw.Draw(canvas)
    line_h = round(size * 1.06)
    w = canvas.size[0]
    y = top
    for line in lines:
        total = font.getlength(line)
        x = (w - total) / 2
        segments = [(line, WHITE)]
        if highlight and highlight in line:
            i = line.index(highlight)
            segments = [(line[:i], WHITE), (highlight, LIME), (line[i + len(highlight):], WHITE)]
        for text, color in segments:
            if text:
                d.text((x, y), text, font=font, fill=color)
                x += font.getlength(text)
        y += line_h
    return y, size


def draw_subline(canvas, fonts, text, top, max_width, size=54):
    d = ImageDraw.Draw(canvas)
    words = text.split()
    # One line if it fits (shrinking a little), else two balanced lines.
    font = fonts.get("medium", size)
    while size > 46 and font.getlength(text) > max_width:
        size -= 2
        font = fonts.get("medium", size)
    if font.getlength(text) <= max_width:
        lines = [text]
    else:
        size = 54
        font = fonts.get("medium", size)
        best = None
        for i in range(1, len(words)):
            a, b = " ".join(words[:i]), " ".join(words[i:])
            widest = max(font.getlength(a), font.getlength(b))
            if best is None or widest < best[0]:
                best = (widest, [a, b])
        lines = best[1] if best else [text]
    y = top
    for line in lines[:2]:
        x = (canvas.size[0] - font.getlength(line)) / 2
        d.text((x, y), line, font=font, fill=SUBLINE)
        y += round(size * 1.3)
    return y


def chip(fonts, text, size=40):
    font = fonts.get("semibold", size)
    tw = font.getlength(text)
    pad_x, h = round(size * 0.75), round(size * 2.0)
    w = round(tw + 2 * pad_x)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=(32, 36, 32, 235), outline=LIME + (150,), width=3)
    d.text((pad_x, (h - size * 1.2) / 2), text, font=font, fill=WHITE)
    return img


# MARK: - Raw captures

def usable(path: Path) -> bool:
    """False for missing or (nearly) black captures, e.g. a Lock Screen with the display off."""
    if not path.exists():
        return False
    img = Image.open(path).convert("L").resize((66, 143))
    return ImageStat.Stat(img).mean[0] > 6


def find_raw(raw: Path, kind: str, lang: str, names) -> Path | None:
    for language in (lang, "en"):
        for name in names:
            path = raw / kind / language / f"{name}.png"
            if usable(path):
                if language != lang:
                    print(f"  ! {kind}/{lang}/{name}.png missing, using {language}")
                return path
    return None


# MARK: - Slides

def compose_iphone(fonts, caption, raw, lang, extras) -> Image.Image | None:
    spec = SLIDES.get(caption["id"])
    if not spec:
        print(f"  ! unknown caption id {caption['id']}")
        return None
    screen_path = find_raw(raw, "iphone", lang, spec["screens"])
    if not screen_path:
        print(f"  ! no capture for {caption['id']} ({lang})")
        return None
    W, H = CANVAS
    phone_w = 1040
    canvas = background(CANVAS, (W / 2, 1700))

    # Text block; the phone starts right below it and bleeds off the bottom edge.
    bottom, _ = draw_headline(canvas, fonts, caption["headline"], caption.get("highlight"), 200, W - 150, 150)
    bottom = draw_subline(canvas, fonts, caption.get("subline", ""), bottom + 30, W - 200)
    phone_top = max(760, int(bottom + 95))

    screen = Image.open(screen_path)
    phone = iphone(screen, phone_w)
    px = (W - phone_w) // 2
    box = (px, phone_top, px + phone_w, phone_top + phone.size[1])
    canvas.alpha_composite(radial_glow(CANVAS, (W / 2, phone_top + 260), 620, LIME, 0.20))
    drop_shadow(canvas, box, 160, 60, 0.75, offset=(0, 50))
    side_buttons(canvas, box, phone_w)
    canvas.alpha_composite(phone, (px, phone_top))

    if spec.get("watch"):
        watch_path = find_raw(raw, "watch", lang, [spec["watch"]])
        if watch_path:
            device = watch(Image.open(watch_path), 470)
            wx = W - device.size[0] + 20
            wy = phone_top + 1080
            drop_shadow(canvas, (wx + 40, wy + 40, wx + device.size[0] - 40, wy + device.size[1] - 40), 100, 50, 0.85, offset=(0, 30))
            canvas.alpha_composite(device, (wx, wy))
    if spec.get("chips"):
        names = extras.get("formats") or []
        positions = [(-30, 0.30, "l"), (W + 30, 0.40, "r"), (-30, 0.52, "l"), (W + 30, 0.63, "r")]
        for name, (x, rel, side) in zip(names, positions):
            c = chip(fonts, name, 44)
            cy = int(phone_top + rel * (H - phone_top))
            cx = 40 if side == "l" else W - c.size[0] - 40
            drop_shadow(canvas, (cx, cy, cx + c.size[0], cy + c.size[1]), c.size[1] // 2, 24, 0.7, offset=(0, 14))
            canvas.alpha_composite(c, (cx, cy))
    return canvas.convert("RGB")


def compose_watch(raw, lang, screen) -> Image.Image | None:
    path = find_raw(raw, "watch", lang, [screen])
    if not path:
        return None
    img = Image.open(path).convert("RGB")
    if img.size != WATCH_SIZE:
        img = img.resize(WATCH_SIZE, Image.LANCZOS)
    return img


def save_png(img: Image.Image, path: Path, size):
    assert img.size == size, (path, img.size)
    assert img.mode == "RGB"
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)


def contact_sheet(paths, out: Path, scale=0.25):
    thumbs = [Image.open(p).convert("RGB") for p in paths]
    if not thumbs:
        return
    tw, th = int(thumbs[0].size[0] * scale), int(thumbs[0].size[1] * scale)
    sheet = Image.new("RGB", (len(thumbs) * (tw + 16) + 16, th + 32), (240, 240, 240))
    for i, t in enumerate(thumbs):
        sheet.paste(t.resize((tw, th), Image.LANCZOS), (16 + i * (tw + 16), 16))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw", default=str(ROOT / "build" / "store-raw"), help="folder with iphone/<lang>/ and watch/<lang>/ captures")
    parser.add_argument("--out", default=str(FINAL))
    parser.add_argument("--locales", nargs="*", help="App Store locales (default: every metadata file)")
    parser.add_argument("--only", nargs="*", help="caption ids to render, e.g. 01-dashboard")
    parser.add_argument("--fonts-cache", default=os.environ.get("PADELOS_FONT_CACHE", str(Path.home() / ".cache" / "padelos-store-fonts")))
    parser.add_argument("--preview", default=str(ROOT / "build" / "store-preview"), help="contact sheets at 25%% for review")
    args = parser.parse_args(argv)

    raw, out = Path(args.raw), Path(args.out)
    fonts = Fonts(font_dir(Path(args.fonts_cache)))
    locales = args.locales or sorted(p.stem for p in METADATA.glob("*.json"))
    if not locales:
        sys.exit("No metadata in docs/app-store/metadata")
    for locale in locales:
        meta = json.loads((METADATA / f"{locale}.json").read_text(encoding="utf-8"))
        lang = LOCALE_LANGUAGE.get(locale, locale.split("-")[0])
        if not (raw / "iphone" / lang).exists():
            print(f"{locale}: no {lang} captures, using en")
        print(f"{locale} ({lang})")
        extras = {"formats": meta.get("formatChips") or []}
        written = []
        captions = meta["screenshotCaptions"]
        for index, caption in enumerate(captions, start=1):
            if args.only and caption["id"] not in args.only:
                continue
            img = compose_iphone(fonts, caption, raw, lang, extras)
            if img is None:
                continue
            path = out / locale / "iphone" / f"{index:02d}.png"
            save_png(img, path, CANVAS)
            written.append(path)
        for index, caption in enumerate(meta.get("watchCaptions", []), start=1):
            if args.only and caption["id"] not in args.only:
                continue
            img = compose_watch(raw, lang, WATCH_SLIDES.get(caption["id"], ""))
            if img is None:
                print(f"  ! no watch capture for {caption['id']}")
                continue
            path = out / locale / "watch" / f"{index:02d}.png"
            save_png(img, path, WATCH_SIZE)
        if written and args.preview:
            contact_sheet(written, Path(args.preview) / f"{locale}.png")
        print(f"  {len(written)} iPhone screenshots -> {out / locale}")


if __name__ == "__main__":
    main()
