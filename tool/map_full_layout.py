#!/usr/bin/env python3
"""Definitive layout map of the player screenshot (40x20 cells)."""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size
cols, rows = 40, 20
tw, th = W / cols, H / rows
print(f'{W}x{H}  legend: . = black  - = dark  v = video  U = UI  T = bright text')

for r in range(rows):
    line = ''
    for c in range(cols):
        box = (int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th))
        region = img.crop(box)
        px = list(region.getdata())
        n = len(px)
        lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in px) / n
        bright = sum(1 for p in px if p[0] > 180 and p[1] > 180 and p[2] > 180)
        colored = sum(1 for p in px if max(p) - min(p) > 40)
        if lum < 6:
            ch = '.'
        elif lum < 22:
            ch = '-'
        elif colored > n * 0.4:
            ch = 'v'  # saturated = video
        elif bright > n * 0.15:
            ch = 'T'  # bright text/white UI
        else:
            ch = 'U'
        line += ch
    print(f'{line}   y={r*100//rows}-{(r+1)*100//rows}%')
