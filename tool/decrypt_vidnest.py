#!/usr/bin/env python3
"""
decrypt_vidnest.py — reverse-engineer the VidNest response cipher.

new.vidnest.fun/{server}/movie/{tmdb} returns {"data":"<encoded>","encrypted":true}.
The decoder lives in vidnest.fun chunk 9bd6e41ec62ebb62.js:

  - a(idx, key): array[idx-180] -> base64 decode -> RC4(key)
  - n(idx):      array[idx-180] -> base64 decode
  - an anti-tamper loop rotates the string array until a checksum == 566921
  - the payload is then decoded with a CUSTOM-ALPHABET base64 (the alphabet is
    passed as the second argument to the inner decoder)

This script (1) decodes the string array, (2) resolves the rotation, (3) prints
the de-obfuscated decoder logic names, and (4) decodes a real payload if given
on argv[1].
"""
import base64
import json
import sys
import urllib.request

ARRAY = [
    "WO/dHmk2FZfZ", "De9VAgm", "zfq0bSoA", "zvnpAMW", "FejRW7fL", "qMLmreq",
    "odm3nZq3oxLrz1rZvG", "ntqXnM5wBgz0uW", "v2HAEwO", "EmohW700qa",
    "ndHvyMvdz1q", "mZuWotK0ohrgDNDhDG", "f8kGW47cHqq", "jLVdSmowbG",
    "WO3cLmoJWOBcGmkuW6j6umo7W4XO", "EeTcBNq", "nJG3nJi1s29YB0HQ",
    "W6pcIYKsAcW", "D8kiECkyoSkjBCoHjCo9u8o3W4W", "W5hcG8oOja",
    "WPpdO8kaASoJ", "WRxdL3Xeoh4cpd4NWQBcJZO", "mZqWowTmtMzNtG",
    "mtqZAuHMqw5f", "A8oCbSoGcW", "WPldGSkRDCkbuHJdIMFdHa", "gmoGWRfMWRe",
    "hXjlW4DeqKZdJW", "uCoCWPddNvxcKCkqqmkRlSkwWPa", "WQ3cPmkQuSkl",
    "ChvZAa", "W5FcOwtdLmkdANtcNsTzWQ7cO8k3", "wfPWqKS", "zLvMEwC",
    "ndH6t0TwELa", "W558cmo7W41kFuy", "WRddUKz1W7K", "WOtdM8kmW6ddPa",
    "EbGOaq", "BgvUz3rO", "W53cOghdNmoDdGBcMHrb", "WO/cVeWWCSkKaf99",
    "D0DfAgS", "WRKYW6i3WOi", "uIuPWQnu", "EMPPquC", "WQhcNmkXiq",
    "otq1mwDqsNn5BG", "WQhdImkuxae",
]

# Every a()/n() call site found in the chunk: (index, key) for a(), (index,) for n()
A_CALLS = {
    181: ("tp2w", 1), 188: ("nT)b", 8), 221: ("Xd@@", 41), 201: ("kmnX", 21),
    200: ("kmnX", 20), 214: ("(y1g", 34), 227: ("TITv", 47), 189: ("Am%5", 9),
    213: ("%uFo", 33), 203: ("hwmV", 23), 195: ("7fJ)", 15), 218: (")(sX", 38),
    198: ("kjAj", 18), 220: ("8b52", 40), 225: ("7t&b", 45), 196: ("nzRa", 16),
    205: ("$jj$", 25), 190: ("A)U2", 10), 210: ("dvmo", 30), 192: ("znLE", 12),
    228: ("$jj$", 48), 222: (")(sX", 42), 180: ("%uFo", 0), 193: ("da@z", 13),
}
N_CALLS = {
    185: (-93, 5), 184: (224, 4), 216: (-60, 36), 194: (-50, 14), 191: (242, 11),
    206: (268, 26), 209: (-55, 29), 202: (-44, 22), 204: (-26, 24), 197: (-44, 17),
    212: (139, 32), 217: (117, 37), 211: (127, 31), 223: (-705, 43), 208: (-752, 28),
    207: (-760, 27),
}


def rc4(data: bytes, key: str) -> bytes:
    s = list(range(256))
    a = 0
    for i in range(256):
        a = (a + s[i] + ord(key[i % len(key)])) % 256
        s[i], s[a] = s[a], s[i]
    r = 0
    a = 0
    out = bytearray()
    for byte in data:
        r = (r + 1) % 256
        a = (a + s[r]) % 256
        s[r], s[a] = s[a], s[r]
        out.append(byte ^ s[(s[r] + s[a]) % 256])
    return bytes(out)


JS_ATOB_ALPHABET = (
    "abcdefghijklmnopqrstuvwxyz"  # NOTE: lowercase FIRST in the JS atob
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/="
)


def b64decode_pad(s: str) -> bytes:
    """Replicates the JS custom atob: lowercase-first alphabet."""
    while len(s) % 4 != 0:
        s += "="
    lookup = {c: i for i, c in enumerate(JS_ATOB_ALPHABET)}
    out = bytearray()
    vals = []
    for c in s:
        vals.append(lookup.get(c, -1))
    i = 0
    while i + 4 <= len(vals):
        a, b, c, d = vals[i:i + 4]
        if a < 0 or b < 0:
            break
        out.append((a << 2) | (b >> 4))
        if c >= 0:
            out.append(((b & 15) << 4) | (c >> 2))
            if d >= 0:
                out.append(((c & 3) << 6) | d)
        i += 4
    return bytes(out)


