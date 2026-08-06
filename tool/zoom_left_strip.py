#!/usr/bin/env python3
"""Zoom into the left vertical strip to identify its content."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size

def ascii_region(box, cols=120, rows=48, label=''):
    region = img.crop(box)
    rw, rh = region.size
    tw, th = rw / cols, rh / rows
    chars = ' .:-=+*#%@'
    print(f'\n--- {label} box={box} ({rw}x{rh}) ---')
    for r in range(rows):
        line = ''
        for c in range(cols):
            b = region.crop((int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th)))
            px = list(b.getdata())
            lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in px) / len(px)
            line += chars[min(int(lum / 256 * len(chars)), len(chars) - 1)]
        print(line)

# The left strip: x 0-520 (cols 0-7 of 40 = 0-20%), y 100-720
ascii_region((0, 100, 520, 720), label='left strip full')
