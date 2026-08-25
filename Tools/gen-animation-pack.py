#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 chuahchengxi
"""
Generates Resources/pet-animation-pack.bin — the Desktop Pet animation pack.

The pack is a tiny metadata table (18 bytes per species, ~19 KB total) that
lets the app composite eyelid overlays onto the cached PokeAPI sprite:
blinking while awake, closed lids while asleep, plus a per-species walk-gait
class derived from the sprite's proportions. No pixels ship in the pack;
sprites themselves stay on-demand downloads exactly as before.

Pipeline per National Dex id (1..1025):
  1. Fetch the gen-V animated GIF (first frame); fall back to the static PNG.
  2. Find the sprite's alpha bounding box.
  3. Detect the eye pair: connected components of dark pixels inside the head
     zone, eroded first so 1px body outlines do not glue every eye into one
     giant blob; scored by symmetry, height agreement and head position.
  4. Sample a lid colour from the fur band right above the eyes.
  5. Derive the gait class from the bounding box aspect ratio.
Records are emitted sorted by dex id, so the output is byte-stable across
runs and safe to commit.

Usage:
  python3 Tools/gen-animation-pack.py                 # build the pack
  python3 Tools/gen-animation-pack.py --sheet out.png # + visual QA contact sheet

Requires Pillow. Downloads are cached under /tmp/opencode/petpack-cache.
"""

import io
import os
import struct
import sys
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageFilter, ImageDraw

SPRITE_BASE = (
    "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"
)
ANIMATED_URL = SPRITE_BASE + "versions/generation-v/black-white/animated/{id}.gif"
STATIC_URL = SPRITE_BASE + "{id}.png"

CACHE_DIR = "/tmp/opencode/petpack-cache"
OUTPUT_DEFAULT = os.path.join(os.path.dirname(__file__), "..", "Resources", "pet-animation-pack.bin")

DEX_MIN, DEX_MAX = 1, 1025

MAGIC = b"CPAP"
VERSION = 3
HEADER = struct.Struct("<4sHH")          # magic, version, count
RECORD = struct.Struct("<HBBBB4s4s3sBBBB")   # id, flags, canvasW, canvasH, bodyFlags, lRect, rRect, rgb, legLx, legRx, legTopY, legW
# flags bit 0 = hasEyes, bits 2-3 = gait class (0 low, 1 medium, 2 tall)
# bodyFlags bit 0 = hasLegs, bit 1 = hasWings (wings only pick the glide
# travel style — nothing about the sprite is sliced for them)

_UNSET = object()
# Species whose sliced legs the detector gets wrong and hand-tuning fixes.
# Value = (leftFootX, rightFootX, legTopY, legWidth) in canvas pixels, or
# None to say "this design has no legs, use the pack-free hop".
#
# The None entries are all the same mistake in different costumes: the
# detector found two narrow columns under the body and they were fins, coils,
# tentacles, spikes, roots or a saucer rather than legs. Reviewed one by one
# against the composited stride (Tools/qa-animation-pack.py walk).
LEG_OVERRIDES = {
    73: None,    # Tentacruel — floating jellyfish, those are tentacles
    75: None,    # Graveler — arms and a boulder, no legs at all
    92: None,    # Gastly — a gas cloud
    95: None,    # Onix — rock snake, the "feet" are tail segments
    119: None,   # Seaking — fish fins
    121: None,   # Starmie — a floating star, the points are not legs
    201: None,   # Unown — a floating glyph
    202: None,   # Wobbuffet — its tail hangs where the feet would be
    266: None,   # Silcoon — a cocoon on silk spikes
    339: None,   # Barboach — fish
    340: None,   # Whiscash — fish
    343: None,   # Baltoy — a spinning top balanced on one point
    382: None,   # Kyogre — a whale
    386: None,   # Deoxys — floats, those are tendrils
    479: None,   # Rotom — plasma, the points are its bolt shape
    481: None,   # Mesprit — floats
    488: None,   # Cresselia — floats, the "legs" are ribbons
    517: None,   # Munna — floats
    524: None,   # Roggenrola — one rock base, not a pair of feet
    562: None,   # Yamask — floats, carrying its mask below
    593: None,   # Jellicent — floating jellyfish skirt
    600: None,   # Klang — gears
    608: None,   # Lampent — a floating lamp with a flame tail
    670: None,   # Floette — floats
    707: None,   # Klefki — a floating keyring
    730: None,   # Primarina — a mermaid tail
    742: None,   # Cutiefly — hovers
    743: None,   # Ribombee — hovers
    781: None,   # Dhelmise — an anchor swinging on seaweed
    785: None,   # Tapu Koko — hovers inside its shell
    793: None,   # Nihilego — jellyfish tendrils
    798: None,   # Kartana — a paper blade
    846: None,   # Arrokuda — fish
    847: None,   # Barraskewda — fish
    851: None,   # Centiskorch — many small legs under one long body
    855: None,   # Polteageist — a teapot on a saucer
    883: None,   # Arctovish — fish fins
    885: None,   # Dreepy — floats
    886: None,   # Drakloak — floats
    904: None,   # Overqwil — spikes, not legs
    977: None,   # Dondozo — fish fins
    990: None,   # Iron Treads — a wheel
    1011: None,  # Dipplin — an apple
    1013: None,  # Sinistcha — a floating teacup
}
# Flying types that never leave the ground.
FLIGHTLESS = {84, 85, 701}

