#!/usr/bin/env python3
"""Zoom into specific regions of the player screenshot at higher resolution."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size
print(f'image: {W}x{H}')

def ascii_region(box, cols=100, rows=24, label=''):
    x0, y0, x1, y1 = box
    region = img.crop(box)
    rw, rh = region.size
    tw, th = rw / cols, rh / rows
    chars = ' .:-=+*#%@'
    print(f'\n--- {label}  ({x0},{y0})-({x1},{y1}) size {rw}x{rh} ---')
    for r in range(rows):
        line = ''
        for c in range(cols):
            b = region.crop((int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th)))
            px = list(b.getdata())
            lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in px) / len(px)
            line += chars[min(int(lum / 256 * len(chars)), len(chars) - 1)]
        print(line)

# middle-right cluster (rows 18-19 ascii = y 50-53%, cols 58-77 = x 72-97%)
ascii_region((int(W*0.65), int(H*0.42), W, int(H*0.60)), label='middle-right (suspected controls)')
# bottom band
ascii_region((0, int(H*0.75), W, H), rows=14, label='bottom band')
# top band
ascii_region((0, 0, W, int(H*0.12)), rows=10, label='top band')
# left video strip detail
ascii_region((0, int(H*0.05), int(W*0.25), int(H*0.70)), cols=60, rows=30, label='left strip')
