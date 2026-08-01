#!/usr/bin/env python3
"""Extract code around key endpoint markers from the @movie-web/providers bundle."""
import sys

s = open('/tmp/mwp_index.js').read()

MARKERS = [
    'api.whvx.net',
    'warezcdn.com',
    'upstream.wafflehacker.io',
    'm3u8.justchill.workers.dev',
    'ee3.wafflehacker.io',
    'streamscrape.wafflehacker.io',
    'soaper.live',
]

for m in MARKERS:
    print(f"\n{'='*20} MARKER: {m} {'='*20}")
    idx = s.find(m)
    if idx < 0:
        print("NOT FOUND")
        continue
    print(s[max(0, idx - 2500):idx + 4000])
