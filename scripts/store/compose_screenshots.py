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
    "dashboard": {"screens": ["store-live"]},
    "watch": {"screens": ["store-scoring"], "watch": "watch-scoring"},
    "schedule": {"screens": ["store-schedule"]},
    "shared": {"screens": ["store-invite"]},
    "live-activity": {"screens": ["store-lock-wake", "store-lock-clean", "store-lock", "store-island-expanded"], "lock": True},
    # The public spectator page on a TV, the phone sharing its link in front.
    "leaderboard": {"screens": ["store-leaderboard"], "tv": "live-board"},
    "playoffs": {"screens": ["store-playoffs", "store-standings"]},
    "stats": {"screens": ["store-player", "store-players"]},
    "formats": {"screens": ["store-create"]},
}
WATCH_SLIDES = {"scoring": ["watch-scoring"], "home": ["watch-home"], "standings": ["watch-standings"]}


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


def television(screen: Image.Image, width: int) -> Image.Image:
    """A slim flat-screen TV on a stand around a 16:9 web capture."""
    bezel = max(8, round(width * 0.012))
    inner_w = width - 2 * bezel
    inner_h = round(screen.size[1] * inner_w / screen.size[0])
    panel_h = inner_h + 2 * bezel
    stand_h = round(width * 0.07)
    img = Image.new("RGBA", (width, panel_h + stand_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Stand: neck and a flat foot.
    cx = width // 2
    neck_w = round(width * 0.05)
    d.rectangle((cx - neck_w // 2, panel_h - 4, cx + neck_w // 2, panel_h + stand_h - 18), fill=(46, 49, 45, 255))
    d.rounded_rectangle((cx - round(width * 0.17), panel_h + stand_h - 22, cx + round(width * 0.17), panel_h + stand_h - 6), 8, fill=(58, 62, 57, 255))
    # Panel.
    panel = Image.new("RGBA", (width, panel_h), (10, 11, 10, 255))
    img.paste(panel, (0, 0), rounded_mask((width, panel_h), 18))
    shot = screen.convert("RGB").resize((inner_w, inner_h), Image.LANCZOS)
    img.paste(shot, (bezel, bezel), rounded_mask((inner_w, inner_h), 6))
    d.rounded_rectangle((1, 1, width - 2, panel_h - 2), 18, outline=(120, 126, 118, 150), width=2)
    return img


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


def live_activity_card(screen: Image.Image) -> Image.Image | None:
    """Crops the Live Activity from a Lock Screen capture, found by its lime elements:
    from the first lime row (header) to the end of the lime +1 button, plus padding.
    Anything below the button (system prompts, notifications) is left out."""
    img = screen.convert("RGB")
    w, h = img.size
    small = img.resize((w // 4, h // 4), Image.NEAREST)
    sw, sh = small.size
    px = small.load()

    def lime(c):
        return abs(c[0] - LIME[0]) < 30 and abs(c[1] - LIME[1]) < 30 and abs(c[2] - LIME[2]) < 40

    rows = []
    for y in range(sh // 3, sh - sh // 10):
        count = sum(1 for x in range(sw) if lime(px[x, y]))
        rows.append((y, count))
    hits = [(y, c) for y, c in rows if c > 3]
    if not hits:
        return None
    # Group into runs; keep runs up to the last one containing the filled +1 button.
    runs, current = [], [hits[0]]
    for item in hits[1:]:
        if item[0] - current[-1][0] > 5:  # 20 px gap at full size
            runs.append(current)
            current = [item]
        else:
            current.append(item)
    runs.append(current)
    # The +1 button is the run with the most lime (the progress bar is wide but thin).
    wide = [run for run in runs if max(c for _, c in run) > sw * 0.25]
    if not wide:
        return None
    last_run = max(wide, key=lambda run: sum(c for _, c in run))
    first = runs[0][0][0]
    # Crop inside the activity (no wallpaper corners), then pad it with its own
    # background so the zoomed card gets clean rounded corners.
    top, bottom = first * 4 - 8, last_run[-1][0] * 4 + 10
    left, right = 64, w - 64
    if top < 0 or bottom > h or bottom - top < 200:
        return None
    inner = img.crop((left, top, right, bottom))
    fill = inner.getpixel((4, inner.size[1] // 2))
    # Wallpaper showing through the activity's rounded corners (blue/teal) and a black
    # system prompt below it become card background.
    ipx = inner.load()
    for y in range(inner.size[1]):
        for x in range(inner.size[0]):
            r, g, b = ipx[x, y]
            # Also the activity's own hairline edge: the top rows above the header text
            # and the outermost columns.
            if b - r > 25 or (r + g + b) < 12 or y < 5 or y >= inner.size[1] - 6 or x < 22 or x >= inner.size[0] - 22:
                ipx[x, y] = fill
    pad = 34
    card = Image.new("RGB", (inner.size[0] + 2 * pad, inner.size[1] + 2 * pad), fill)
    card.paste(inner, (pad, pad))
    return card, (left - pad, top - pad, right + pad, bottom + pad)


def hide_below_activity(screen: Image.Image, box) -> Image.Image:
    """Removes a system prompt attached below the Live Activity ("Allow Live Activities
    from …?" on a fresh simulator) by extending the wallpaper just below it upwards."""
    img = screen.copy()
    left, _, right, bottom = box
    left, right = max(0, left - 4), min(img.size[0], right + 4)
    px = img.load()
    height = img.size[1]

    def black_share(y):  # the prompt is pure black (with lime text), the wallpaper is not
        columns = range(left, right, 4)
        return sum(1 for x in columns if max(px[x, y]) < 10) / len(columns)

    if black_share(bottom + 2) < 0.5:
        return img  # nothing attached below the activity
    end = bottom
    while end < min(height - 41, bottom + 800) and black_share(end) >= 0.3:
        end += 1
    sample = end + 16  # wallpaper just below the prompt (incl. its rounded corners)
    for x in range(left, right):
        color = px[x, sample]
        for y in range(bottom - 30, sample):
            px[x, y] = color
    return img


# MARK: - Slides

def compose_iphone(fonts, caption, raw, lang) -> Image.Image | None:
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

    if spec.get("tv"):
        board = find_raw(raw, "web", lang, [spec["tv"]])
        if board:
            tv = television(Image.open(board), W - 90)
            tx, ty = 45, int(bottom + 90)
            canvas.alpha_composite(radial_glow(CANVAS, (W / 2, ty + tv.size[1] / 2), 760, LIME, 0.22))
            drop_shadow(canvas, (tx, ty, tx + tv.size[0], ty + tv.size[1] - 60), 24, 50, 0.8, offset=(0, 30))
            canvas.alpha_composite(tv, (tx, ty))
            # A smaller phone in front, overlapping the bottom of the TV.
            phone_w = 840
            phone_top = ty + tv.size[1] - 120
        else:
            print(f"  ! no web capture for {caption['id']} ({lang}); phone only")

    screen = Image.open(screen_path).convert("RGB")
    found = live_activity_card(screen) if spec.get("lock") else None
    if found is not None:
        screen = hide_below_activity(screen, found[1])
    phone = iphone(screen, phone_w)
    px = (W - phone_w) // 2
    if spec.get("watch"):
        # Phone to the left, the watch in front of its lower right corner (below the score).
        px = 40
    box = (px, phone_top, px + phone_w, phone_top + phone.size[1])
    canvas.alpha_composite(radial_glow(CANVAS, (W / 2, phone_top + 260), 620, LIME, 0.20))
    drop_shadow(canvas, box, 160, 60, 0.75, offset=(0, 50))
    side_buttons(canvas, box, phone_w)
    canvas.alpha_composite(phone, (px, phone_top))

    if spec.get("lock"):
        if found is not None:
            card, (_, top, _, bottom) = found
            # Zoomed copy centred on the activity inside the phone.
            inset = round(phone_w * 0.012) + round(phone_w * 0.028)
            scale = (phone_w - 2 * inset) / screen.size[0]
            centre = phone_top + inset + (top + bottom) / 2 * scale
            cw = W - 120
            card = card.resize((cw, round(card.size[1] * cw / card.size[0])), Image.LANCZOS)
            framed = Image.new("RGBA", card.size, (0, 0, 0, 0))
            framed.paste(card, (0, 0), rounded_mask(card.size, 64))
            ImageDraw.Draw(framed).rounded_rectangle((1, 1, card.size[0] - 2, card.size[1] - 2), 64, outline=LIME + (140,), width=3)
            cx, cy = 60, int(centre - card.size[1] / 2)
            drop_shadow(canvas, (cx, cy, cx + cw, cy + card.size[1]), 64, 50, 0.9, offset=(0, 36))
            canvas.alpha_composite(framed, (cx, cy))
    if spec.get("watch"):
        watch_path = find_raw(raw, "watch", lang, [spec["watch"]])
        if watch_path:
            device = watch(Image.open(watch_path), 500)
            wx = W - device.size[0] + 24
            wy = phone_top + int(phone.size[1] * 0.56)
            drop_shadow(canvas, (wx + 40, wy + 40, wx + device.size[0] - 40, wy + device.size[1] - 40), 100, 50, 0.85, offset=(0, 30))
            canvas.alpha_composite(device, (wx, wy))
    return canvas.convert("RGB")


def compose_watch(raw, lang, screens) -> Image.Image | None:
    path = find_raw(raw, "watch", lang, screens)
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
    parser.add_argument("--only", nargs="*", help="caption ids to render, e.g. dashboard")
    parser.add_argument("--fonts-cache", default=os.environ.get("PADELOS_FONT_CACHE", str(Path.home() / ".cache" / "padelos-store-fonts")))
    parser.add_argument("--preview", default=str(ROOT / "build" / "store-preview"), help="contact sheets at 25%% for review")
    args = parser.parse_args(argv)

    raw, out = Path(args.raw), Path(args.out)
    fonts = Fonts(font_dir(Path(args.fonts_cache)))
    # By default every locale whose language was captured (others would show English UI).
    locales = args.locales or sorted(
        p.stem for p in METADATA.glob("*.json")
        if (raw / "iphone" / LOCALE_LANGUAGE.get(p.stem, p.stem.split("-")[0])).exists()
    )
    if not locales:
        sys.exit(f"No captures in {raw} for any locale in docs/app-store/metadata")
    for locale in locales:
        meta = json.loads((METADATA / f"{locale}.json").read_text(encoding="utf-8"))
        lang = LOCALE_LANGUAGE.get(locale, locale.split("-")[0])
        if not (raw / "iphone" / lang).exists():
            print(f"{locale}: no {lang} captures, using en")
        print(f"{locale} ({lang})")
        written = []
        captions = meta["screenshotCaptions"]
        for index, caption in enumerate(captions, start=1):
            if args.only and caption["id"] not in args.only:
                continue
            img = compose_iphone(fonts, caption, raw, lang)
            if img is None:
                continue
            path = out / locale / "iphone" / f"{index:02d}.png"
            save_png(img, path, CANVAS)
            written.append(path)
        for index, caption in enumerate(meta.get("watchCaptions", []), start=1):
            if args.only and caption["id"] not in args.only:
                continue
            img = compose_watch(raw, lang, WATCH_SLIDES.get(caption["id"], []))
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
