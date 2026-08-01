#!/usr/bin/env python3
"""Probe: can Referer/Origin/UA headers unlock a native (non-browser) fetch of
the VidLink signed .mp4?

The app's headless WebView extracts the signed URL, but the native ExoPlayer
(video_player) fetches it without browser context and gets rejected. This
script re-extracts a fresh signed URL from vidlink.pro with headless chromium,
then fetches it with different header combinations to see which (if any) the
CDN accepts (HTTP 200 vs 403/502).
"""
import html
import re
import subprocess
import urllib.error
import urllib.request

html_unescape = html.unescape

CHROME = "/usr/bin/chromium"
MID = "969681"  # trending movie id (verified reachable)
UA = (
    "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)


def extract_signed_url() -> str:
    """Load vidlink.pro in headless chromium and find a signed media URL."""
    cmd = [
        CHROME,
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--virtual-time-budget=35000",
        "--user-agent=" + UA,
        "--dump-dom",
        f"https://vidlink.pro/movie/{MID}",
    ]
    proc = subprocess.run(
        cmd, capture_output=True, text=True, timeout=75, check=False
    )
    html = proc.stdout
    print(f"[1] DOM size: {len(html)} bytes (exit={proc.returncode})")
    pats = [
        r"https?://[^\s<>]+?\.mp4[^\s<>]*",
        r"https?://[^\s<>]+?\.m3u8[^\s<>]*",
    ]
    found = set()
    for pat in pats:
        for u in re.findall(pat, html, re.I):
            u = u.strip(chr(34) + chr(39) + ",.;)")
            # chromium serializes the DOM with HTML entities; the app decodes
            # them before playing, so the probe must too (a literal `&amp;`
            # in the signature is exactly the 502-class bug already fixed).
            u = html_unescape(u)
            if u.startswith("http"):
                found.add(u)
    urls = sorted(found)
    print(f"[1] candidate URLs found: {len(urls)}")
    for u in urls[:5]:
        print(f"      {u}")
    return urls[0] if urls else ""


def probe(url: str, name: str, headers: dict) -> str:
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            data = resp.read(512)
            ctype = resp.headers.get("Content-Type", "?")
            return f"{name}: HTTP {resp.status} [{ctype}] first_bytes={data[:12]!r}"
    except urllib.error.HTTPError as e:
        return f"{name}: HTTP {e.code} ({e.reason})"
    except Exception as e:  # noqa: BLE001
        return f"{name}: ERR {type(e).__name__}: {e}"


def main() -> None:
    url = extract_signed_url()
    if not url:
        print("[2] NO signed URL extracted — cannot probe headers.")
        return

    combos = [
        ("no-headers", {}),
        ("referer", {"Referer": "https://vidlink.pro/"}),
        (
            "referer+origin",
            {"Referer": "https://vidlink.pro/", "Origin": "https://vidlink.pro"},
        ),
        (
            "referer+origin+ua",
            {
                "Referer": "https://vidlink.pro/",
                "Origin": "https://vidlink.pro",
                "User-Agent": UA,
            },
        ),
        (
            "full-browser",
            {
                "Referer": "https://vidlink.pro/movie/" + MID,
                "Origin": "https://vidlink.pro",
                "User-Agent": UA,
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9",
                "Sec-Fetch-Dest": "video",
                "Sec-Fetch-Mode": "no-cors",
                "Sec-Fetch-Site": "cross-site",
            },
        ),
    ]
    print("\n[2] header experiment:")
    for name, headers in combos:
        print("     " + probe(url, name, headers))


if __name__ == "__main__":
    main()
