#!/usr/bin/env python3
"""Read the controls cluster at high resolution."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size

def ascii_region(box, cols=220, rows=30, label=''):
    region = img.crop(box)
    rw, rh = region.size
    tw, th = rw / cols, rh / rows
    chars = ' .:-=+*#%@'
    print(f'\n--- {label} box={box} ---')
    for r in range(rows):
        line = ''
        for c in range(cols):
            b = region.crop((int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th)))
            px = list(b.getdata())
            lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in px) / len(px)
            line += chars[min(int(lum / 256 * len(chars)), len(chars) - 1)]
        print(line)

# The controls cluster region (from earlier: x 65-100%, y 42-62%)
ascii_region((int(W * 0.60), int(H * 0.40), W, int(H * 0.68)), label='controls cluster hi-res')

# The video strip at the left, hi-res
ascii_region((0, int(H * 0.08), int(W * 0.30), int(H * 0.70)), cols=160, rows=30, label='left video strip hi-res')
