#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 chuahchengxi
"""
Visual QA for Resources/pet-animation-pack.bin.

Re-implements exactly what the app composites at runtime (PetSpriteSlicer +
AnimatedSpriteView.slicedBody + PetEyelidsView) so every species' animation
can be eyeballed on a contact sheet instead of one at a time in the app.

  python3 Tools/qa-animation-pack.py walk  out/     # composited mid-stride
  python3 Tools/qa-animation-pack.py diag  out/     # sprite + pack rects
  python3 Tools/qa-animation-pack.py blink out/     # lids shut
  python3 Tools/qa-animation-pack.py sleep out/     # lids shut + sleep tint
  python3 Tools/qa-animation-pack.py audit          # text report, no images

Sprites come from the same cache the generator uses.
"""

import math
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "Resources", "pet-animation-pack.bin")
CACHE = "/tmp/opencode/petpack-cache"

HEADER = struct.Struct("<4sHH")
# Kept in sync with gen-animation-pack.py / PetAnimationPackSupport.swift.
LAYOUTS = {
    2: struct.Struct("<HBBBB4s4s3sBBBBB"),
    3: struct.Struct("<HBBBB4s4s3sBBBB"),
}

SWING = {0: 0.16 * 1.4, 1: 0.16, 2: 0.16 * 0.7}


class Rec:
    __slots__ = (
        "id", "flags", "cw", "ch", "body", "leye", "reye", "lid",
        "legl", "legr", "legtop", "wingtop", "wingbot", "legw",
    )

    @property
    def has_eyes(self):
        return self.flags & 1

    @property
    def gait(self):
        return (self.flags >> 2) & 3

    @property
    def has_legs(self):
        return self.body & 1

    @property
    def has_wings(self):
        return self.body & 2


def load_pack(path=PACK):
    data = open(path, "rb").read()
    magic, version, count = HEADER.unpack(data[:8])
    assert magic == b"CPAP", magic
    rec_struct = LAYOUTS[version]
    out = {}
    for i in range(count):
        base = 8 + i * rec_struct.size
        f = rec_struct.unpack(data[base:base + rec_struct.size])
        r = Rec()
        (r.id, r.flags, r.cw, r.ch, r.body, leye, reye, lid,
         r.legl, r.legr, r.legtop) = f[:11]
        if version >= 3:
            r.legw, r.wingtop, r.wingbot = f[11], 0, 0
        else:
            r.legw, r.wingtop, r.wingbot = 0, f[11], f[12]
        r.leye = tuple(leye)
        r.reye = tuple(reye)
        r.lid = tuple(lid)
        out[r.id] = r
    return version, out


def sprite(id_):
    for ext in ("gif", "png"):
        p = os.path.join(CACHE, f"{id_}.{ext}")
        if os.path.exists(p):
            try:
                return Image.open(p).convert("RGBA")
            except Exception:
                pass
    return None


def integral(x0, y0, x1, y1):
    """CGRect.integral — smallest integral rect containing the rect."""
    return (int(math.floor(x0)), int(math.floor(y0)),
            int(math.ceil(x1)), int(math.ceil(y1)))


def leg_rects(rec, img, zoom):
    """The two leg crop rects in zoomed image space, as the slicer builds them."""
    cw, ch = rec.cw * zoom, rec.ch * zoom
    w = max(3 * zoom, (rec.legw * zoom) if rec.legw else cw * 0.09)
    top = rec.legtop * zoom
    rects = []
    for cx in (rec.legl * zoom, rec.legr * zoom):
        r = integral(
            max(0, cx - w / 2), max(0, top),
            min(img.width, cx + w / 2), min(img.height, ch),
        )
        rects.append(r)
    return rects


def compose_walk(rec, img, zoom, phase):
    """The composited walking frame: body with the leg boxes punched out,
    each leg crop redrawn rotated about its hip."""
    if zoom > 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    out = img.copy()
    if not rec.has_legs:
        return out
    swing = SWING.get(rec.gait, 0.16)
    rects = leg_rects(rec, img, zoom)
    crops = [img.crop(r) for r in rects]
    blank = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for r in rects:
        out.paste(blank.crop(r), (r[0], r[1]))
    for r, crop, ph in zip(rects, crops, (phase, phase + math.pi)):
        hip_x, hip_y = (r[0] + r[2]) / 2, r[1]
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        lift = max(0.0, math.sin(ph)) * rec.ch * zoom * 0.018
        layer.paste(crop, (r[0], int(round(r[1] - lift))))
        layer = layer.rotate(
            -math.degrees(math.sin(ph) * swing),
            resample=Image.NEAREST, center=(hip_x, hip_y),
        )
        out.alpha_composite(layer)
    return out


