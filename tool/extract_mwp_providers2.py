#!/usr/bin/env python3
"""Extract embed-scraper code for the vidbinge/wafflehacker backends from the bundle."""
import sys

s = open('/tmp/mwp_index.js').read()

# Find the "comboEmbed" scrapers that query a provider by id — search for the
# pattern where embeds get resolved (fetch a provider-specific endpoint).
for marker in [
    'scrapeEmbed',
    'embedId',
    'vidbinge.com/embed',
    'm3u8.justchill.workers.dev',
    'warezcdn',
    'upstream.wafflehacker.io',
    'streamscrape.wafflehacker.io',
    'soaper.live',
]:
    print(f"\n{'='*20} MARKER: {marker} {'='*20}")
    idx = s.find(marker)
    if idx < 0:
        print("NOT FOUND")
        continue
    print(s[max(0, idx - 1200):idx + 3500])
