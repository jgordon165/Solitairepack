#!/usr/bin/env python3
"""Draws Solitairepack's icon and writes it out.

An original drawing in the spirit of the Windows 3.1 Solitaire icon: a
face-up card peeking out behind a card back in a grey frame. It adds the
later Windows card games' touches: a spider web on the back, in the
blue-green of the Spider table, and a spider hanging from a thread.

Every size is drawn on its own pixel grid (edges land on whole pixels, so
the small sizes stay sharp) at 8x, then averaged down. Writes:

    res/solitairepack.ico      16, 20, 24, 32, 40, 48, 64, 128 and 256 px
    res/solitairepack.png      256 px, for the README
    src/icon_rgba.h            48 px RGBA, for SDL_SetWindowIcon

Run from the repository root:  python3 tools/make_icon.py
Needs Pillow.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

SIZES = [256, 128, 64, 48, 40, 32, 24, 20, 16]
SS = 8  # supersampling

NAVY = (0, 0, 128, 255)
TEAL = (0, 112, 104, 255)       # the Spider table (scripts/game/cards.lua)
WEB = (96, 200, 190, 255)
FRAME = (64, 64, 64, 255)
FRAME_HI = (160, 160, 160, 255)
WHITE = (255, 255, 255, 255)
PAPER = (232, 232, 232, 255)
RED = (192, 0, 0, 255)
BLACK = (0, 0, 0, 255)
SHADOW = (0, 0, 0, 70)


def draw_icon(n):
    """The icon at n x n pixels."""
    S = n * SS
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = n / 32.0  # one unit of the 32 px design, in output pixels

    def px(v):
        """A design coordinate, snapped to the output pixel grid, at 8x."""
        return round(v * u) * SS

    def rect(x0, y0, x1, y1, fill, r=0.0, outline=None, w=0.0):
        box = [px(x0), px(y0), px(x1) - 1, px(y1) - 1]
        rad = max(0, round(r * u * SS))
        width = max(SS, round(w * u) * SS) if outline else 0
        d.rounded_rectangle(box, rad, fill=fill, outline=outline, width=width)

    small = n <= 24
    edge = max(1, round(0.6 * u)) / u  # the frame: whole pixels, about 0.6 units

    # Card shadow, down-right.
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    off = max(1, round(1.5 * u)) * SS
    for (x0, y0, x1, y1) in [(11, 2, 26, 22), (5, 9, 20, 30)]:
        sd.rounded_rectangle([px(x0) + off, px(y0) + off, px(x1) + off - 1, px(y1) + off - 1],
                             round(2 * u * SS), fill=SHADOW)
    img.alpha_composite(sh)

    # The face-up card behind: a frame, white paper and two red hearts.
    rect(11, 2, 26, 22, FRAME, r=2)
    rect(11 + edge, 2 + edge, 26 - edge, 22 - edge, WHITE, r=1.5)
    for cx in (14.5, 19.8):
        heart(d, cx * u * SS, 6.0 * u * SS, (2.6 if not small else 3.2) * u * SS, RED)

    # The card back in front: a frame with a light inner edge, then the back.
    rect(5, 9, 20, 30, FRAME, r=2)
    rect(5 + edge, 9 + edge, 20 - edge, 30 - edge, FRAME_HI, r=1.5)
    bx0, by0, bx1, by1 = 5 + 2 * edge, 9 + 2 * edge, 20 - 2 * edge, 30 - 2 * edge
    rect(bx0, by0, bx1, by1, NAVY)
    # The web, from the back's top-left corner, in the Spider blue-green.
    web(d, px(bx0), px(by0), px(bx1), px(by1), n)

    # The spider, hanging on its thread at the right.
    spider(d, 23.5 * u * SS, 12.5 * u * SS, u * SS, n)

    return img.resize((n, n), Image.BOX)


def heart(d, cx, cy, size, fill):
    r = size * 0.30
    d.ellipse([cx - 2 * r, cy - r * 1.4, cx, cy + r * 0.6], fill=fill)
    d.ellipse([cx, cy - r * 1.4, cx + 2 * r, cy + r * 0.6], fill=fill)
    d.polygon([(cx - 2 * r + r * 0.1, cy - r * 0.1), (cx + 2 * r - r * 0.1, cy - r * 0.1),
               (cx, cy + size * 0.62)], fill=fill)


def web(d, x0, y0, x1, y1, n):
    """The back: navy with a blue-green glow, and a quarter web from its
    top-left corner (from 32 px up; smaller, just a blue-green border)."""
    w, h = x1 - x0 + 1, y1 - y0 + 1
    base = Image.new("RGBA", (w, h), NAVY)
    # A blue-green glow, strongest in the far corner.
    wash = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wash)
    reach = math.hypot(w, h)
    for i in range(32):
        t = i / 31
        r = reach * (1.0 - t)
        wd.ellipse([w - r, h - r, w + r, h + r], fill=TEAL[:3] + (int(170 * t ** 1.2),))
    base.alpha_composite(wash)
    ld = ImageDraw.Draw(base)
    if n < 32:
        b = SS
        ld.rectangle([b, b, w - 1 - b, h - 1 - b], outline=WEB, width=SS)
    else:
        line = max(SS, round(SS * n / 80))
        spokes = 5
        angles = [math.pi / 2 * i / (spokes - 1) for i in range(spokes)]
        for a in angles:
            ld.line([(0, 0), (math.cos(a) * reach, math.sin(a) * reach)], fill=WEB, width=line)
        for k, f in enumerate([0.22, 0.42, 0.64, 0.88]):
            r = reach * f
            pts = []
            for a0, a1 in zip(angles, angles[1:]):
                # Each strand sags towards the corner between two spokes.
                for j in range(9):
                    t = j / 8
                    a = a0 + (a1 - a0) * t
                    sag = 1.0 - 0.10 * math.sin(math.pi * t)
                    pts.append((math.cos(a) * r * sag, math.sin(a) * r * sag))
            ld.line(pts, fill=WEB, width=line, joint="curve")
    d._image.paste(base, (x0, y0))


TEAL_LIGHT = (40, 170, 160, 255)


def spider(d, cx, top, u, n):
    """A small black spider hanging on its thread; u is one design unit."""
    thread = SS if n < 64 else max(SS, round(u / 4))
    body_r = 1.9 * u
    head_r = 1.15 * u
    cy = top + body_r  # the abdomen's centre
    hy = cy - body_r - head_r * 0.6
    d.line([(cx, 0), (cx, hy)], fill=(48, 48, 48, 255), width=thread)
    if n <= 20:
        # At the smallest sizes: a body and four leg pixels a side.
        p = SS  # one output pixel
        x, y = round(cx / p) * p, round(cy / p) * p
        d.rectangle([x - p, y - p, x + p - 1, y + p - 1], fill=BLACK)       # 2x2 body
        for lx, ly in [(-2, -2), (1, -2), (-2, 1), (1, 1)]:                  # legs
            d.rectangle([x + lx * p, y + ly * p, x + (lx + 1) * p - 1, y + (ly + 1) * p - 1], fill=BLACK)
        return
    leg = SS if n < 48 else max(SS, round(u * 0.4))
    for side in (-1, 1):
        for i, (ang, bend) in enumerate([(-60, -100), (-25, -60), (10, 70), (40, 100)]):
            a, b = math.radians(ang), math.radians(bend)
            hip = (cx, cy - body_r * 0.5)
            knee = (hip[0] + side * math.cos(a) * 2.5 * u, hip[1] + math.sin(a) * 2.5 * u)
            foot = (knee[0] + side * abs(math.cos(b)) * 1.2 * u, knee[1] + math.sin(b) * 1.8 * u)
            d.line([hip, knee, foot], fill=BLACK, width=leg, joint="curve")
    d.ellipse([cx - head_r, hy - head_r, cx + head_r, hy + head_r], fill=BLACK)
    d.ellipse([cx - body_r, cy - body_r, cx + body_r, cy + body_r], fill=BLACK)
    if n >= 48:
        d.ellipse([cx - 0.75 * u, cy - 0.9 * u, cx - 0.1 * u, cy - 0.25 * u], fill=(110, 110, 110, 255))


def write_header(img, path):
    w, h = img.size
    data = img.tobytes()
    lines = [
        "// Generated by tools/make_icon.py: the window icon, %dx%d RGBA." % (w, h),
        "#pragma once",
        "",
        "namespace icon {",
        "constexpr int kWidth = %d;" % w,
        "constexpr int kHeight = %d;" % h,
        "constexpr unsigned char kRGBA[] = {",
    ]
    for i in range(0, len(data), 16):
        lines.append("    " + ", ".join("0x%02x" % b for b in data[i:i + 16]) + ",")
    lines += ["};", "}  // namespace icon", ""]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(os.path.join(root, "res"), exist_ok=True)
    imgs = {n: draw_icon(n) for n in SIZES}
    big = imgs[256]
    big.save(os.path.join(root, "res", "solitairepack.ico"), sizes=[(n, n) for n in SIZES],
             append_images=[imgs[n] for n in SIZES[1:]])
    big.save(os.path.join(root, "res", "solitairepack.png"))
    write_header(imgs[48], os.path.join(root, "src", "icon_rgba.h"))
    # A contact sheet for checking the sizes by eye (not committed).
    sheet = Image.new("RGBA", (sum(SIZES) + 10 * len(SIZES) + 10, 266), (0, 112, 104, 255))
    x = 10
    for n in SIZES:
        sheet.alpha_composite(imgs[n], (x, 5))
        x += n + 10
    sheet.save(os.path.join(os.environ.get("TMPDIR", "/tmp"), "icon_sheet.png"))


if __name__ == "__main__":
    main()
