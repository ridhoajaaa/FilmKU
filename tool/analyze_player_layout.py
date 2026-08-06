#!/usr/bin/env python3
"""Exact layout facts from the player screenshot."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size
print(f'image: {W}x{H}  (aspect {W/H:.3f})')

gray = img.convert('L')
gdata = list(gray.getdata())

# ---- 1. video content bounding box (pixels that are NOT near-black) ----
min_x, max_x, min_y, max_y = W, -1, H, -1
for y in range(0, H, 2):
    for x in range(0, W, 2):
        v = gdata[y * W + x]
        if v > 18:
            if x < min_x: min_x = x
            if x > max_x: max_x = x
            if y < min_y: min_y = y
            if y > max_y: max_y = y
print(f'content bbox: x=[{min_x},{max_x}]  y=[{min_y},{max_y}]  '
      f'({(max_x-min_x+1)}x{(max_y-min_y+1)}, aspect {(max_x-min_x+1)/(max_y-min_y+1):.3f})')

# ---- 2. row-wise density of bright UI elements (excluding video content) ----
# Video is the large bright area on the left; UI elements are small clusters.
# Report per-10%-height band: count of pixels >120 and >200 in the RIGHT half.
print('\nright-half (x>50%) pixel density per 10% height band:')
for band in range(10):
    y0, y1 = int(H * band / 10), int(H * (band + 1) / 10)
    bright = darkui = 0
    for y in range(y0, y1, 2):
        for x in range(W // 2, W, 2):
            v = gdata[y * W + x]
            if v > 120: bright += 1
            if 200 > v > 60: darkui += 1
    print(f'  y {band*10}-{(band+1)*10}%: bright>120={bright:5d}  mid(60-200)={darkui:5d}')

# ---- 3. bottom band (bottom 30%) — any UI at all? ----
bottom = sum(1 for y in range(int(H * 0.70), H, 2) for x in range(0, W, 2)
             if gdata[y * W + x] > 60)
print(f'\nbottom 30% pixels >60: {bottom}')

# ---- 4. subtitle check: bright text in the lower-middle of the VIDEO ----
print('\nbright-text scan over video bbox lower area:')
for frac in [0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85]:
    y = int(min_y + (max_y - min_y) * frac)
    row = gdata[y * W:(y + 1) * W]
    bright = sum(1 for v in row if v > 200)
    print(f'  y={y} ({frac:.0%} of video): bright_px={bright}')
