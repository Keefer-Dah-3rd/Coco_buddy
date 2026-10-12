#!/usr/bin/env python3
"""Generates DesktopBuddy/Generated/DesignTokens.generated.swift from design/tokens.json.

    python3 scripts/tokens/generate_swift.py          # write the Swift file
    python3 scripts/tokens/generate_swift.py --check  # exit 1 if it's out of date

Validates the token file first (aliases resolve, hex colors, unique Swift names,
known weights and scopes) and refuses to write anything if it's invalid.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "design" / "tokens.json"
OUTPUT = ROOT / "DesktopBuddy" / "Generated" / "DesignTokens.generated.swift"

HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
IDENTIFIER = re.compile(r"^[a-z][A-Za-z0-9]*$")
WEIGHTS = {"ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"}
SCOPES = {
    "FRAME_FILL", "SHAPE_FILL", "TEXT_FILL", "STROKE_COLOR", "EFFECT_COLOR", "GAP", "CORNER_RADIUS",
    "WIDTH_HEIGHT", "STROKE_FLOAT", "OPACITY", "FONT_SIZE", "LETTER_SPACING", "LINE_HEIGHT",
}
FLOAT_GROUPS = ("space", "radius", "metrics")


class TokenError(Exception):
    pass


def entries(group):
    """The tokens in a group, without its `$` metadata keys."""
    return {name: value for name, value in group.items() if not name.startswith("$")}


def validate(tokens):
    problems = []
    primitives = entries(tokens.get("primitives", {}))
    for name, value in primitives.items():
        if not isinstance(value, str) or not HEX.match(value):
            problems.append(f"primitives/{name}: expected #RRGGBB, got {value!r}")

    def resolve(reference, where):
        if isinstance(reference, str) and HEX.match(reference):
            return reference
        if reference in primitives:
            return primitives[reference]
        problems.append(f"{where}: {reference!r} is neither #RRGGBB nor a primitive")
        return "#000000"

    swift_names = {}

    def claim(namespace, swift, where):
        if not isinstance(swift, str) or not IDENTIFIER.match(swift):
            problems.append(f"{where}: swift name {swift!r} isn't a lowerCamelCase identifier")
            return
        key = (namespace, swift)
        if key in swift_names:
            problems.append(f"{where}: swift name {swift!r} is also used by {swift_names[key]}")
        swift_names[key] = where

    for name, token in entries(tokens.get("color", {})).items():
        where = f"color/{name}"
        claim("Theme", token.get("swift"), where)
        for mode in ("light", "dark"):
            if mode not in token:
                problems.append(f"{where}: missing {mode} value")
            else:
                resolve(token[mode], f"{where} ({mode})")
        unknown = set(token.get("scopes", [])) - SCOPES
        if unknown:
            problems.append(f"{where}: unknown scopes {sorted(unknown)}")

    for name, token in entries(tokens.get("brand", {})).items():
        claim("BrandPalette", token.get("swift"), f"brand/{name}")
        resolve(token.get("value"), f"brand/{name}")

    for group in FLOAT_GROUPS:
        for name, token in entries(tokens.get(group, {})).items():
            where = f"{group}/{name}"
            claim(group, token.get("swift"), where)
            if not isinstance(token.get("value"), (int, float)) or token["value"] < 0:
                problems.append(f"{where}: expected a non-negative number, got {token.get('value')!r}")

    fonts = tokens.get("fonts", {})
    for family in ("sans", "mono"):
        if family not in fonts:
            problems.append(f"fonts: missing {family}")
    for name, style in entries(tokens.get("typography", {})).items():
        where = f"typography/{name}"
        claim("TypeStyle", style.get("swift"), where)
        if style.get("family") not in fonts:
            problems.append(f"{where}: family {style.get('family')!r} isn't in fonts")
        if style.get("weight") not in WEIGHTS:
            problems.append(f"{where}: weight {style.get('weight')!r} isn't one of {sorted(WEIGHTS)}")
        if not isinstance(style.get("size"), (int, float)) or style["size"] <= 0:
            problems.append(f"{where}: size must be a positive number")

    if problems:
        raise TokenError("\n".join(problems))
    return resolve


def swift_hex(color):
    return "0x" + color[1:].upper()


def number(value):
    text = f"{value:g}"
    return text


def doc(token, figma_name):
    note = token.get("description")
    return f"    /// `{figma_name}`" + (f" — {note}" if note else "")


def generate(tokens):
    resolve = validate(tokens)
    lines = [
        "// GENERATED FILE — do not edit by hand.",
        "// Source: design/tokens.json  ·  Generator: scripts/tokens/generate_swift.py",
        "// Change a token in Figma and sync it, or edit design/tokens.json and run the generator.",
        "// See docs/DESIGN_SYSTEM.md.",
        "",
        "import AppKit",
        "import SwiftUI",
        "",
        "// MARK: - Color (Figma collection “Color”, modes Light / Dark)",
        "",
        "extension Theme {",
    ]
    for name, token in entries(tokens["color"]).items():
        light = swift_hex(resolve(token["light"], name))
        dark = swift_hex(resolve(token["dark"], name))
        lines.append(doc(token, name))
        if light == dark:
            lines.append(f"    static let {token['swift']} = Color(hex: {light})")
        else:
            lines.append(f"    static let {token['swift']} = dynamic(light: {light}, dark: {dark})")
    lines += ["}", "", "// MARK: - Brand (Figma collection “Brand”): Coco's palette and the app icon", "",
              "enum BrandPalette {"]
    for name, token in entries(tokens["brand"]).items():
        lines.append(doc(token, name))
        lines.append(f"    static let {token['swift']} = NSColor(hex: {swift_hex(resolve(token['value'], name))})")
    lines.append("}")

    titles = {"space": "Space", "radius": "Radius", "metrics": "Metrics"}
    for group in FLOAT_GROUPS:
        lines += ["", f"// MARK: - {titles[group]} (Figma collection “{tokens[group]['$collection']}”)", "",
                  f"nonisolated enum {titles[group]} {{"]
        for name, token in entries(tokens[group]).items():
            kind = "Double" if "OPACITY" in token.get("scopes", []) else "CGFloat"
            lines.append(doc(token, name))
            lines.append(f"    static let {token['swift']}: {kind} = {number(token['value'])}")
        lines.append("}")

    lines += ["", "// MARK: - Typography (Figma text styles)", "", "extension TypeStyle {"]
    fonts = tokens["fonts"]
    for name, style in entries(tokens["typography"]).items():
        design = fonts[style["family"]]["swift"]
        args = [f"design: .{design}", f"weight: .{style['weight']}", f"size: {number(style['size'])}"]
        if style.get("tracking"):
            args.append(f"tracking: {number(style['tracking'])}")
        if style.get("uppercase"):
            args.append("uppercase: true")
        lines.append(f"    /// `{name}`")
        lines.append(f"    static let {style['swift']} = TypeStyle({', '.join(args)})")
    lines += ["}", ""]
    return "\n".join(lines)


def main(argv):
    try:
        tokens = json.loads(TOKENS.read_text())
        swift = generate(tokens)
    except (TokenError, json.JSONDecodeError, KeyError) as error:
        print(f"design/tokens.json is invalid:\n{error}", file=sys.stderr)
        return 2
    if "--check" in argv:
        if not OUTPUT.exists() or OUTPUT.read_text() != swift:
            print(f"{OUTPUT.relative_to(ROOT)} is out of date — run scripts/tokens/generate_swift.py", file=sys.stderr)
            return 1
        print("Generated tokens are up to date.")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    changed = not OUTPUT.exists() or OUTPUT.read_text() != swift
    OUTPUT.write_text(swift)
    print(f"{'Wrote' if changed else 'Unchanged:'} {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
