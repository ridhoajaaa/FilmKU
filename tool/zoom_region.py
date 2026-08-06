#!/usr/bin/env python3
"""Renders a screenshot region as an ASCII luminance grid (readable without
viewing the image). Usage: python3 zoom_region.py IMG X0 X1 Y0 Y1 [COLS ROWS]"""
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert('RGB')
w, h = im.size
x0 = int(float(sys.argv[2]) * w)
x1 = int(float(sys.argv[3]) * w)
y0 = int(float(sys.argv[4]) * h)
y1 = int(float(sys.argv[5]) * h)
cols = int(sys.argv[6]) if len(sys.argv) > 6 else 72
rows = int(sys.argv[7]) if len(sys.argv) > 7 else 12

chars = ' .:-=+*#%@'
print(f'region x[{x0},{x1}] y[{y0},{y1}] ({x1-x0}x{y1-y0}px)')
for r in range(rows):
    line = ''
    for c in range(cols):
        x = min(w - 1, int(x0 + (x1 - x0) * (c + 0.5) / cols))
        y = min(h - 1, int(y0 + (y1 - y0) * (r + 0.5) / rows))
        R, G, B = im.getpixel((x, y))
        lum = (R * 299 + G * 587 + B * 114) / 1000
        line += chars[min(9, int(lum / 26))]
    print(line)
