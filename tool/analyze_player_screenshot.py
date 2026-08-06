#!/usr/bin/env python3
"""Visual analysis of the phone player screenshot (/tmp/phone_player.png).

Renders a coarse ASCII brightness map so the control layout (top/bottom bars
vs a centered cluster) can be "seen", and reports the vertical band where
dense UI elements (buttons/slider) live, plus any bright subtitle-like text
rows in the lower third of the video area.
"""
import sys
from PIL import Image

path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/phone_player.png'
img = Image.open(path).convert('RGB')
W, H = img.size
print(f'image: {W}x{H}')

# ---------- ASCII brightness map ----------
cols, rows = 80, 36
tw, th = W / cols, H / rows
chars = ' .:-=+*#%@'
print(f'\nASCII map ({cols}x{rows}):')
for r in range(rows):
    line = ''
    for c in range(cols):
        box = img.crop((int(c * tw), int(r * th), int((c + 1) * tw), int((r + 1) * th)))
        px = list(box.getdata())
        lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in px) / len(px)
        line += chars[min(int(lum / 256 * len(chars)), len(chars) - 1)]
    print(line)

# ---------- find the control row (dense small bright/dark UI band) ----------
# Controls sit on a dark gradient bar with light icons. Measure per-row mean
# luminance difference vs neighbors to find distinct UI bands (top bar, bottom
# bar, or centered cluster).
print('\nrow luminance profile (every 2% of height):')
small = img.resize((W // 4, H // 4))
sdata = list(small.getdata())
sw, sh = small.size
for r in range(0, sh, max(1, sh // 50)):
    row = sdata[r * sw:(r + 1) * sw]
    lum = sum(0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2] for p in row) / len(row)
    pct = r / sh * 100
    bar = '#' * int(lum / 256 * 40)
    print(f'  y={pct:5.1f}%  lum={lum:6.1f}  {bar}')

# ---------- subtitle text detection (bright text rows in video lower area) ----------
# mpv/libass subtitles render as bright glyphs on the video; look for rows in
# the lower-middle band with HIGH local contrast (bright pixels near dark).
gray = img.convert('L')
gdata = list(gray.getdata())
print('\nsubtitle-ish bright-text rows (lower 45% of frame):')
for r in range(int(H * 0.55), int(H * 0.95), max(1, H // 100)):
    row = gdata[r * W:(r + 1) * W]
    bright = sum(1 for v in row if v > 200)
    pct = r / H * 100
    if bright > 20:
        print(f'  y={pct:5.1f}%  bright_px={bright}')
