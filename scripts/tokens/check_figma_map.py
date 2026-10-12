#!/usr/bin/env python3
"""Checks design/figma-map.json against the code: every mapped file exists and still contains
its anchor text, and every mapped SF Symbol is still used somewhere in the app.

    python3 scripts/tokens/check_figma_map.py
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    mapping = json.loads((ROOT / "design" / "figma-map.json").read_text())
    sources = "\n".join(p.read_text() for p in (ROOT / "DesktopBuddy").rglob("*.swift"))
    problems = []
    for entry in mapping["components"]:
        name, swift = entry["figma"]["name"], entry["swift"]
        path = ROOT / swift["file"]
        if not path.exists():
            problems.append(f"{name}: {swift['file']} doesn't exist")
        elif swift["anchor"] not in path.read_text():
            problems.append(f"{name}: “{swift['anchor']}” not found in {swift['file']}")
    for entry in mapping["icons"]:
        symbol = entry["figma"]["name"].removeprefix("Icon/")
        if f'"{symbol}"' not in sources:
            problems.append(f"{entry['figma']['name']}: SF Symbol “{symbol}” is no longer used in the app")
    if problems:
        print("Figma map is out of date:\n  " + "\n  ".join(problems), file=sys.stderr)
        return 1
    print(f"Figma map OK: {len(mapping['components'])} components and {len(mapping['icons'])} icons point at real code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
