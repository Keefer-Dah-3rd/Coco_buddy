#!/usr/bin/env python3
"""Applies a Figma token export to design/tokens.json and regenerates the Swift tokens.

    python3 scripts/tokens/apply_figma_export.py path/to/coco-tokens.json [--dry-run]
    python3 scripts/tokens/apply_figma_export.py --format   # rewrite tokens.json canonically

The export comes from design/figma/tokens-bridge.js (the Coco Tokens plugin's
“Export” button, or `exportTokens()` through the Figma MCP). It is
`{"tokens": {...}, "warnings": [...], "checksum": "…"}`; a bare tokens object works too.

Steps: verify the checksum → validate → print what changed, token by token →
write tokens.json (canonical order and formatting) → run the Swift generator.
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_swift as gen  # noqa: E402

# Figma's own scope order (VariableScope in the Plugin API typings); exports come back in it.
SCOPE_ORDER = [
    "ALL_SCOPES", "TEXT_CONTENT", "CORNER_RADIUS", "WIDTH_HEIGHT", "GAP", "ALL_FILLS", "FRAME_FILL",
    "SHAPE_FILL", "TEXT_FILL", "STROKE_COLOR", "STROKE_FLOAT", "EFFECT_FLOAT", "EFFECT_COLOR", "OPACITY",
    "FONT_FAMILY", "FONT_STYLE", "FONT_WEIGHT", "FONT_SIZE", "LINE_HEIGHT", "LETTER_SPACING",
]
KEY_ORDER = ["swift", "figma", "light", "dark", "value", "family", "weight", "size", "tracking", "uppercase",
             "scopes", "description"]
GROUP_ORDER = ["primitives", "color", "brand", "space", "radius", "metrics", "fonts", "typography"]


def checksum(text):
    """FNV-1a over UTF-16 code units — the same as cocoChecksum in tokens-bridge.js."""
    value = 0x811C9DC5
    units = text.encode("utf-16-le")
    for i in range(0, len(units), 2):
        value ^= units[i] | (units[i + 1] << 8)
        value = (value * 0x01000193) & 0xFFFFFFFF
    return f"{value:08x}"


def canonical(tokens, description):
    """Same content, stable order: groups, then tokens as Figma lists them, then keys."""
    out = {"$description": description, "$version": tokens.get("$version", 1)}
    for group in GROUP_ORDER:
        section = tokens[group]
        ordered = {k: v for k, v in section.items() if k.startswith("$")}
        for name, token in section.items():
            if name.startswith("$"):
                continue
            if isinstance(token, dict):
                token = {k: token[k] for k in KEY_ORDER if k in token} | {k: v for k, v in token.items() if k not in KEY_ORDER}
                if "scopes" in token:
                    token["scopes"] = sorted(token["scopes"], key=lambda s: SCOPE_ORDER.index(s) if s in SCOPE_ORDER else 99)
            ordered[name] = token
        out[group] = ordered
    return out


def dumps(tokens):
    """One token per line, like the hand-written file."""
    lines = ["{"]
    groups = list(tokens.items())
    for gi, (group, section) in enumerate(groups):
        comma = "," if gi < len(groups) - 1 else ""
        if not isinstance(section, dict):
            lines.append(f"  {json.dumps(group)}: {json.dumps(section, ensure_ascii=False)}{comma}")
            continue
        lines.append(f"  {json.dumps(group)}: {{")
        items = list(section.items())
        for i, (name, value) in enumerate(items):
            inner = "," if i < len(items) - 1 else ""
            text = json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
            if isinstance(value, dict):
                text = "{ " + text[1:-1] + " }"
            lines.append(f"    {json.dumps(name, ensure_ascii=False)}: {text}{inner}")
        lines.append(f"  }}{comma}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def changes(old, new):
    found = []
    for group in GROUP_ORDER:
        a, b = old.get(group, {}), new.get(group, {})
        for name in list(a) + [n for n in b if n not in a]:
            if name.startswith("$"):
                continue
            if name not in b:
                found.append(f"  − {group} {name} (removed in Figma)")
            elif name not in a:
                found.append(f"  + {group} {name} = {json.dumps(b[name], ensure_ascii=False)}")
            elif a[name] != b[name]:
                if isinstance(a[name], dict):
                    diffs = [f"{k}: {json.dumps(a[name].get(k), ensure_ascii=False)} → {json.dumps(b[name].get(k), ensure_ascii=False)}"
                             for k in sorted(set(a[name]) | set(b[name])) if a[name].get(k) != b[name].get(k)]
                    found.append(f"  ~ {group} {name}: " + "; ".join(diffs))
                else:
                    found.append(f"  ~ {group} {name}: {a[name]} → {b[name]}")
    return found


def main(argv):
    current = json.loads(gen.TOKENS.read_text())
    description = current["$description"]
    if argv[:1] == ["--format"]:
        gen.TOKENS.write_text(dumps(canonical(current, description)))
        print("Reformatted design/tokens.json")
        return 0
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2

    payload = json.loads(Path(argv[0]).read_text())
    tokens = payload.get("tokens", payload)
    if "checksum" in payload:
        actual = checksum(json.dumps(tokens, ensure_ascii=False, separators=(",", ":")))
        if actual != payload["checksum"]:
            print(f"Checksum mismatch ({actual} ≠ {payload['checksum']}): the export was altered or truncated.", file=sys.stderr)
            return 3
    for warning in payload.get("warnings", []):
        print(f"warning: {warning}")

    updated = canonical(tokens, description)
    try:
        gen.validate(updated)
    except gen.TokenError as error:
        print(f"The Figma export isn't valid, nothing was changed:\n{error}", file=sys.stderr)
        return 2

    found = changes(canonical(current, description), updated)
    print("Token changes from Figma:" if found else "No token changes — Figma matches design/tokens.json.")
    print("\n".join(found)) if found else None
    if "--dry-run" in argv:
        return 0
    gen.TOKENS.write_text(dumps(updated))
    return gen.main([])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
