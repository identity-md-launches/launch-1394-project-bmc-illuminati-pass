#!/usr/bin/env python3
"""Generate the 77 original Genesis artworks (genesis-01.png .. genesis-77.png), 1024x1024.

Original character: a mysterious cartoon frog in a black hooded cloak with gold trim, a glowing
golden third eye and a floating golden eye-in-triangle. Not based on any existing character.
genesis-01 is the Legendary piece: unique crown, radiant halo, veil and double-sigil.

Deterministic: the same script always produces byte-identical files (seeded by artwork number),
so the IPFS directory CID is reproducible.

Usage: python3 artwork/tools/generate_genesis.py [out_dir]
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
GOLD = (212, 175, 55)
GOLD_LIGHT = (255, 221, 120)
GOLD_DEEP = (160, 120, 30)
BLACK = (8, 8, 10)
CLOAK = (14, 14, 18)
CLOAK_EDGE = (34, 32, 36)
FROG = (62, 140, 74)
FROG_DARK = (30, 80, 40)
FROG_LIGHT = (110, 190, 120)
WHITE = (245, 245, 240)

BACKGROUNDS = [
    ((6, 6, 10), (28, 22, 10)),
    ((10, 8, 14), (40, 30, 8)),
    ((4, 6, 8), (26, 26, 26)),
    ((12, 6, 4), (44, 28, 10)),
    ((6, 10, 8), (30, 30, 14)),
    ((8, 8, 8), (36, 28, 16)),
    ((5, 4, 12), (34, 24, 12)),
]


def radial_background(idx, rnd):
    inner, outer = BACKGROUNDS[idx % len(BACKGROUNDS)]
    img = Image.new("RGB", (SIZE, SIZE), outer)
    px = img.load()
    cx, cy = SIZE / 2, SIZE * 0.42
    maxd = math.hypot(SIZE, SIZE) / 2
    for y in range(SIZE):
        for x in range(0, SIZE, 1):
            d = math.hypot(x - cx, y - cy) / maxd
            t = min(1.0, d * 1.25)
            px[x, y] = tuple(int(inner[i] * (1 - t) + outer[i] * t) for i in range(3))
    draw = ImageDraw.Draw(img)
    # Faint gold constellation dust
    for _ in range(90):
        x, y = rnd.randint(0, SIZE - 1), rnd.randint(0, SIZE - 1)
        r = rnd.choice([1, 1, 1, 2])
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(90 + rnd.randint(0, 60), 75 + rnd.randint(0, 40), 20))
    return img


def glow_layer(size, center, radius, color, blur):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_eye_in_triangle(draw, cx, cy, size, stroke, legendary=False):
    h = size * math.sqrt(3) / 2
    pts = [(cx, cy - 2 * h / 3), (cx - size / 2, cy + h / 3), (cx + size / 2, cy + h / 3)]
    draw.polygon(pts, outline=GOLD, width=stroke)
    inner = [(cx, cy - 2 * h / 3 + stroke * 2.5), (cx - size / 2 + stroke * 2.2, cy + h / 3 - stroke * 1.3),
             (cx + size / 2 - stroke * 2.2, cy + h / 3 - stroke * 1.3)]
    draw.polygon(inner, outline=GOLD_LIGHT, width=max(2, stroke // 3))
    ew, eh = size * 0.42, size * 0.2
    ey = cy + h / 12
    draw.ellipse((cx - ew / 2, ey - eh / 2, cx + ew / 2, ey + eh / 2), fill=BLACK, outline=GOLD, width=stroke // 2)
    draw.ellipse((cx - eh * 0.45, ey - eh * 0.45, cx + eh * 0.45, ey + eh * 0.45), fill=GOLD)
    draw.ellipse((cx - eh * 0.2, ey - eh * 0.2, cx + eh * 0.2, ey + eh * 0.2), fill=BLACK)
    # Rays
    nrays = 16 if legendary else 10
    for k in range(nrays):
        a = -math.pi / 2 + k * 2 * math.pi / nrays
        r0 = size * 0.62
        r1 = size * (0.78 if k % 2 == 0 else 0.7)
        draw.line((cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + r1 * math.cos(a), cy + r1 * math.sin(a)),
                  fill=GOLD, width=max(2, stroke // 2))


def draw_frog(img, rnd, n, legendary):
    draw = ImageDraw.Draw(img, "RGBA")
    cx = SIZE / 2
    # Cloak body
    body = [(cx - 330, SIZE), (cx - 250, 520), (cx - 150, 330), (cx, 250), (cx + 150, 330), (cx + 250, 520),
            (cx + 330, SIZE)]
    draw.polygon(body, fill=CLOAK)
    draw.line(body, fill=GOLD, width=10)
    # Gold trim lines down the cloak
    trim_w = 18 if legendary else 10
    draw.line([(cx - 120, SIZE), (cx - 95, 560)], fill=GOLD, width=trim_w)
    draw.line([(cx + 120, SIZE), (cx + 95, 560)], fill=GOLD, width=trim_w)
    # Hood (ellipse-ish) with a dark interior
    draw.ellipse((cx - 250, 170, cx + 250, 690), fill=CLOAK, outline=GOLD, width=10)
    draw.ellipse((cx - 200, 220, cx + 200, 660), fill=(4, 4, 6))
    # Face
    draw.ellipse((cx - 165, 330, cx + 165, 600), fill=FROG)
    draw.ellipse((cx - 110, 440, cx + 110, 600), fill=FROG_LIGHT)
    # Eye bumps
    for sx in (-1, 1):
        ex = cx + sx * 95
        draw.ellipse((ex - 62, 300, ex + 62, 420), fill=FROG)
        draw.ellipse((ex - 46, 320, ex + 46, 410), fill=WHITE)
        # Pupil variation
        pr = 20 + (n % 5) * 2
        off = (n % 3 - 1) * 6
        draw.ellipse((ex - pr + off, 345, ex + pr + off, 345 + 2 * pr), fill=BLACK)
        draw.ellipse((ex - 7 + off, 352, ex + 3 + off, 362), fill=WHITE)
        # Heavy hooded lids
        draw.chord((ex - 50, 300, ex + 50, 400), 180, 360, fill=(4, 4, 6))
    # Mouth
    mw = 110 + (n % 4) * 10
    draw.arc((cx - mw, 470, cx + mw, 580), 15, 165, fill=FROG_DARK, width=9)
    # Cheek shade
    draw.ellipse((cx - 160, 480, cx - 100, 520), fill=(50, 120, 60, 120))
    draw.ellipse((cx + 100, 480, cx + 160, 520), fill=(50, 120, 60, 120))
    # Third eye (glowing gold) on the forehead
    tx, ty = cx, 300
    draw.ellipse((tx - 42, ty - 22, tx + 42, ty + 22), fill=GOLD_LIGHT, outline=GOLD, width=5)
    draw.ellipse((tx - 16, ty - 16, tx + 16, ty + 16), fill=GOLD_DEEP)
    draw.ellipse((tx - 7, ty - 7, tx + 7, ty + 7), fill=BLACK)
    # Cloak clasp
    draw.polygon([(cx, 640), (cx - 28, 675), (cx, 710), (cx + 28, 675)], fill=GOLD, outline=GOLD_LIGHT)
    # Hands holding a gold pendant (variation by n)
    if n % 2 == 0:
        draw.ellipse((cx - 90, 760, cx - 20, 830), fill=FROG, outline=FROG_DARK, width=4)
        draw.ellipse((cx + 20, 760, cx + 90, 830), fill=FROG, outline=FROG_DARK, width=4)
        draw.line([(cx - 30, 790), (cx + 30, 790)], fill=GOLD, width=6)
        draw.ellipse((cx - 22, 800, cx + 22, 844), fill=GOLD, outline=GOLD_LIGHT, width=3)
    # Legendary extras
    if legendary:
        # Crown
        crown = [(cx - 150, 215), (cx - 150, 120), (cx - 95, 190), (cx - 45, 90), (cx, 180), (cx + 45, 90),
                 (cx + 95, 190), (cx + 150, 120), (cx + 150, 215)]
        draw.polygon(crown, fill=GOLD, outline=GOLD_LIGHT, width=6)
        for jx in (-100, -45, 0, 45, 100):
            draw.ellipse((cx + jx - 12, 195, cx + jx + 12, 219), fill=(190, 30, 40), outline=GOLD_LIGHT, width=2)
        # Veil of gold chains
        for k in range(-4, 5):
            draw.line([(cx + k * 38, 330), (cx + k * 42, 470)], fill=(212, 175, 55, 140), width=3)
        # Double sigils on the cloak
        draw_eye_in_triangle(draw, cx - 190, 820, 110, 6)
        draw_eye_in_triangle(draw, cx + 190, 820, 110, 6)


def render(n):
    legendary = n == 1
    rnd = random.Random(1000 + n)
    img = radial_background(n, rnd).convert("RGBA")
    # Halo / aura
    aura = glow_layer(img.size, (SIZE / 2, 420), 300 if legendary else 220, (212, 175, 55, 110 if legendary else 60),
                      90)
    img = Image.alpha_composite(img, aura)
    if legendary:
        ring = Image.new("RGBA", img.size, (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring)
        rd.ellipse((SIZE / 2 - 330, 100, SIZE / 2 + 330, 760), outline=(255, 221, 120, 160), width=14)
        rd.ellipse((SIZE / 2 - 360, 70, SIZE / 2 + 360, 790), outline=(212, 175, 55, 90), width=6)
        img = Image.alpha_composite(img, ring.filter(ImageFilter.GaussianBlur(3)))
    # Floating sigil glow
    sig_y = 150 if not legendary else 90
    sig_size = 170 if not legendary else 200
    sig_x = SIZE / 2 + (0 if legendary else [-230, 230, 0, -250, 250][n % 5])
    if not legendary:
        sig_y = [150, 150, 120, 180, 180][n % 5]
    glow = glow_layer(img.size, (sig_x, sig_y), sig_size * 0.75, (255, 200, 80, 120), 40)
    img = Image.alpha_composite(img, glow)
    draw_frog(img, rnd, n, legendary)
    d = ImageDraw.Draw(img, "RGBA")
    draw_eye_in_triangle(d, sig_x, sig_y, sig_size, 12, legendary)
    # Third-eye glow on top
    te = glow_layer(img.size, (SIZE / 2, 300), 70, (255, 221, 120, 150), 25)
    img = Image.alpha_composite(img, te)
    # Plate
    d = ImageDraw.Draw(img, "RGBA")
    label = f"BMC ILLUMINATI PASS  -  GENESIS {n:02d}" + ("  -  LEGENDARY" if legendary else "")
    d.rectangle((0, SIZE - 70, SIZE, SIZE), fill=(0, 0, 0, 170))
    d.line((0, SIZE - 70, SIZE, SIZE - 70), fill=GOLD, width=3)
    d.text((SIZE / 2, SIZE - 36), label, fill=GOLD_LIGHT, anchor="mm")
    return img.convert("RGB")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "genesis")
    os.makedirs(out, exist_ok=True)
    for n in range(1, 78):
        img = render(n)
        assert img.size == (SIZE, SIZE)
        img.save(os.path.join(out, f"genesis-{n:02d}.png"), "PNG", optimize=True)
        print(f"genesis-{n:02d}.png")


if __name__ == "__main__":
    main()
