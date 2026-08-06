#!/usr/bin/env python3
"""Classifies a screenshot as HOME vs PLAYER by sampling key regions.

Player signature (MpvControlsOverlay, landscape):
  - top ~8%: thin bar with small icons/text
  - bottom ~8%: control bar with small white icons + slider
  - middle: mostly dark video content (no dense text rows)
Home signature:
  - dense UI/text across the upper half (posters, titles, carousels)
  - bottom nav bar
"""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
print('size', im.size)

def lum_region(x0, y0, x1, y1):
    """Average luminance + fraction of near-black and near-white pixels."""
    xs = max(1, int((x1 - x0) / 8))
    ys = max(1, int((y1 - y0) / 8))
    total = 0.0
    black = white = 0
    n = 0
    for i in range(8):
        for j in range(8):
            x = min(w - 1, int(x0 + (x1 - x0) * (i + 0.5) / 8))
            y = min(h - 1, int(y0 + (y1 - y0) * (j + 0.5) / 8))
            r, g, b = im.getpixel((x, y))
            lum = (r + g + b) / 3
            total += lum
            if lum < 25:
                black += 1
            if lum > 200:
                white += 1
            n += 1
    return total / n, black / n, white / n

regions = {
    'top_bar   (0-8%)': (0, 0, w, int(h * 0.08)),
    'upper_mid (20-45%)': (0, int(h * 0.20), w, int(h * 0.45)),
    'center    (40-60%)': (0, int(h * 0.40), w, int(h * 0.60)),
    'lower_mid (60-85%)': (0, int(h * 0.60), w, int(h * 0.85)),
    'bottom    (88-100%)': (0, int(h * 0.88), w, h),
}
for name, (x0, y0, x1, y1) in regions.items():
    avg, black, white = lum_region(x0, y0, x1, y1)
    print(f'{name}: avgLum={avg:6.1f} black={black:4.0%} white={white:4.0%}')

# Bottom bar scan: find the lowest band with >8% bright pixels (controls).
print()
print('vertical bright profile (y band -> %bright pixels):')
bright = []
for band in range(20):
    y0 = int(h * band / 20)
    y1 = int(h * (band + 1) / 20)
    count = 0
    n = 0
    for i in range(40):
        for j in range(6):
            x = int(w * (i + 0.5) / 40)
            y = int(y0 + (y1 - y0) * (j + 0.5) / 6)
            r, g, b = im.getpixel((x, y))
            if (r + g + b) / 3 > 150:
                count += 1
            n += 1
    pct = count / n * 100
    bright.append(pct)
    if pct > 2:
        print(f'  y={band*5:3d}-{(band+1)*5:3d}%: {pct:5.1f}% bright')

# Lowest band with significant content = where the bottom bar sits.
for i in range(19, -1, -1):
    if bright[i] > 2:
        print(f'-> lowest content band: y={i*5}%-{(i+1)*5}% (bar bottom edge ~{(i+1)*5}%)')
        break
