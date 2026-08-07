#!/usr/bin/env python3
"""Simulate SubtitleDatasource._searchSubtitleCat against the live site."""
import re
import sys
import urllib.request
import urllib.parse

UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
BASE = "https://subtitlecat.com"

SC_SLUG = re.compile(r'href="(subs/\d+/[^"]+\.html)"', re.I)
SC_SRT = re.compile(r'href="(/subs/\d+/[^"]+\.srt)"', re.I)
SC_LANG = re.compile(r'-([a-z]{2}(?:-[a-z0-9]{2,3})?)\.srt$', re.I)


def fetch(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,*/*;q=0.8"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def main():
    query = sys.argv[1] if len(sys.argv) > 1 else "Supergirl 1984"
    url = f"{BASE}/index.php?search={urllib.parse.quote(query)}"
    print(f"=== SEARCH: {query} ===")
    search_html = fetch(url)
    slugs = []
    for m in SC_SLUG.finditer(search_html):
        s = m.group(1)
        if s not in slugs:
            slugs.append(s)
    print(f"total slugs: {len(slugs)}")
    for i, s in enumerate(slugs[:12], 1):
        print(f"  {i}. {urllib.parse.unquote(s)}")

    print("\n=== SIMULATE PARSER: first 8 slugs ===")
    found_any = False
    for idx, slug in enumerate(slugs[:8], 1):
        try:
            detail = fetch(f"{BASE}/{slug}")
        except Exception as e:
            print(f"  [{idx}] {urllib.parse.unquote(slug)[:60]} -> FETCH FAIL {e}")
            continue
        links = []
        for m in SC_SRT.finditer(detail):
            path = m.group(1)
            if path not in [l[0] for l in links]:
                lang = SC_LANG.search(path)
                links.append((path, lang.group(1).lower() if lang else "xx"))
        langs = sorted({l for _, l in links})
        print(f"  [{idx}] {urllib.parse.unquote(slug)[:55]:55} -> {len(links)} srt, langs={langs}")
        if links:
            found_any = True
        if "id" in langs:
            print(f"        >>> INDONESIAN FOUND on slug #{idx}!!")
            # download the id srt to prove it works
            id_path = next(p for p, l in links if l == "id")
            try:
                srt = fetch(f"{BASE}{id_path}")
                head = srt.strip()[:80]
                ok = not head.lower().startswith("<!doctype") and not head.lower().startswith("<html")
                print(f"        >>> id.srt downloaded: {len(srt)} bytes, looks-like-srt={ok}")
                print(f"        >>> head: {head!r}")
            except Exception as e:
                print(f"        >>> id.srt download FAIL: {e}")
            break
    if not found_any:
        print("\nNO srt links found on any of the first 8 slugs")


if __name__ == "__main__":
    main()
