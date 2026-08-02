#!/usr/bin/env python3
"""Scan a grim screenshot of the live Linux run (FILMKU_FORCE_IOS_UI) for the
iOS liquid-glass capsule.

The capsule's active pill/icon is electric aqua #4DE1FF. If the iOS glass UI
rendered in the real running app, a horizontal band of aqua pixels should
appear in the bottom portion of the app window. This scans the WHOLE
screenshot's bottom half (the window position on the desktop is unknown), so
it works regardless of where the window landed.

Usage: python3 tool/check_live_ios_screenshot.py <screenshot.png>
Exit 0 = capsule detected, 1 = not detected.
"""
import sys
from PIL import Image


def main() -> int:
    path = sys.argv[1]
    img = Image.open(path).convert('RGB')
    w, h = img.size
    px = img.load()
    print(f'screenshot: {w}x{h}')

    # Rows in the bottom half that contain aqua accent pixels (#4DE1FF-ish).
    aqua_rows = []
    for y in range(int(h * 0.5), h):
        row_aqua = 0
        for x in range(w):
            r, g, b = px[x, y]
            if b > 180 and g > 150 and r < 160 and (b - r) > 60:
                row_aqua += 1
        if row_aqua:
            aqua_rows.append((y, row_aqua))

    total = sum(c for _, c in aqua_rows)
    print(f'bottom-half aqua px: {total}')

    if not aqua_rows:
        print('NO_CAPSULE_DETECTED')
        return 1

    ys = [y for y, _ in aqua_rows]
    span = max(ys) - min(ys)
    print(f'aqua y-range: {min(ys)}..{max(ys)} (span {span}px)')
    # A capsule is a compact band (tens of px tall), not scattered pixels.
    if span < 400 and total > 30:
        print('CAPSULE_DETECTED')
        return 0
    print('NO_CAPSULE_DETECTED (aqua scattered or too sparse)')
    return 1


if __name__ == '__main__':
    sys.exit(main())