def compose_blink(rec, img, zoom):
    if zoom > 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    out = img.copy()
    if not rec.has_eyes:
        return out
    zoom = out.width / rec.cw
    d = ImageDraw.Draw(out)
    lash = tuple(int(c * 0.42) for c in rec.lid)
    for x, y, w, h in (rec.leye, rec.reye):
        x, y, w, h = x * zoom, y * zoom, w * zoom, h * zoom
        d.rounded_rectangle([x, y, x + w, y + h], radius=max(1, h * 0.3),
                            fill=rec.lid + (255,))
        d.rectangle([x + w * 0.08, y + h * 0.72, x + w * 0.92, y + h * 0.96],
                    fill=lash + (255,))
    return out


def compose_diag(rec, img, zoom):
    if zoom > 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    out = img.copy()
    d = ImageDraw.Draw(out)
    if rec.has_legs:
        for r in leg_rects(rec, img, zoom):
            d.rectangle([r[0], r[1], r[2] - 1, r[3] - 1], outline=(90, 255, 130, 255))
    if rec.has_eyes:
        for x, y, w, h in (rec.leye, rec.reye):
            d.rectangle([x * zoom, y * zoom, (x + w) * zoom - 1, (y + h) * zoom - 1],
                        outline=(255, 90, 220, 255))
    return out


def compose_sleep(rec, img, zoom):
    """The sleeping pose exactly as the app composites it: lids shut, then
    sprite AND lids desaturated and dimmed together (PetSleepTint).

    Judged at a harsher bar than `blink`: a blink is 0.13 s and forgives a
    lid a pixel off, a nap holds it on screen for minutes.
    """
    lidded = compose_blink(rec, img, zoom)
    rgb = ImageEnhance.Color(lidded.convert("RGB")).enhance(0.45)
    px = rgb.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = px[x, y]
            px[x, y] = (max(0, r - 38), max(0, g - 38), max(0, b - 38))
    return Image.merge("RGBA", (*rgb.split(), lidded.getchannel("A")))


def compose_all(rec, img, zoom):
    """Both animations at once: mid-stride with the lids shut. One sheet per
    64 species is then enough to review the whole dex."""
    walked = compose_walk(rec, img, zoom, math.pi / 2)
    return compose_blink(rec, walked, 1)


MODES = {"walk": lambda r, i, z: compose_walk(r, i, z, math.pi / 2),
         "blink": compose_blink,
         "diag": compose_diag,
         "sleep": compose_sleep,
         "all": compose_all}