# Eye rects the detector gets wrong, in canvas pixels. Reviewed one by one
# against the lids-shut contact sheets (Tools/qa-animation-pack.py blink).
#   None -> no eyelids at all. A buddy that never blinks beats one that
#           paints a lid on its shoulder cannon every four seconds.
#   ((x, y, w, h), (x, y, w, h)) -> hand-measured lids. The same rect twice
#           is how a three-quarter pose showing only one eye is encoded: two
#           identical lids draw as one.
EYE_OVERRIDES = {
    9: ((24, 12, 6, 5), (24, 12, 6, 5)),    # Blastoise — only one eye faces us
    4: ((6, 8, 4, 5), (17, 7, 5, 6)),       # Charmander — detector found cheek + half an eye
    12: None,    # Butterfree — lids swallow half the head
    24: None,    # Arbok — found the hood pattern, not the eyes
    30: None,    # Nidorina — landed on an ear
    40: None,    # Wigglytuff — landed on both ears
    131: None,   # Lapras — one lid ends up on the shell
    213: None,   # Shuckle — found two shell holes
    393: ((4, 13, 6, 7), (13, 12, 9, 10)),  # Piplup — both eye patches
    444: None,   # Gabite — landed on the arms
    726: ((29, 49, 4, 5), (37, 49, 5, 5)),  # Torracat — the ears fooled the detector
    750: None,   # Mudsdale — landed on the mane
    774: None,   # Minior — the meteor shell has no eyes to shut
    828: None,   # Thievul — landed on the flank
    848: None,   # Toxel — lid sits above the eyes
    851: None,   # Centiskorch — found two body segments
    852: None,   # Clobbopus — one lid lands on an arm
    993: None,   # Iron Jugulis — bright lids over both heads
    1014: None,  # Okidogi — landed on the shoulders
    1016: None,  # Fezandipiti — landed on the plumage
    1025: None,  # Pecharunt — landed on the chain

    # Reviewed one by one against the *sleeping* sheets, a harsher bar than
    # blinking: a blink is 0.13 s and forgives a lid a pixel off, a nap holds
    # it on screen for minutes. These 81 all leave a visibly open eye. Nearly
    # every one has bright eyes — yellow, red, cyan — which `eyeish` cannot
    # see (it keys on dark or deep-saturated ink), so the detector latched
    # onto a mouth, a marking or a cheek instead. Dropping the lids costs
    # them their blink too; a wrong blink was never worth keeping.
    15: None, 27: None, 39: None, 47: None, 48: None, 54: None, 66: None, 72: None, 73: None, 82: None,
    98: None, 109: None, 129: None, 166: None, 167: None, 205: None, 215: None, 218: None, 219: None, 273: None,
    294: None, 295: None, 302: None, 318: None, 341: None, 342: None, 344: None, 345: None, 355: None, 356: None,
    362: None, 411: None, 415: None, 416: None, 432: None, 445: None, 447: None, 448: None, 453: None, 454: None,
    466: None, 467: None, 494: None, 495: None, 496: None, 504: None, 505: None, 509: None, 547: None, 559: None,
    560: None, 570: None, 571: None, 574: None, 592: None, 599: None, 600: None, 601: None, 610: None, 632: None,
    636: None, 656: None, 657: None, 664: None, 678: None, 694: None, 700: None, 725: None, 727: None, 762: None,
    763: None, 791: None, 807: None, 815: None, 860: None, 893: None, 906: None, 907: None, 950: None, 985: None,
    996: None,
}

MAX_BBOX_SIDE = 250          # coordinates are u8, bbox-relative; leave headroom
HEAD_ZONE = 0.62             # fraction of the bbox height eyes may sit in
DARK_LUMA = 97               # max(r,g,b) below this counts as outline/pupil dark
DARK_SAT_VALUE = 0.56        # saturated deep colours (red eyes etc.) count too


