#!/usr/bin/python3
"""palette.py — the accent colour a wallpaper asks for (Material-You style), for `glass-mode theme wallpaper`.

    palette.py IMAGE            -> the accent as #rrggbb (tuned for the shell: OKLCH lightness 0.62)
    palette.py --json IMAGE     -> {accent, accentLight, hue, chroma, source, swatches: [{hex, population, chroma}, …]}

The SAME algorithm lives in the shell (sirca-shell/src/palette.cpp): the shell shows the colour at once, this script
derives it for everything else (Qt / GTK / Spotify / folders). Both must give the same answer, so every step below is
deterministic and integer where it can be (no k-means, no library resampling):
  1. box-average the picture down to <= 128 px on its long side (integer factor, remainder dropped; integer rounding)
  2. median cut to 16 boxes: split the box with the widest channel range (ties: the lower box index, then r,g,b) at
     the median of that channel, stable sort by that one channel
  3. score every box by chroma^2 x population in OKLab (chroma squared: a wallpaper is mostly background, and a plain
     chroma x population let a big near-black area beat the actual bloom); boxes under chroma 0.03 or 0.2 % of the
     picture are grey or a splash and never win
  4. the hue is the population-weighted mean over every coloured box within 30 degrees of the winner (one box is a
     slice of a gradient; the family of boxes is the colour), the source chroma is the strongest one in that family
  5. accent = that hue, chroma = source + 0.06 clamped into 0.10..0.20 (an accent sits on small controls, which need
     more saturation than a wallpaper area to read as coloured at all), lightness 0.62 (0.50 for the light variant),
     pulled back into sRGB by lowering chroma. The seven hand-picked Bloom accents sit at L 0.57-0.73, C 0.10-0.19,
     so a derived accent lands in the same family.
Needs Pillow and numpy under /usr/bin/python3 (Ubuntu ships both).
"""
import json
import math
import sys

import numpy as np
from PIL import Image

TARGET = 128
BOXES = 16
MIN_CHROMA = 0.03
MIN_POPULATION = 0.002
HUE_FAMILY = math.radians(30)
CHROMA_LIFT = 0.06
CHROMA_LO, CHROMA_HI = 0.10, 0.20
L_DARK, L_LIGHT = 0.62, 0.50