def get_a(arr, idx, key):
    return rc4(b64decode_pad(arr[idx - 180]), key).decode("utf-8", "replace")


def get_n(arr, idx):
    return b64decode_pad(arr[idx - 180]).decode("utf-8", "replace")


def js_parse_int(s: str):
    """Mimics JS parseInt(s): 0x-prefixed -> hex, else decimal."""
    s = s.strip()
    try:
        if s[:2] in ("0x", "0X"):
            return int(s, 16)
        return int(s, 10)
    except ValueError:
        return float("nan")


def checksum(arr):
    # mimics the anti-tamper loop condition
    a1 = js_parse_int(get_a(arr, 192, "znLE"))  # /1
    a2 = js_parse_int(get_a(arr, 228, "$jj$"))  # /-2
    a3 = js_parse_int(get_a(arr, 222, ")(sX"))  # /-3
    n4 = js_parse_int(get_n(arr, 212))          # /-4
    n5 = js_parse_int(get_n(arr, 217))          # /5
    n6 = js_parse_int(get_n(arr, 211))          # /6
    n7 = js_parse_int(get_n(arr, 223))          # /-7
    n8 = js_parse_int(get_n(arr, 208))          # /-8
    n9 = js_parse_int(get_n(arr, 207))          # /9
    a10 = js_parse_int(get_a(arr, 180, "%uFo"))  # /10
    a11 = js_parse_int(get_a(arr, 193, "da@z"))  # /11
    return (
        a1 / 1 * (-a2 / 2)
        + -a3 / 3
        + -n4 / 4
        + n5 / 5 * (n6 / 6)
        + -n7 / 7 * (-n8 / 8)
        + n9 / 9
        + a10 / 10 * (a11 / 11)
    )


def main():
    arr = list(ARRAY)
    target = 566921
    for _ in range(len(arr)):
        try:
            if abs(checksum(arr) - target) < 1e-9:
                break
        except Exception:
            pass
        arr.append(arr.pop(0))  # r.push(r.shift())
    print("rotation resolved, checksum:", checksum(arr))

    print("\n=== debug: raw decode of first 6 entries ===")
    for i in range(6):
        entry = arr[i]
        raw = b64decode_pad(entry)
        print(f"  [{i}] {entry!r} b64={raw.hex()} rc4(znLE)={rc4(raw, 'znLE')!r}")

    print("\n=== decoded operator table (rotated array) ===")
    for idx, (key, _) in sorted(A_CALLS.items()):
        print(f"  a({idx}, {key!r}) = {get_a(arr, idx, key)!r}")
    for idx, (_, _) in sorted(N_CALLS.items()):
        print(f"  n({idx}) = {get_n(arr, idx)!r}")

    print("\n=== decoded full array ===")
    for i, entry in enumerate(arr):
        print(f"  [{i}] {entry!r} -> {rc4(b64decode_pad(entry), 'x')[:0].decode()!r}")

    payload = sys.argv[1] if len(sys.argv) > 1 else None
    if payload is None:
        # Live-fetch the first server endpoint so the decode is always verified
        # against a real response (no quoting needed in the shell).
        tmdb = "634649"
        url = f"https://new.vidnest.fun/hollymoviehd/movie/{tmdb}"
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 (Linux; Android 13; Pixel 7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 "
                "Mobile Safari/537.36",
                "Referer": f"https://vidnest.fun/movie/{tmdb}",
            },
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read().decode("utf-8", "replace")
        print(f"=== live payload from {url} ===")
        parsed_in = json.loads(raw)
        payload = parsed_in.get("data", "")
    if payload:
        print("\n=== decode real payload (custom-alphabet base64) ===")
        alphabet = "RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/="
        lookup = {c: i for i, c in enumerate(alphabet)}
        # replicate the inner decoder faithfully: EVERY group is padded to 4
        # chars with '=' (the site pads each group before processing), then
        # 4 chars -> 3 bytes with the site's emission rules (b0 always;
        # b1/b2 gated by the sentinel 64).
        out = bytearray()
        i = 0
        while i < len(payload):
            group = payload[i:i + 4]
            i += 4
            group = group + "=" * (4 - len(group))
            vals = [lookup.get(c, 64) for c in group]
            b0 = (vals[0] << 2) | (vals[1] >> 4)
            out.append(b0 & 0xFF)
            if vals[2] != 64:
                b1 = ((vals[1] & 15) << 4) | (vals[2] >> 2)
                out.append(b1 & 0xFF)
                if vals[3] != 64:
                    b2 = ((vals[2] & 3) << 6) | vals[3]
                    out.append(b2 & 0xFF)
        text = out.decode("utf-8", "replace")
        print(text[:2000])
        try:
            parsed = json.loads(text)
            print("\n=== parsed JSON keys ===")
            print(json.dumps(parsed, indent=1)[:2000])
        except Exception as e:
            print("not JSON:", e)


if __name__ == "__main__":
    main()
