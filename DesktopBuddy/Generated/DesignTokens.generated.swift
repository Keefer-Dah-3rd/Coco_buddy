// GENERATED FILE — do not edit by hand.
// Source: design/tokens.json  ·  Generator: scripts/tokens/generate_swift.py
// Change a token in Figma and sync it, or edit design/tokens.json and run the generator.
// See docs/DESIGN_SYSTEM.md.

import AppKit
import SwiftUI

// MARK: - Color (Figma collection “Color”, modes Light / Dark)

extension Theme {
    /// `surface/paper` — Panel and window background; text on ink fills.
    static let paper = dynamic(light: 0xF3F1EC, dark: 0x1C1C1A)
    /// `surface/well` — Recessed areas: fields, cards, hover.
    static let well = dynamic(light: 0xE8E5DE, dark: 0x272724)
    /// `ink/primary` — Primary text; selected-segment fill.
    static let ink = dynamic(light: 0x1A1A18, dark: 0xEFECE5)
    /// `ink/secondary` — Supporting text, mono labels.
    static let inkSecondary = dynamic(light: 0x6E6A61, dark: 0x9C988E)
    /// `ink/tertiary` — Placeholders, metadata, disabled hints.
    static let inkTertiary = dynamic(light: 0xA6A196, dark: 0x64615A)
    /// `line/hairline` — 1 pt borders and dividers.
    static let hairline = dynamic(light: 0xD9D5CB, dark: 0x363531)
    /// `accent/default` — The one accent: primary keys, focus, Coco's tag.
    static let accent = dynamic(light: 0xFF5A1F, dark: 0xFF6A33)
    /// `accent/on-accent` — Text on accent fills; dark in both modes, like a printed key cap.
    static let onAccent = Color(hex: 0x1A1A18)
    /// `lcd/screen` — The countdown chip's LCD; the same in both modes.
    static let lcd = Color(hex: 0x1D1E1B)
    /// `lcd/phosphor` — Digits on the LCD.
    static let phosphor = Color(hex: 0xFFE6B0)
}

// MARK: - Brand (Figma collection “Brand”): Coco's palette and the app icon

enum BrandPalette {
    /// `coco/fur`
    static let fur = NSColor(hex: 0x221D1B)
    /// `coco/fur-rim` — Warm grey edge so a black dog still reads on a dark desktop.
    static let rim = NSColor(hex: 0x5E5550)
    /// `coco/fur-shade`
    static let furShade = NSColor(hex: 0x3A322F)
    /// `coco/white`
    static let white = NSColor(hex: 0xF4F0E8)
    /// `coco/white-edge`
    static let whiteEdge = NSColor(hex: 0xCFC7BB)
    /// `coco/inner-ear`
    static let innerEar = NSColor(hex: 0x7A5446)
    /// `coco/nose`
    static let nose = NSColor(hex: 0x141112)
    /// `coco/eye`
    static let eye = NSColor(hex: 0x1A110D)
    /// `coco/eye-rim`
    static let eyeRim = NSColor(hex: 0x86675A)
    /// `coco/eye-closed`
    static let closedEye = NSColor(hex: 0xD7CEC4)
    /// `coco/mouth-line`
    static let mouthLine = NSColor(hex: 0x2A2220)
    /// `coco/mouth-inside`
    static let mouthInside = NSColor(hex: 0x3D1D24)
    /// `coco/tongue`
    static let tongue = NSColor(hex: 0xEC8A9B)
    /// `coco/tongue-groove`
    static let tongueGroove = NSColor(hex: 0xC8687C)
    /// `coco/collar`
    static let collar = NSColor(hex: 0x151515)
    /// `coco/collar-rim`
    static let collarRim = NSColor(hex: 0x4A4542)
    /// `coco/tag-face`
    static let tagFace = NSColor(hex: 0xECEAE5)
    /// `coco/tag-light` — Collar-tag light, focus ring and sparkles.
    static let accent = NSColor(hex: 0xFF5A1F)
    /// `coco/ink` — Thought dots and sleep Zs.
    static let ink = NSColor(hex: 0x2B2A27)
    /// `icon/tile`
    static let iconTile = NSColor(hex: 0xF3F1EC)
    /// `icon/floor`
    static let iconFloor = NSColor(hex: 0xE6E1D7)
    /// `icon/stroke`
    static let iconStroke = NSColor(hex: 0xD3CDC1)
}