def sheet(ids, recs, mode, cell=168, cols=8):
    rows = (len(ids) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cell, rows * cell), (22, 22, 26, 255))
    d = ImageDraw.Draw(out)
    fn = MODES[mode]
    for i, id_ in enumerate(ids):
        ox, oy = (i % cols) * cell, (i // cols) * cell
        d.text((ox + 4, oy + 3), str(id_), fill=(235, 235, 235, 255))
        img = sprite(id_)
        rec = recs.get(id_)
        if img is None or rec is None:
            d.text((ox + 4, oy + 16), "MISSING", fill=(255, 90, 90, 255))
            continue
        # Zoom against the sprite's own bounds, not the canvas: gen-6+ PNGs
        # sit on a padded 96x96 sheet and would otherwise render postage-stamp
        # sized next to the tightly cropped gen-V GIFs.
        bb = bbox(img) or (0, 0, img.width, img.height)
        zoom = max(1, min((cell - 8) // max(1, bb[2] - bb[0]),
                          (cell - 22) // max(1, bb[3] - bb[1])))
        composed = fn(rec, img, zoom).crop(
            (bb[0] * zoom, bb[1] * zoom, bb[2] * zoom, bb[3] * zoom))
        out.alpha_composite(
            composed,
            (ox + (cell - composed.width) // 2,
             oy + 18 + (cell - 20 - composed.height) // 2),
        )
        tag = ("L" if rec.has_legs else "-") + ("W" if rec.has_wings else "-") + \
              ("E" if rec.has_eyes else "-") + str(rec.gait)
        d.text((ox + cell - 34, oy + 3), tag, fill=(150, 150, 160, 255))
    return out


def bbox(img):
    return img.getchannel("A").point(lambda a: 255 if a > 64 else 0).getbbox()


def ink_fraction(img, box):
    x0, y0, x1, y1 = box
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(img.width, x1), min(img.height, y1)
    if x1 <= x0 or y1 <= y0:
        return 0.0
    crop = img.crop((x0, y0, x1, y1)).getchannel("A")
    hits = sum(1 for a in crop.getdata() if a > 64)
    return hits / ((x1 - x0) * (y1 - y0))


def audit_one(rec, img):
    """Every way a record can make a species look cursed, as a list of tags."""
    bad = []
    bb = bbox(img)
    if bb is None:
        return ["empty-sprite"]
    bx0, by0, bx1, by1 = bb
    bw, bh = bx1 - bx0, by1 - by0

    if rec.has_eyes:
        (lx, ly, lw, lh), (rx, ry, rw, rh) = rec.leye, rec.reye
        for tag, (x, y, w, h) in (("L", rec.leye), ("R", rec.reye)):
            if ink_fraction(img, (x, y, x + w, y + h)) < 0.45:
                bad.append(f"eye{tag}-off-body")
            if y + h / 2 > by0 + bh * 0.58:
                bad.append(f"eye{tag}-too-low")
            if w > bw * 0.34 or h > bh * 0.30:
                bad.append(f"eye{tag}-oversized")
        if rec.leye != rec.reye and not (lx + lw <= rx or rx + rw <= lx):
            bad.append("eyes-overlap")   # identical rects are the one-eye encoding
        if max(rec.lid) < 60:
            bad.append("lid-near-black")
        if abs((ly + lh / 2) - (ry + rh / 2)) > bh * 0.14:
            bad.append("eyes-uneven")

    if rec.has_legs:
        # Clip to the sprite's own rows: static PNG sprites sit on a 96x96
        # canvas with empty space below the feet, and counting that as "air"
        # would flag every gen-6+ species.
        rects = [(r[0], r[1], r[2], min(r[3], by1)) for r in leg_rects(rec, img, 1)]
        inks = [ink_fraction(img, r) for r in rects]
        for tag, ink in zip("LR", inks):
            if ink < 0.22:
                bad.append(f"leg{tag}-mostly-air")
        if max(inks) > 0 and min(inks) / max(inks) < 0.35:
            bad.append("legs-lopsided")
        if rec.legtop < by0 + bh * 0.45:
            bad.append("legs-reach-into-torso")
        if rects[0][2] > rects[1][0]:
            bad.append("legs-overlap")
    return bad


def run_audit(recs, version):
    from collections import Counter
    print(f"pack v{version}: {len(recs)} records  "
          f"legs={sum(1 for r in recs.values() if r.has_legs)}  "
          f"wings={sum(1 for r in recs.values() if r.has_wings)}  "
          f"eyes={sum(1 for r in recs.values() if r.has_eyes)}")
    tally, flagged = Counter(), {}
    for id_ in sorted(recs):
        img = sprite(id_)
        if img is None:
            print(f"  {id_}: NO SPRITE")
            continue
        bad = audit_one(recs[id_], img)
        if bad:
            flagged[id_] = bad
            tally.update(bad)
    print(f"flagged {len(flagged)}/{len(recs)} species")
    for tag, n in tally.most_common():
        ids = [i for i, b in flagged.items() if tag in b]
        print(f"  {tag:26} {n:4}  {ids[:24]}{' …' if len(ids) > 24 else ''}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "walk"
    version, recs = load_pack()
    ids = sorted(recs)
    if len(sys.argv) > 3:
        ids = [i for i in ids if int(sys.argv[3]) <= i <= int(sys.argv[4])] \
            if len(sys.argv) > 4 else [int(x) for x in sys.argv[3].split(",")]
    if mode == "audit":
        run_audit(recs, version)
        return
    outdir = sys.argv[2] if len(sys.argv) > 2 else "/tmp/petqa"
    os.makedirs(outdir, exist_ok=True)
    per = 64
    for start in range(0, len(ids), per):
        chunk = ids[start:start + per]
        path = os.path.join(outdir, f"{mode}-{chunk[0]:04d}-{chunk[-1]:04d}.png")
        sheet(chunk, recs, mode).save(path)
        print(path)


if __name__ == "__main__":
    main()
