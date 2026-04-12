#!/usr/bin/env python3
"""Build dnsmasq rules for LanCache using uklans/cache-domains."""

from __future__ import annotations

import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

RAW_URL = "https://raw.githubusercontent.com/uklans/cache-domains/master"
MANIFEST_URL = f"{RAW_URL}/cache_domains.json"
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "lancache.conf"


def fetch_text(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8")


def fetch_domain_files() -> list[str]:
    manifest = json.loads(fetch_text(MANIFEST_URL))
    files: list[str] = []
    for entry in manifest.get("cache_domains", []):
        files.extend(entry.get("domain_files", []))
    unique_files = sorted(set(files))
    if not unique_files:
        raise RuntimeError("No domain files were found in cache_domains.json")
    return unique_files


def normalize_domain(line: str) -> str | None:
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    return line.removeprefix("*.")


def build_lines() -> list[str]:
    domains: set[str] = set()
    for domain_file in fetch_domain_files():
        source = fetch_text(f"{RAW_URL}/{domain_file}")
        for raw_line in source.splitlines():
            domain = normalize_domain(raw_line)
            if domain:
                domains.add(domain)

    if not domains:
        raise RuntimeError("No cacheable domains were generated")

    header = [
        "# LanCache Pi-hole DNS Config",
        f"# Auto-generated at {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "# Source: https://github.com/uklans/cache-domains",
        "# Install script injects your LanCache server IP into each rule.",
        "",
    ]
    body = [f"server=/{domain}/LANCACHE_IP" for domain in sorted(domains)]
    return header + body + [""]


def main() -> int:
    OUTPUT_PATH.write_text("\n".join(build_lines()), encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