// MARK: - Space (Figma collection “Space”)

nonisolated enum Space {
    /// `xxxs`
    static let xxxs: CGFloat = 2
    /// `xxs`
    static let xxs: CGFloat = 4
    /// `xs`
    static let xs: CGFloat = 6
    /// `sm`
    static let sm: CGFloat = 8
    /// `md` — Row and card padding.
    static let md: CGFloat = 10
    /// `lg`
    static let lg: CGFloat = 12
    /// `xl` — Panel inset.
    static let xl: CGFloat = 16
    /// `xxl` — Window inset.
    static let xxl: CGFloat = 24
    /// `xxxl`
    static let xxxl: CGFloat = 32
}

// MARK: - Radius (Figma collection “Radius”)

nonisolated enum Radius {
    /// `bar` — Progress segments.
    static let bar: CGFloat = 1.5
    /// `check` — Task checkbox.
    static let check: CGFloat = 3.5
    /// `keycap` — Keycaps, chips, the LCD.
    static let keycap: CGFloat = 4
    /// `key` — Key buttons and inline fields.
    static let key: CGFloat = 5
    /// `control` — Segmented controls, fields, banners.
    static let control: CGFloat = 6
    /// `card`
    static let card: CGFloat = 8
    /// `bubble` — Coco's speech bubble.
    static let bubble: CGFloat = 9
    /// `section` — Settings and Connections sections.
    static let section: CGFloat = 10
    /// `panel`
    static let panel: CGFloat = 12
}

// MARK: - Metrics (Figma collection “Metrics”)

nonisolated enum Metrics {
    /// `stroke/hairline`
    static let hairline: CGFloat = 1
    /// `opacity/disabled`
    static let disabledOpacity: Double = 0.4
    /// `opacity/pressed`
    static let pressedOpacity: Double = 0.85
    /// `panel/width`
    static let panelWidth: CGFloat = 340
    /// `panel/height`
    static let panelHeight: CGFloat = 540
}

// MARK: - Typography (Figma text styles)

extension TypeStyle {
    /// `Display/Countdown`
    static let displayCountdown = TypeStyle(design: .monospaced, weight: .light, size: 62)
    /// `Display/Count`
    static let displayCount = TypeStyle(design: .default, weight: .semibold, size: 30)
    /// `Title/Large`
    static let titleLarge = TypeStyle(design: .default, weight: .semibold, size: 22)
    /// `Title/Section`
    static let titleSection = TypeStyle(design: .default, weight: .semibold, size: 15)
    /// `Speech/Panel`
    static let speechPanel = TypeStyle(design: .default, weight: .medium, size: 13.5)
    /// `Speech/Bubble`
    static let speechBubble = TypeStyle(design: .default, weight: .medium, size: 12.5)
    /// `Body/Default`
    static let body = TypeStyle(design: .default, weight: .regular, size: 13)
    /// `Body/Emphasis`
    static let bodyEmphasis = TypeStyle(design: .default, weight: .medium, size: 13)
    /// `Body/Small`
    static let bodySmall = TypeStyle(design: .default, weight: .regular, size: 12)
    /// `Body/Small Emphasis`
    static let bodySmallEmphasis = TypeStyle(design: .default, weight: .medium, size: 12)
    /// `Caption`
    static let caption = TypeStyle(design: .default, weight: .regular, size: 11)
    /// `Mono/Label`
    static let monoLabel = TypeStyle(design: .monospaced, weight: .semibold, size: 10, tracking: 0.8, uppercase: true)
    /// `Mono/Key`
    static let monoKey = TypeStyle(design: .monospaced, weight: .semibold, size: 11, tracking: 0.6, uppercase: true)
    /// `Mono/Key Compact`
    static let monoKeyCompact = TypeStyle(design: .monospaced, weight: .semibold, size: 10, tracking: 0.6, uppercase: true)
    /// `Mono/Value`
    static let monoValue = TypeStyle(design: .monospaced, weight: .medium, size: 11)
    /// `Mono/Mark`
    static let monoMark = TypeStyle(design: .monospaced, weight: .bold, size: 10)
    /// `Mono/Tiny`
    static let monoTiny = TypeStyle(design: .monospaced, weight: .semibold, size: 9)
}