# ---- colour maths (Björn Ottosson's OKLab, https://bottosson.github.io/posts/oklab/) --------------------------------
def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def rgb_to_oklab(r, g, b):
    r, g, b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = math.cbrt(l), math.cbrt(m), math.cbrt(s)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def oklab_to_linear(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def oklch_to_rgb(L, C, h):
    """sRGB 0..1, or None when the colour is outside the gamut."""
    a, b = C * math.cos(h), C * math.sin(h)
    lin = oklab_to_linear(L, a, b)
    if any(v < -0.0005 or v > 1.0005 for v in lin):
        return None
    return tuple(linear_to_srgb(min(1.0, max(0.0, v))) for v in lin)


def oklch_to_hex(L, C, h):
    # out of gamut: pull the chroma in until it fits (the hue and the lightness are what the eye keeps)
    while C > 0.0:
        rgb = oklch_to_rgb(L, C, h)
        if rgb is not None:
            return "#%02x%02x%02x" % tuple(int(math.floor(v * 255 + 0.5)) for v in rgb)
        C = max(0.0, C - 0.005)
    rgb = oklch_to_rgb(L, 0.0, h) or (L, L, L)
    return "#%02x%02x%02x" % tuple(int(math.floor(v * 255 + 0.5)) for v in rgb)


# ---- the picture -> a handful of colours ----------------------------------------------------------------------------
def downscale(im):
    """Box average with an integer factor: the C++ side does the exact same sums."""
    w, h = im.size
    f = max(1, -(-max(w, h) // TARGET))          # ceil
    ow, oh = w // f, h // f
    a = np.asarray(im.convert("RGB"), dtype=np.int64)[: oh * f, : ow * f, :]
    s = a.reshape(oh, f, ow, f, 3).sum(axis=(1, 3))
    n = f * f
    return ((s * 2 + n) // (2 * n)).reshape(-1, 3).astype(np.int64)   # round half up, integer


def median_cut(px, count=BOXES):
    boxes = [np.arange(len(px))]
    while len(boxes) < count:
        best, best_range = -1, 0
        for i, idx in enumerate(boxes):
            if len(idx) < 2:
                continue
            rng = int((px[idx].max(axis=0) - px[idx].min(axis=0)).max())
            if rng > best_range:                   # strictly greater: ties keep the lower index
                best, best_range = i, rng
        if best < 0:
            break
        idx = boxes[best]
        ranges = px[idx].max(axis=0) - px[idx].min(axis=0)
        ch = int(np.argmax(ranges))                # first maximum: r before g before b
        order = idx[np.argsort(px[idx, ch], kind="stable")]
        half = len(order) // 2
        boxes[best:best + 1] = [order[:half], order[half:]]
    return boxes


def swatches(px, boxes):
    total = len(px)
    out = []
    for idx in boxes:
        mean = px[idx].sum(axis=0) / len(idx)     # float mean of the box, 0..255
        L, a, b = rgb_to_oklab(mean[0] / 255, mean[1] / 255, mean[2] / 255)
        out.append({"hex": "#%02x%02x%02x" % tuple(int(math.floor(v + 0.5)) for v in mean),
                    "population": len(idx) / total, "L": L, "a": a, "b": b, "chroma": math.hypot(a, b),
                    "hue": math.atan2(b, a)})
    return out


def hue_distance(h1, h2):
    d = abs(h1 - h2) % (2 * math.pi)
    return min(d, 2 * math.pi - d)


def pick(sw):
    """(hue, source chroma, the winning swatch) from the swatch list; the tie rule (first strict maximum) is the C++ one."""
    coloured = [s for s in sw if s["chroma"] >= MIN_CHROMA]
    cand = [s for s in coloured if s["population"] >= MIN_POPULATION]
    if not cand:                                   # a grey picture: the most common shade, and (nearly) no colour at all
        win = max(sw, key=lambda s: s["population"])
        return win["hue"], 0.0, win
    win = cand[0]
    for s in cand[1:]:
        if s["chroma"] ** 2 * s["population"] > win["chroma"] ** 2 * win["population"]:
            win = s
    family = [s for s in coloured if hue_distance(s["hue"], win["hue"]) <= HUE_FAMILY]
    a = sum(s["population"] * s["a"] for s in family)
    b = sum(s["population"] * s["b"] for s in family)
    hue = math.atan2(b, a) if (a != 0.0 or b != 0.0) else win["hue"]
    csrc = max(s["chroma"] for s in family if s["population"] >= MIN_POPULATION)
    return hue, csrc, win


def accent_lightness(hue):
    # yellows at L 0.62 are olive / mustard (the eye wants yellow light): up to +0.10 around hue 90, nothing by 0 / 180
    y = max(0.0, math.cos(hue - math.radians(90)))
    return L_DARK + 0.10 * y * y


def analyse(path):
    im = Image.open(path)
    px = downscale(im)
    sw = swatches(px, median_cut(px))
    hue, csrc, win = pick(sw)
    C = 0.02 if csrc == 0.0 else min(CHROMA_HI, max(CHROMA_LO, csrc + CHROMA_LIFT))
    L = accent_lightness(hue)
    return {"accent": oklch_to_hex(L, C, hue), "accentLight": oklch_to_hex(L - (L_DARK - L_LIGHT), C, hue),
            "hue": round(math.degrees(hue) % 360, 1), "chroma": round(C, 4), "sourceChroma": round(csrc, 4), "source": win["hex"],
            "swatches": [{"hex": s["hex"], "population": round(s["population"], 4), "chroma": round(s["chroma"], 4)}
                         for s in sorted(sw, key=lambda s: -s["population"])]}


def main(argv):
    as_json = "--json" in argv
    files = [a for a in argv if not a.startswith("--")]
    if not files:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: palette.py [--json] IMAGE", file=sys.stderr)
        return 2
    r = analyse(files[0])
    print(json.dumps(r, indent=1) if as_json else r["accent"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
