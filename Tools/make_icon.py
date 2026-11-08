#!/usr/bin/env python3
"""Generate the 1024x1024 app icon (Woop) with Pillow.

Dark WHOOP-like background, three score arcs (sleep / recovery / strain colours)
and a thin geometric "W" in the middle. No third-party artwork is used.

Usage: python3 Tools/make_icon.py Woop/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling factor for smooth edges
S = SIZE * SS


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def main(out_path: str) -> None:
    img = Image.new("RGB", (S, S), (0, 0, 0))
    px = img.load()
    top, bottom = (44, 51, 59), (11, 13, 16)
    for y in range(S):
        c = lerp(top, bottom, y / (S - 1))
        for x in range(S):
            px[x, y] = c

    d = ImageDraw.Draw(img)
    cx, cy = S // 2, S // 2

    # Three concentric arcs: sleep (blue-grey), recovery (green), strain (blue).
    arcs = [
        (0.40, (128, 151, 176), 205, 495),
        (0.33, (22, 236, 6), 150, 420),
        (0.26, (0, 147, 231), 240, 520),
    ]
    width = int(0.035 * S)
    for radius_f, colour, start, end in arcs:
        r = int(radius_f * S)
        box = (cx - r, cy - r, cx + r, cy + r)
        # faint track
        d.arc(box, 0, 360, fill=(40, 46, 53), width=width)
        d.arc(box, start, end, fill=colour, width=width)

    # Thin geometric W.
    w_half = int(0.15 * S)
    h_half = int(0.085 * S)
    pts = [
        (cx - w_half, cy - h_half),
        (cx - int(w_half * 0.5), cy + h_half),
        (cx, cy - int(h_half * 0.35)),
        (cx + int(w_half * 0.5), cy + h_half),
        (cx + w_half, cy - h_half),
    ]
    d.line(pts, fill=(245, 247, 250), width=int(0.022 * S), joint="curve")

    img = img.filter(ImageFilter.GaussianBlur(radius=SS * 0.3))
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(out_path, "PNG")
    print("wrote", out_path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png")
