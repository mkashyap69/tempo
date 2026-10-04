"""Renders the Tempo mark (the Downbeat) into every platform icon and
launch asset. Run from the repo root: python3 tools/brand/make_icons.py
Needs Pillow. Geometry is the design's 48-unit grid."""
import glob
import json
import os

from PIL import Image, ImageDraw

BG = (10, 11, 13, 255)  # #0A0B0D
INK = (243, 242, 239, 255)  # #F3F2EF
RECTS = [(5.5, 8, 5.5, 32), (16, 27, 5.5, 13), (26.5, 27, 5.5, 13), (37, 27, 5.5, 13)]
APP = "app"


def mark(size, mark_frac, bg=BG, ink=INK, radius_frac=0.0, opacities=(1, 1, 1, 1)):
    s = 4  # supersample
    w = size * s
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg is not None:
        d.rounded_rectangle([0, 0, w - 1, w - 1], radius=int(w * radius_frac), fill=bg)
    m = w * mark_frac
    off = (w - m) / 2
    k = m / 48
    for (x, y, rw, rh), o in zip(RECTS, opacities):
        col = ink[:3] + (int(ink[3] * o),)
        d.rounded_rectangle([off + x * k, off + y * k, off + (x + rw) * k, off + (y + rh) * k], radius=2.75 * k, fill=col)
    return img.resize((size, size), Image.LANCZOS)


def ios():
    base = f"{APP}/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for f in glob.glob(f"{base}/*.png"):
        n = Image.open(f).size[0]
        # iOS masks the corners itself; draw full-bleed.
        mark(n, 100 / 180).convert("RGB").save(f)
    launch = f"{APP}/ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for f, scale in [("LaunchImage.png", 1), ("LaunchImage@2x.png", 2), ("LaunchImage@3x.png", 3)]:
        mark(72 * scale, 1.0, bg=None).save(f"{launch}/{f}")


def android():
    res = f"{APP}/android/app/src/main/res"
    for f in glob.glob(f"{res}/mipmap-*/ic_launcher.png"):
        n = Image.open(f).size[0]
        mark(n, 0.56, radius_frac=0.22).save(f)


if __name__ == "__main__":
    ios()
    android()
    print("icons written")
