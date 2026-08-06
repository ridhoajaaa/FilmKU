#!/usr/bin/env python3
"""12x8 luminance grid of the player screenshot — coarse visual layout."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('L')
W, H = img.size
cols, rows = 12, 8
tw, th = W / cols, H / rows
chars = ' .:-=+*#%@'
print(f'{W}x{H}')
for r in range(rows):
    line = ''
    for c in range(cols):
        box = (int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th))
        region = img.crop(box)
        px = list(region.getdata())
        lum = sum(px) / len(px)
        line += chars[min(int(lum / 256 * len(chars)), len(chars) - 1)]
    print(f'{line}   y={r*100//rows}-{(r+1)*100//rows}%')