def fetch(id_, session_cache=True):
    """Returns the decoded RGBA sprite for a dex id, or None."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    paths = [
        os.path.join(CACHE_DIR, f"{id_}.gif"),
        os.path.join(CACHE_DIR, f"{id_}.png"),
    ]
    if session_cache:
        for p in paths:
            if os.path.exists(p):
                try:
                    return Image.open(p).convert("RGBA")
                except Exception:
                    pass
    for url_template, path in ((ANIMATED_URL, paths[0]), (STATIC_URL, paths[1])):
        url = url_template.format(id=id_)
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:
                data = resp.read()
            if resp.status != 200 or len(data) < 64:
                continue
            img = Image.open(io.BytesIO(data)).convert("RGBA")
            with open(path, "wb") as fh:
                fh.write(data)
            return img
        except (urllib.error.URLError, OSError, Exception):
            continue
    return None


def first_frame(img):
    return img.convert("RGBA")


def alpha_bbox(img):
    alpha = img.getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > 64 else 0).getbbox()
    return bbox


def eyeish(px):
    """True where an eye could live: near-black outline/pupil, or a deep
    saturated fill (dark red / blue irises)."""
    r, g, b, a = px
    if a <= 64:
        return False
    v = max(r, g, b)
    if v < DARK_LUMA:
        return True
    mx, mn = v, min(r, g, b)
    sat = 0 if mx == 0 else (mx - mn) / mx
    val = mx / 255.0
    return sat > DARK_SAT_VALUE and val < DARK_SAT_VALUE


def components(mask, width, height):
    """4-connected components of a boolean bitmap -> list[(area, x0,y0,x1,y1)]."""
    seen = bytearray(len(mask))
    comps = []
    for start in range(len(mask)):
        if not mask[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        area = 0
        x0 = y0 = 1 << 30
        x1 = y1 = -(1 << 30)
        sx = sy = 0
        while stack:
            idx = stack.pop()
            x, y = idx % width, idx // width
            area += 1
            sx += x
            sy += y
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    nidx = ny * width + nx
                    if mask[nidx] and not seen[nidx]:
                        seen[nidx] = 1
                        stack.append(nidx)
        comps.append({"area": area, "box": (x0, y0, x1, y1), "cx": sx / area, "cy": sy / area})
    return comps


def interior_mask(mask, alpha, width, height):
    """Dark pixels that do not touch transparency.

    Shell = dark pixels 8-adjacent to a transparent pixel, i.e. the visible
    silhouette outline and any dark edge hugging the background. Eye rings
    welded to that outline get cut loose from it; what stays inside is eyes,
    nostrils, mouths and markings. Working from the alpha channel (rather
    than flooding through non-dark pixels) matters because many sprites bound
    their fur directly with transparency, and a flood would leak through the
    un-outlined edges straight into the face and swallow the eyes.
    """
    inner = bytearray(len(mask))
    for idx in range(len(mask)):
        if not mask[idx]:
            continue
        x, y = idx % width, idx // width
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
                       (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)):
            if 0 <= nx < width and 0 <= ny < height and alpha[ny * width + nx] <= 64:
                break
        else:
            inner[idx] = 1
    return inner


def head_mid(alpha, cw, ch):
    """Horizontal centre of the head zone (top 45% of the bbox) by opaque
    mass. Sprites often park the body asymmetrically in the canvas, so the
    bbox midpoint is a poor proxy for where the face straddles."""
    y_max = max(1, int(ch * 0.45))
    sx = n = 0
    for y in range(y_max):
        for x in range(cw):
            if alpha[y * cw + x] > 64:
                sx += x
                n += 1
    return sx / n if n else cw / 2


def white_adjacent(pixels, cw, ch, comp):
    """True when a near-white pixel (sclera/shine) sits within 2px of the
    blob — the strongest single cue separating eyes from ears and paws."""
    x0, y0, x1, y1 = comp["box"]
    hits = 0
    for y in range(max(0, y0 - 2), min(ch, y1 + 3)):
        for x in range(max(0, x0 - 2), min(cw, x1 + 3)):
            r, g, b, a = pixels[y * cw + x]
            if a > 100 and min(r, g, b) > 170:
                hits += 1
                if hits >= 1:
                    return True
    return False


_TRACE = False
def _log(*args):
    if _TRACE:
        print(*args)


def detect_eyes(img):
    """
    Returns (left_rect, right_rect) in absolute image coordinates, each as
    (x, y, w, h), or None when no credible eye pair exists.

    Works on interior dark blobs (see interior_mask): eyes survive, ears and
    outlines do not. Pairs are scored by vertical agreement, size match,
    symmetry, centre-line and head placement, and white-sclera adjacency.
    Falls back to the raw mask (minus giant blobs) when the interior leaves
    nothing usable.
    """
    bbox = alpha_bbox(img)
    if bbox is None:
        return None
    bx0, by0, bx1, by1 = bbox
    bw, bh = bx1 - bx0, by1 - by0
    if bw <= 4 or bh <= 4:
        return None

    crop = img.crop(bbox)
    cw, ch = crop.size
    pixels = list(crop.getdata())
    alpha = [p[3] for p in pixels]
    mask = [bool(b) for b in [eyeish(p) for p in pixels]]

    def collect(m):
        head_bottom = ch * HEAD_ZONE
        cands = []
        for c in components(m, cw, ch):
            if c["cy"] > head_bottom or c["area"] < 1:
                continue
            x0, y0, x1, y1 = c["box"]
            w, h = x1 - x0 + 1, y1 - y0 + 1
            if c["area"] > bw * bh * 0.15 or w > bw * 0.45 or h > bh * 0.5:
                continue
            aspect = w / h
            if aspect > 8.0 or aspect < 0.14:
                continue
            c["white"] = white_adjacent(pixels, cw, ch, c)
            c["aspect_pen"] = max(0.0, abs(aspect - 1.0) - 1.2) * 5.0
            if aspect < 0.5:
                c["aspect_pen"] += (0.5 - aspect) * 14.0
            cands.append(c)
        # Non-max suppression: one blob per eye (a pupil and its broken
        # outline ring must not become two candidates).
        cands.sort(key=lambda c: -c["area"])
        kept = []
        for c in cands:
            x0, y0, x1, y1 = c["box"]
            dup = False
            for k in kept:
                kx0, ky0, kx1, ky1 = k["box"]
                ix = max(0, min(x1, kx1) - max(x0, kx0))
                iy = max(0, min(y1, ky1) - max(y0, ky0))
                inter = ix * iy
                small = min(c["area"], k["area"])
                if small and inter > small * 0.35:
                    dup = True
                    break
            if not dup:
                kept.append(c)
        return kept

    def pick_pair(cands, midx):
        """Best eye pair with its score, or None. Pairs with white sclera on
        both sides are trusted on loose geometry; pairs without white must be
        near-perfect (aligned, in the eye band) so nostrils, mouths and ear
        fills stay out."""
        # Every candidate combination is considered — three-quarter views
        # often park the whole face on one side of the head-mass centreline,
        # so a hard left/right split would lose real pairs.
        ordered = sorted(cands, key=lambda c: c["cx"])
        best, best_score = None, None
        for i in range(len(ordered)):
            for j in range(i + 1, len(ordered)):
                lc, rc = ordered[i], ordered[j]
                dy = abs(lc["cy"] - rc["cy"])
                if dy > bh * 0.18:
                    continue
                gap = rc["cx"] - lc["cx"]
                if gap < bw * 0.07 or gap > bw * 0.65:
                    continue
                da = abs(lc["area"] - rc["area"]) / max(lc["area"], rc["area"], 1)
                mean_y = (lc["cy"] + rc["cy"]) / 2
                score = (
                    dy * 1.4
                    + da * 8
                    + abs((midx - lc["cx"]) - (rc["cx"] - midx)) * 0.9
                    + abs(mean_y - ch * 0.34) * 0.40
                    + lc["aspect_pen"] + rc["aspect_pen"]
                    + (0 if lc["white"] else 8) + (0 if rc["white"] else 8)
                    + (3 if lc["area"] < 2 else 0) + (3 if rc["area"] < 2 else 0)
                    - min(lc["area"], 40) * 0.05 - min(rc["area"], 40) * 0.05
                )
                if mean_y < ch * 0.16:
                    score += 10
                if best_score is None or score < best_score:
                    best_score, best = score, (lc, rc)
        if best is None:
            return None, None
        white = best[0]["white"] and best[1]["white"]
        mean_y = (best[0]["cy"] + best[1]["cy"]) / 2
        if not white:
            if not ch * 0.16 <= mean_y <= ch * 0.50:
                return None, best_score
        elif not ch * 0.08 <= mean_y <= ch * 0.52:
            return None, best_score
        if best_score > (30 if white else 13):
            return None, best_score
        return best, best_score

    def grow(c):
        x0, y0, x1, y1 = c["box"]
        w, h = x1 - x0 + 1, y1 - y0 + 1
        cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
        # Grow the seed into the visible eye, capped relative to the canvas
        # so a small sprite never gets a unibrow. A bare pupil dot needs
        # room to cover its sclera; a ring/outline blob already spans the
        # eye and only needs a nudge.
        max_w = max(5.0, cw * 0.24)
        max_h = max(4.0, ch * 0.22)
        if c["area"] <= 4:
            gw = min(max(w * 2.2, w + 4), max_w)
            gh = min(max(h * 2.0, h + 3), max_h)
        else:
            gw = min(w + 2, max_w)
            gh = min(h + 2, max_h)
        gx0 = max(0, int(cx - gw / 2))
        gy0 = max(0, int(cy - gh / 2))
        gx1 = min(cw, int(cx + gw / 2) + 1)
        gy1 = min(ch, int(cy + gh / 2) + 1)
        return (gx0, gy0, gx1 - gx0, gy1 - gy0)

    pair = None
    hm = head_mid(alpha, cw, ch)
    inner_cands = collect(interior_mask(mask, alpha, cw, ch))
    if _TRACE:
        for c in inner_cands:
            _log("  cand", c["box"], "area", c["area"], "white", c["white"], "cx", round(c["cx"],1), "cy", round(c["cy"],1))
    _log("  head midx:", round(hm, 1))
    p, pscore = pick_pair(inner_cands, hm)
    _log("  pair:", "yes" if p else "no", pscore)
    if p is not None:
        pair = p
    if pair is None:
        # Three-quarter views often keep only one eye as a clean interior
        # blob (the other welds into the silhouette outline). Mirror the
        # strongest survivor across the centre line when the mirror site
        # has ink.
        strong = [
            c for c in inner_cands
            if c["white"] and c["area"] >= 3 and ch * 0.14 <= c["cy"] <= ch * 0.58
            and abs(c["cx"] - hm) >= bw * 0.10
        ]
        x0s, y0s, x1s, y1s = strong[0]["box"] if strong else (0, 0, 0, 0)
        if strong and (x1s - x0s + 1) / (y1s - y0s + 1) < 0.45:
            strong = []
        strong.sort(key=lambda c: -c["area"])
        if strong:
            c = strong[0]
            x0, y0, x1, y1 = c["box"]
            mx0 = int(2 * hm - x1 - 1)
            mx1 = int(2 * hm - x0)
            ink = 0
            for y in range(max(0, y0 - 1), min(ch, y1 + 2)):
                for x in range(max(0, mx0 - 1), min(cw, mx1 + 2)):
                    if mask[y * cw + x]:
                        ink += 1
            _log("  mirror ink:", ink, "at x", mx0, "-", mx1)
            if ink >= 2:
                mirror = {
                    "box": (mx0, y0, mx1 - 1, y1),
                    "area": c["area"],
                    "cx": 2 * hm - c["cx"],
                    "cy": c["cy"],
                    "white": True,
                    "aspect_pen": c["aspect_pen"],
                }
                pair = (c, mirror) if c["cx"] < hm else (mirror, c)
    if pair is None:
        return None

    rects = sorted((grow(c) for c in pair), key=lambda r: r[0])
    (ax, ay, aw, ah), (bx2, by2, bw2, bh2) = rects
    # Two lids that touch read as one unibrow, and any column they share gets
    # painted twice. Trim the overlap off the inner edges: growth expanded
    # each rect symmetrically about its own eye, so the outer half is the
    # half that actually sits over the eye.
    overlap = (ax + aw + 1) - bx2
    if overlap > 0:
        left_trim = overlap // 2
        aw = max(2, aw - left_trim)
        shift = overlap - left_trim
        bx2 += shift
        bw2 = max(2, bw2 - shift)
        rects = [(ax, ay, aw, ah), (bx2, by2, bw2, bh2)]
    return [
        (r[0] + bx0, r[1] + by0, r[2], r[3]) for r in rects
    ]


def sample_lid_color(img, bbox, eye_pair):
    """Skin colour from the ring of pixels hugging each eye.

    A closed eyelid is the face's own skin drawn over the eye, so the colour
    has to come from what immediately surrounds that eye — not, as it used to,
    from a band across the brow. On most designs the brow is a different
    colour from the eye socket (Squirtle's pale cheek, Charmander's cream
    muzzle), and sampling it gave every sleeping buddy a pair of bright
    goggles. The median of the ring is used rather than the mode: a ring is a
    small sample and the mode latches onto single stray pixels.

    Falls back to the sprite's dominant non-extreme colour, then warm grey.
    """
    bx0, by0, bx1, by1 = bbox
    px = img.load()

    def ring_pixels(rect, pad):
        x, y, w, h = rect
        out = []
        for yy in range(y - pad, y + h + pad):
            for xx in range(x - pad, x + w + pad):
                if x <= xx < x + w and y <= yy < y + h:
                    continue                       # the eye itself
                if not (0 <= xx < img.width and 0 <= yy < img.height):
                    continue
                r, g, b, a = px[xx, yy]
                if a <= 100:
                    continue
                v = max(r, g, b)
                if v < 60 or (v > 235 and min(r, g, b) > 210):
                    continue                       # outlines and blown whites
                out.append((r, g, b))
        return out

    samples = []
    for rect in eye_pair:
        for pad in (2, 3, 4):                      # widen until the ring has skin
            found = ring_pixels(rect, pad)
            if len(found) >= 6:
                samples.extend(found)
                break
    if len(samples) >= 6:
        mid = len(samples) // 2
        return tuple(sorted(c[i] for c in samples)[mid] for i in range(3))

    counts = {}
    for r, g, b, a in img.crop(bbox).getdata():
        if a <= 100:
            continue
        key = (r // 24 * 24, g // 24 * 24, b // 24 * 24)
        counts[key] = counts.get(key, 0) + 1
    if counts:
        return max(counts.items(), key=lambda kv: kv[1])[0]
    return (150, 140, 130)


def gait_class(bw, bh):
    ratio = bh / bw
    if ratio < 0.92:
        return 0   # squat: quicker steps, extra waddle
    if ratio <= 1.28:
        return 1   # neutral
    return 2       # tall: slower, deeper bob


def detect_legs(img, bbox):
    """Feet anchors for the walking slice animation, or None.

    A leg is a narrow opaque column that stays narrow for a few rows before
    flaring into the torso. Everything that does not present two of them —
    snakes, blobs, hoverers, Diglett on its mound, anything sitting down —
    gets no sliced legs at all; the pack-free hop reads far better on those
    than two rectangles cut out of the body and swung around.

    When in doubt this returns None on purpose: a species that hops is never
    cursed, a species sliced in the wrong place always is.

    Returns (leftFootX, rightFootX, legTopY, legWidth) in canvas pixels.
    """
    bx0, by0, bx1, by1 = bbox
    bw, bh = bx1 - bx0, by1 - by0
    px = img.load()

    def opaque(x, y):
        return 0 <= x < img.width and 0 <= y < img.height and px[x, y][3] > 64

    _rows = {}

    def row_runs(y):
        if y in _rows:
            return _rows[y]
        runs, start = [], None
        for x in range(bx0, bx1):
            if opaque(x, y):
                if start is None:
                    start = x
            elif start is not None:
                runs.append((start, x - 1))
                start = None
        if start is not None:
            runs.append((start, bx1 - 1))
        merged = []
        for r in runs:                       # bridge 1px anti-alias gaps
            if merged and r[0] - merged[-1][1] <= 2:
                merged[-1] = (merged[-1][0], r[1])
            else:
                merged.append(r)
        _rows[y] = merged
        return merged

    def walk(run, y, step):
        """Follow this column away from row `y`, stopping where it flares
        into the torso. The flare is what tells a leg from a body that simply
        rests on the floor."""
        limit = (run[1] - run[0] + 1) * 2.2 + 2
        out, cur = [], run
        y += step
        while by0 <= y < by1:
            over = [r for r in row_runs(y) if r[1] >= cur[0] - 1 and r[0] <= cur[1] + 1]
            if not over:
                break
            r = max(over, key=lambda r: min(r[1], cur[1]) - max(r[0], cur[0]))
            if r[1] - r[0] + 1 > limit:
                break
            out.append(r)
            cur = r
            y += step
        return out

    max_foot = bw * 0.42
    # The feet row: the row in the bottom band showing the most separate
    # narrow runs, lowest wins ties. The sprite's very bottom row alone is
    # not enough — plenty of designs hang a tail below the feet, and plenty
    # stand with one foot a pixel higher than the other.
    band = max(3, int(bh * 0.22))
    feet_row, feet = by1 - 1, []
    for y in range(by1 - 1, max(by0, by1 - 1 - band) - 1, -1):
        runs = [r for r in row_runs(y) if r[1] - r[0] + 1 <= max_foot]
        if len(runs) > len(feet):
            feet_row, feet = y, runs
    if len(feet) < 2:
        return None

    cands = []
    for run in feet:
        up = walk(run, feet_row, -1)
        height = len(up) + 1
        if height < 3 or height > bh * 0.6:
            continue           # a floor stub, or a tail running the whole body
        cands.append({
            "cx": (run[0] + run[1]) / 2,
            "w": run[1] - run[0] + 1,
            "h": height,
            "rows": [run] + up + walk(run, feet_row, +1),
            "up": up,
        })
    if len(cands) < 2:
        return None

    xs = [x for y in range(feet_row, by1) for x in range(bx0, bx1) if opaque(x, y)]
    xs += [x for y in range(max(by0, by1 - max(2, int(bh * 0.25))), by1)
           for x in range(bx0, bx1) if opaque(x, y)]
    lower_cx = sum(xs) / len(xs) if xs else (bx0 + bx1) / 2

    best, best_score = None, None
    for i in range(len(cands)):
        for j in range(i + 1, len(cands)):
            a, b = sorted((cands[i], cands[j]), key=lambda c: c["cx"])
            gap = b["cx"] - a["cx"]
            if gap < bw * 0.10 or gap > bw * 0.72:
                continue
            w_ratio = max(a["w"], b["w"]) / min(a["w"], b["w"])
            h_ratio = max(a["h"], b["h"]) / min(a["h"], b["h"])
            if w_ratio > 2.6 or h_ratio > 2.6:
                continue                     # a tail and a leg, not a pair
            skew = abs((lower_cx - a["cx"]) - (b["cx"] - lower_cx)) / bw
            if skew > 0.30:
                continue                     # both feet must straddle the body
            score = (skew * 6 + (w_ratio - 1) + (h_ratio - 1)
                     - min(a["h"], b["h"]) / bh)
            if best_score is None or score < best_score:
                best_score, best = score, (a, b)
    if best is None:
        return None

    left, right = best
    rows = min(left["h"], right["h"], max(3, int(bh * 0.45)))
    leg_top = feet_row - rows + 1
    centres, widths = [], []
    for leg in best:
        # Foot row + the traced rows above it (capped to the shorter leg) +
        # everything below it, so a foot that splays wider than its shin
        # still fits inside the crop.
        below = leg["rows"][1 + len(leg["up"]):]
        used = [leg["rows"][0]] + leg["up"][:rows - 1] + below
        x0 = min(r[0] for r in used)
        x1 = max(r[1] for r in used)
        centres.append((x0 + x1) / 2)
        widths.append(x1 - x0 + 1)
    # Values are stored as whole canvas pixels, so decide them here: the
    # runtime expands each crop to whole pixels too, and two crops that share
    # even one column get that column cleared once and drawn twice — a torn
    # seam right between the legs.
    lx, rx = round(centres[0]), round(centres[1])
    width = int(min(max(widths) + 2, max(3, bw * 0.4)))
    width = min(width, rx - lx - 1)
    if width < 3:
        return None        # the feet sit too close together to slice apart
    return (lx, rx, round(leg_top), width)


FLYING_TYPE_ID = None
_winged_ids = None


def winged_ids():
    """Species the flight cycle applies to: everything with a Flying typing
    (from the PokeAPI CSV, cached) plus a curated set of visually winged
    species whose typing does not say Flying (Scyther, Volcarona, ...)."""
    global FLYING_TYPE_ID, _winged_ids
    if _winged_ids is not None:
        return _winged_ids
    curated = {
        83, 123, 212, 284, 313, 314, 380, 381, 487, 635, 637, 792,
        841, 873, 887, 994,
    }
    flying = set()
    try:
        import csv as _csv
        base = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/"
        os.makedirs(CACHE_DIR, exist_ok=True)
        cache = os.path.join(CACHE_DIR, "types.csv")
        if not os.path.exists(cache):
            with urllib.request.urlopen(base + "types.csv", timeout=20) as r:
                open(cache, "wb").write(r.read())
        for row in _csv.DictReader(open(cache)):
            if row["identifier"] == "flying":
                FLYING_TYPE_ID = row["id"]
        cache = os.path.join(CACHE_DIR, "pokemon_types.csv")
        if not os.path.exists(cache):
            with urllib.request.urlopen(base + "pokemon_types.csv", timeout=20) as r:
                open(cache, "wb").write(r.read())
        for row in _csv.DictReader(open(cache)):
            if row["type_id"] == FLYING_TYPE_ID:
                flying.add(int(row["pokemon_id"]))
    except Exception:
        pass
    _winged_ids = curated | flying
    return _winged_ids


def analyze(id_):
    """-> (record_bytes or None, status)"""
    img = fetch(id_)
    if img is None:
        return None, "no-sprite"
    frame = first_frame(img)
    bbox = alpha_bbox(frame)
    if bbox is None:
        return None, "empty"
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    if bw > MAX_BBOX_SIDE or bh > MAX_BBOX_SIDE:
        return None, "bbox-too-big"
    # The runtime displays the full sprite canvas (scaledToFit), so eye
    # rectangles are stored canvas-relative; gait stays bbox-based because
    # body proportions are what matter there.
    canvas_w, canvas_h = frame.size
    flags = gait_class(bw, bh) << 2
    eyes = EYE_OVERRIDES.get(id_, _UNSET)
    if eyes is _UNSET:
        eyes = detect_eyes(frame)

    legs = LEG_OVERRIDES.get(id_, _UNSET)
    if legs is _UNSET:
        legs = detect_legs(frame, bbox)
    body_flags = 1 if legs else 0
    if id_ in winged_ids() and id_ not in FLIGHTLESS:
        body_flags |= 2
    canvas_rel = lambda v: max(0, min(255, int(round(v))))
    leg_bytes = tuple(canvas_rel(v) for v in legs) if legs else (0, 0, 0, 0)

    if eyes is None:
        return RECORD.pack(
            id_, flags, canvas_w, canvas_h, body_flags,
            b"\0" * 4, b"\0" * 4, b"\0" * 3, *leg_bytes,
        ), "no-eyes"
    flags |= 1
    (lx, ly, lw, lh), (rx, ry, rw, rh) = eyes
    lid = sample_lid_color(frame, bbox, eyes)
    rel = lambda x, y, w, h: struct.pack(
        "<BBBB",
        max(0, min(255, x)),
        max(0, min(255, y)),
        max(1, min(255, w)),
        max(1, min(255, h)),
    )
    rec = RECORD.pack(
        id_, flags, canvas_w, canvas_h, body_flags,
        rel(lx, ly, lw, lh), rel(rx, ry, rw, rh),
        bytes(lid), *leg_bytes,
    )
    return rec, "ok"


def load_sprite_for_sheet(id_):
    return fetch(id_)


def make_sheet(ids, out_path):
    cols = 8
    rows = (len(ids) + cols - 1) // cols
    cell = 128
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (24, 24, 28, 255))
    draw = ImageDraw.Draw(sheet)
    for index, id_ in enumerate(ids):
        img = load_sprite_for_sheet(id_)
        cx, cy = (index % cols) * cell, (index // cols) * cell
        if img is None:
            draw.text((cx + 6, cy + 6), f"{id_}?", fill=(255, 90, 90, 255))
            continue
        result = analyze(id_)
        scale = 1
        img_small = img.convert("RGBA")
        while img_small.width * 2 <= cell - 12 and img_small.height * 2 <= cell - 24:
            img_small = img_small.resize((img_small.width * 2, img_small.height * 2), Image.NEAREST)
        sheet.paste(
            img_small,
            (cx + (cell - img_small.width) // 2, cy + 18 + (cell - 30 - img_small.height) // 2),
            img_small,
        )
        if result[0] is not None:
            rec = RECORD.unpack(result[0])
            flags, bwx, bwy, _, lrect, rrect = rec[1], rec[2], rec[3], rec[4], rec[5], rec[6]
            if flags & 1:
                for r in (lrect, rrect):
                    x, y, w, h = r[0], r[1], r[2], r[3]
                    sx = img_small.width / bwx
                    sy = img_small.height / bwy
                    ox = cx + (cell - img_small.width) // 2
                    oy = cy + 18 + (cell - 30 - img_small.height) // 2
                    draw.rectangle(
                        [ox + x * sx, oy + y * sy, ox + (x + w) * sx, oy + (y + h) * sy],
                        outline=(80, 255, 120, 255),
                    )
        draw.text((cx + 4, cy + 3), str(id_), fill=(230, 230, 230, 255))
    sheet.save(out_path)


def main():
    sheet_out = None
    args = sys.argv[1:]
    if "--sheet" in args:
        i = args.index("--sheet")
        sheet_out = args[i + 1]
        args = args[:i] + args[i + 2:]
    out_path = args[0] if args else os.path.normpath(OUTPUT_DEFAULT)
    sample_ids = []
    if "--sample" in args:
        i = args.index("--sample")
        sample_ids = [int(x) for x in args[i + 1].split(",")]
        args = args[:i] + args[i + 2:]

    ids = list(range(DEX_MIN, DEX_MAX + 1))
    winged_ids()   # warm the CSV cache before the pool races on the download
    print(f"▸ analyzing {len(ids)} species…")
    results = {}
    statuses = {}
    with ThreadPoolExecutor(max_workers=10) as pool:
        for id_, (rec, status) in zip(ids, pool.map(analyze, ids)):
            results[id_] = rec
            statuses[id_] = status

    ok = sum(1 for s in statuses.values() if s == "ok")
    misses = [i for i, s in statuses.items() if s != "ok" and s != "no-eyes"]
    no_eyes = [i for i, s in statuses.items() if s == "no-eyes"]
    print(f"  eyes detected: {ok}/{len(ids)} ({100.0 * ok / len(ids):.1f}%)")
    print(f"  no-eyes (body anims only): {len(no_eyes)}")
    if misses:
        print(f"  MISSING SPRITES: {misses}")

    payload = b"".join(results[i] for i in sorted(results) if results[i] is not None)
    data = HEADER.pack(MAGIC, VERSION, len(payload) // RECORD.size) + payload
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as fh:
        fh.write(data)
    print(f"▸ wrote {out_path} ({len(data)} bytes, {len(data) // RECORD.size} records)")

    if sheet_out:
        chosen = sample_ids or ([25, 1, 4, 7, 133, 150, 702, 6] + no_eyes[:40])
        make_sheet(chosen, sheet_out)
        print(f"▸ wrote QA sheet {sheet_out}")


if __name__ == "__main__":
    main()
