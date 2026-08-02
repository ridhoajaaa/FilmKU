#!/usr/bin/env python3
"""Verify the iOS liquid-glass shell golden renders and differs from the
classic Android shell.

Reads test/goldens/ios_glass_shell.png (iOS) and android_classic_shell.png
(Android). Both are 390x844 physical px (DPR 1.0 in this Flutter version) for
a 390x844 logical iPhone 14 frame; DPR is auto-detected from image height.

NOTE: the golden renders the shell at the TOP of the home list (unscrolled),
so the band above the capsule is CONTENT, not background — the occlusion
guarantee (content scrolls above the bar thanks to the 110px iOS bottom
padding) is proven by the widget geometry test in test/ios_ui_golden_test.dart,
NOT by pixels here. This script's job is to confirm the capsule is actually
DRAWN and that it visually differs from the classic Android shell.

Checks (logical geometry from the widget-test math):
  - bg   = mean brightness of the pure-background margin (x 0-16, y 640-740)
  - cap  = mean brightness of the capsule band (y 762-834, x 24-366: 72px
           tall, 10px safe-area margin, 24px side padding)
  - aqua = count of #4DE1FF-ish accent pixels in the capsule band
  1. content strip above the capsule (y 700-740, x 24-366) is > 1.5x bg
     (the home list really renders there)
  2. capsule band is brighter than the content strip (a visible glass bar)
  3. capsule band has >= 30 aqua pixels (active pill/icon rendered)
  4. the same band on the Android golden has <= 20 aqua (shells differ)

Exit 0 = PASS, 1 = FAIL. Dev tool, not a CI gate.
Regenerate goldens first: flutter test --update-goldens test/ios_ui_golden_test.dart
"""
import os
import sys
from PIL import Image

IOS = 'test/goldens/ios_glass_shell.png'
ANDROID = 'test/goldens/android_classic_shell.png'
LOGICAL_W, LOGICAL_H = 390.0, 844.0


def load(path):
    return Image.open(path).convert('RGB')


def mean_brightness(img, y0, y1, x0=None, x1=None):
    w, h = img.size
    px = img.load()
    x0, x1 = int(x0 or 0), int(x1 or w)
    y0, y1 = int(y0), min(int(y1), h)
    total = n = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            total += (r + g + b) / 3
            n += 1
    return (total / n) if n else 0.0


def count_aqua_light(img, y0, y1, x0=None, x1=None):
    """Returns (aqua_accent_px, light_px) in the region."""
    w, h = img.size
    px = img.load()
    x0, x1 = int(x0 or 0), int(x1 or w)
    y0, y1 = int(y0), min(int(y1), h)
    aqua = light = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if b > 180 and g > 150 and r < 160 and (b - r) > 60:
                aqua += 1
            elif r > 150 and g > 150 and b > 150:
                light += 1
    return aqua, light


def main():
    for p in (IOS, ANDROID):
        if not os.path.exists(p):
            print(f'FATAL: {p} missing — generate goldens first:\n'
                  '  flutter test --update-goldens test/ios_ui_golden_test.dart')
            return 1

    ios = load(IOS)
    andr = load(ANDROID)
    dpr = ios.size[1] / LOGICAL_H
    print(f'iOS golden:     {ios.size[0]}x{ios.size[1]} px  (DPR {dpr:.2f})')
    print(f'Android golden: {andr.size[0]}x{andr.size[1]} px')

    # Background = pure-scaffold margin left of the content cards (x 0-16).
    bg = mean_brightness(ios, 640 * dpr, 740 * dpr, 0, 16 * dpr)
    content_top, content_bot = 700 * dpr, 740 * dpr    # content above capsule
    cap_top, cap_bot = 762 * dpr, 834 * dpr            # capsule band
    cap_x0, cap_x1 = 24 * dpr, (LOGICAL_W - 24) * dpr

    ios_content = mean_brightness(ios, content_top, content_bot, cap_x0, cap_x1)
    ios_cap = mean_brightness(ios, cap_top, cap_bot, cap_x0, cap_x1)
    ios_aqua, ios_light = count_aqua_light(ios, cap_top, cap_bot, cap_x0, cap_x1)
    andr_aqua, _ = count_aqua_light(andr, cap_top, cap_bot, cap_x0, cap_x1)

    print(f'  background margin mean:                 {bg:.2f}')
    print(f'  content strip above capsule mean:       {ios_content:.2f}')
    print(f'  capsule band mean:                      {ios_cap:.2f}')
    print(f'  capsule band aqua px: {ios_aqua}   light px: {ios_light}')
    print(f'  Android same band aqua px: {andr_aqua}')

    ok = True
    if ios_content <= bg * 1.5:
        print(f'  FAIL: content strip ({ios_content:.2f}) not > 1.5x background '
              f'({bg:.2f}) — the home list may not render')
        ok = False
    if ios_cap <= ios_content:
        print(f'  FAIL: capsule band ({ios_cap:.2f}) not brighter than content '
              f'above ({ios_content:.2f}) — glass bar may not be drawn')
        ok = False
    if ios_aqua < 30:
        print(f'  FAIL: iOS capsule band has too few aqua pixels ({ios_aqua}) '
              f'— active pill/icon may not render')
        ok = False
    if andr_aqua > 20:
        print(f'  FAIL: Android classic shell unexpectedly has aqua '
              f'({andr_aqua} px) — the shells should differ')
        ok = False
    if ok:
        print('PASS: liquid-glass capsule renders over content and differs '
              'from the classic Android shell. (Occlusion is asserted by the '
              'widget geometry test, not pixels.)')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
