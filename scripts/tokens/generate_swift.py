#!/usr/bin/env python3
"""Generates DesktopBuddy/Generated/DesignTokens.generated.swift from design/tokens.json.

    python3 scripts/tokens/generate_swift.py          # write the Swift file
    python3 scripts/tokens/generate_swift.py --check  # exit 1 if it's out of date

Validates the token file first (aliases resolve, hex colors, unique Swift names,
known weights and scopes) and refuses to write anything if it's invalid.

The `sky` and `skyTypography` groups (Figma's “Sky” collection and “Sky/…” text styles) are
the pop-up panel's own look; they become `Sky.*`, `Sky.Radius.*`, … and `SkyType.*`.
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
    "ALL_SCOPES", "ALL_FILLS", "FRAME_FILL", "SHAPE_FILL", "TEXT_FILL", "STROKE_COLOR", "EFFECT_COLOR", "GAP",
    "CORNER_RADIUS", "WIDTH_HEIGHT", "STROKE_FLOAT", "OPACITY", "FONT_SIZE", "LETTER_SPACING", "LINE_HEIGHT",
}
FLOAT_GROUPS = ("space", "radius", "metrics")
GROUPS = ("primitives", "color", "brand", *FLOAT_GROUPS, "sky", "fonts", "typography", "skyTypography")
# A Sky token's `swift` is its iOS code syntax after "Sky.": "navy", or "Radius.panel" for a
# token in one of the nested enums SkyStyle.swift declares.
SKY_SWIFT = re.compile(r"^(?:([A-Z][A-Za-z0-9]*)\.)?([a-z][A-Za-z0-9]*)$")
SKY_NAMESPACES = ("Radius", "Space", "Size")
# A Sky text style's Figma font style → Font.Weight.
STYLE_WEIGHTS = {
    "thin": "thin", "extralight": "ultralight", "ultralight": "ultralight", "light": "light",
    "regular": "regular", "book": "regular", "medium": "medium", "semibold": "semibold",
    "demibold": "semibold", "bold": "bold", "extrabold": "heavy", "ultrabold": "heavy",
    "heavy": "heavy", "black": "black",
}


class TokenError(Exception):
    pass


def entries(group):
    """The tokens in a group, without its `$` metadata keys."""
    return {name: value for name, value in group.items() if not name.startswith("$")}


def style_weight(style):
    """"Semi Bold" → "semibold"; None if it isn't a weight."""
    return STYLE_WEIGHTS.get(str(style).lower().replace(" ", "").replace("-", ""))


def sky_face(tokens, style):
    """The PostScript name SkyType loads ("Owners Wide" + "Bold" → "OwnersWide-Bold"), or None
    for the system font's Figma stand-in (Inter), which the app always draws in SF Pro."""
    if style["family"] == tokens["fonts"]["sans"]["figma"]:
        return None
    return style["family"].replace(" ", "") + "-" + style["style"].replace(" ", "")


def validate(tokens):
    problems = [f"missing group {group!r}" for group in GROUPS if not isinstance(tokens.get(group), dict)]
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

    for name, token in entries(tokens.get("sky", {})).items():
        where = f"sky/{name}"
        match = SKY_SWIFT.match(str(token.get("swift")))
        if not match:
            problems.append(f"{where}: swift name {token.get('swift')!r} isn't `name` or `Namespace.name`")
        elif match.group(1) and match.group(1) not in SKY_NAMESPACES:
            problems.append(f"{where}: Sky.{match.group(1)} isn't one of the Sky enums ({', '.join(SKY_NAMESPACES)})")
        else:
            claim("Sky." + match.group(1) if match.group(1) else "Sky", match.group(2), where)
        value = token.get("value")
        if isinstance(value, str):
            resolve(value, where)
        elif not isinstance(value, (int, float)) or value < 0:
            problems.append(f"{where}: expected a color or a non-negative number, got {value!r}")
        unknown = set(token.get("scopes", [])) - SCOPES
        if unknown:
            problems.append(f"{where}: unknown scopes {sorted(unknown)}")

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
    for name, style in entries(tokens.get("skyTypography", {})).items():
        where = f"skyTypography/{name}"
        claim("SkyType", style.get("swift"), where)
        if not isinstance(style.get("family"), str) or not style["family"]:
            problems.append(f"{where}: missing family")
        if not style_weight(style.get("style")):
            problems.append(f"{where}: font style {style.get('style')!r} isn't a weight ({', '.join(sorted(STYLE_WEIGHTS))})")
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


def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


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

    lines += ["", f"// MARK: - Sky (Figma collection “{tokens['sky']['$collection']}”, mode “Value”): the pop-up panel's look"]
    namespaces = {}
    for name, token in entries(tokens["sky"]).items():
        namespace, _, swift = token["swift"].rpartition(".")
        namespaces.setdefault(namespace, []).append((name, swift, token))
    for namespace, members in namespaces.items():
        lines += ["", f"extension Sky{'.' + namespace if namespace else ''} {{"]
        for name, swift, token in members:
            lines.append(doc(token, name))
            if isinstance(token["value"], str):
                lines.append(f"    static let {swift} = Color(hex: {swift_hex(resolve(token['value'], name))})")
            else:
                kind = "Double" if "OPACITY" in token.get("scopes", []) else "CGFloat"
                lines.append(f"    static let {swift}: {kind} = {number(token['value'])}")
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
    lines += ["}", "", "// MARK: - Sky type (Figma text styles “Sky/…”)", "", "extension SkyType {"]
    for name, style in entries(tokens["skyTypography"]).items():
        face = sky_face(tokens, style)
        args = [f"family: {swift_string(style['family'])}", f"face: {swift_string(face) if face else 'nil'}",
                f"weight: .{style_weight(style['style'])}", f"size: {number(style['size'])}"]
        if style.get("tracking"):
            args.append(f"tracking: {number(style['tracking'])}")
        if style.get("uppercase"):
            args.append("uppercase: true")
        lines.append(f"    /// `{name}`")
        lines.append(f"    static let {style['swift']} = SkyType({', '.join(args)})")
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
