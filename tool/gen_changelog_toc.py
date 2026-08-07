#!/usr/bin/env python3
r"""
gen_changelog_toc.py — regenerate the collapsible "Riwayat versi" (version
TOC) block in README.md from the changelog headings themselves.

Keeps the version list in sync with the changelog: after adding a new changelog
entry, run `python3 tool/gen_changelog_toc.py` and commit. The script parses
every `### `date` — vX.Y.Z: …` heading inside `## 📝 Changelog`, computes the
GitHub anchor for each (same slug algorithm GitHub uses to render heading
ids), and rewrites the `<details>` block between the marker comments:

    <!-- VERSION-TOC:start -->
    …
    <!-- VERSION-TOC:end -->

Usage:
    python3 tool/gen_changelog_toc.py            # rewrite in place
    python3 tool/gen_changelog_toc.py --check    # fail if the block is stale

The slug algorithm mirrors GitHub's `user-content-` anchor generation:
lowercase, drop non-word/non-hyphen/non-space characters (punctuation,
backticks, dots, colons AND the em-dash — which leaves two spaces, hence the
`--` in anchors like `2026-08-07--v1334-…`), then replace EACH space with a
hyphen without collapsing runs. Verified against a live-rendered FilmKU
README (2026-08): all 49 changelog heading slugs match 100%.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"

START = "<!-- VERSION-TOC:start -->"
END = "<!-- VERSION-TOC:end -->"


def github_slug(text: str) -> str:
    """GitHub heading anchor slug.

    Mirrors GitHub's renderer: lowercase; drop every non-word/non-hyphen/
    non-space character (punctuation, backticks, dots, colons AND the em-dash
    `—` — but an em-dash is surrounded by spaces, so dropping it leaves TWO
    spaces); then replace EACH space with a hyphen WITHOUT collapsing runs.
    That is why an em-dash in a heading renders as `--` in the anchor:
    `a — b` → `a--b`. Verified against a live-rendered FilmKU README.
    """
    slug = text.lower()
    slug = re.sub(r"[^\w\s-]", "", slug)  # drops `—` too, leaving 2 spaces
    slug = slug.replace(" ", "-").strip("-")
    return slug


def version_label(header: str) -> str:
    """Extract the version label from a changelog heading.

    Prefers the explicit `vX.Y.Z` anywhere in the heading (it sits AFTER the
    em-dash: `` `date` — v1.3.34: title ``). Falls back to the first word for
    the few unnumbered entries (e.g. "iOS sideload tooling…").
    """
    m = re.search(r"v\d+\.\d+\.\d+", header)
    if m:
        return m.group(0)
    m = re.search(r"(\b\w[\w-]*)", header.split("—", 1)[0])
    return m.group(1) if m else header


def parse_changelog_headers(text: str) -> list[tuple[str, str]]:
    """Return [(header, slug)] for every version heading inside the changelog."""
    # Everything between '## 📝 Changelog' and the next '## ' heading.
    m = re.search(r"^## 📝 Changelog\n(.*?)(?=^## )", text, re.M | re.S)
    if not m:
        return []
    out = []
    for line in m.group(1).splitlines():
        if line.startswith("### "):
            header = line[4:].strip()
            slug = github_slug(header)
            out.append((header, slug))
    return out


def build_block(headers: list[tuple[str, str]]) -> str:
    lines = [
        START,
        "",
        "<details>",
        f"<summary>📜 Riwayat versi ({len(headers)})</summary>",
        "",
    ]
    for header, slug in headers:
        label = version_label(header)
        lines.append(f"- [`{label}`](#{slug})")
    lines += [
        "",
        "</details>",
        "",
        END,
    ]
    return "\n".join(lines)


def main() -> int:
    check_only = "--check" in sys.argv
    text = README.read_text(encoding="utf-8")
    headers = parse_changelog_headers(text)
    if not headers:
        print("ERROR: no changelog headings found", file=sys.stderr)
        return 1
    new_block = build_block(headers)

    if START not in text or END not in text:
        print("ERROR: version-TOC marker comments not found in README.md", file=sys.stderr)
        return 1

    new_text = re.sub(
        re.escape(START) + r".*?" + re.escape(END),
        new_block,
        text,
        count=1,
        flags=re.S,
    )
    if check_only:
        if new_text != text:
            print("STALE: run gen_changelog_toc.py to refresh the version TOC", file=sys.stderr)
            return 1
        print(f"OK: version TOC up to date ({len(headers)} versions)")
        return 0

    README.write_text(new_text, encoding="utf-8")
    print(f"OK: version TOC regenerated ({len(headers)} versions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
