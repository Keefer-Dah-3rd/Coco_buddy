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
    static let panelWidth: CGFloat = 425
    /// `panel/height`
    static let panelHeight: CGFloat = 700
}

// MARK: - Sky (Figma collection “Sky”, mode “Value”): the pop-up panel's look

extension Sky {
    /// `color/confirm`
    static let confirm = Color(hex: 0x51E302)
    /// `color/accent` — Sunny Side orange: primary buttons, progress, focus ring. Sky.accent
    static let accent = Color(hex: 0xFF741B)
    /// `color/accent-soft` — Selected segment, passed slider ticks. Sky.accentSoft
    static let accentSoft = Color(hex: 0xFFB07A)
    /// `color/accent-text` — Orange text on white: kickers, urgent notes. Sky.accentText
    static let accentText = Color(hex: 0xF73C3C)
    /// `color/accent-pale` — Speech line, Coco bubble disc, active tab tile. Sky.accentPale
    static let accentPale = Color(hex: 0xFFF1E6)
    /// `color/ink` — Primary text. Sky.ink
    static let ink = Color(hex: 0x1D1F20)
    /// `color/muted` — Secondary text, idle nav. Sky.muted
    static let muted = Color(hex: 0x595E60)
    /// `color/faint` — Placeholders, done tasks. Sky.faint
    static let faint = Color(hex: 0xA3ABAE)
    /// `color/line` — Hairlines, card rims, slider track. Sky.line
    static let line = Color(hex: 0xEDF0F1)
    /// `color/well` — Input wells, segment track. Sky.well
    static let well = Color(hex: 0xF5F8F9)
    /// `color/ring` — Empty checkbox ring, dashed outlines, idle ticks. Sky.ring
    static let ring = Color(hex: 0xBFCBD0)
    /// `color/bubble-you` — Your chat bubble. Sky.bubbleYou
    static let bubbleYou = Color(hex: 0xF2F4F4)
    /// `color/dusk` — Focus countdown card and banner. Sky.dusk
    static let dusk = Color(hex: 0x39251F)
    /// `color/dusk-disc` — Banner icon disc
    static let duskDisc = Color(hex: 0x4D3C37)
    /// `color/paper` — Panel and card fill. Sky.paper
    static let paper = Color(hex: 0xFFFFFF)
    /// `color/receipt-card` — Day Club receipt card
    static let receiptCard = Color(hex: 0xF7F6F0)
    /// `color/receipt-ink` — Receipt text
    static let receiptInk = Color(hex: 0x38120C)
    /// `color/receipt-orange` — Receipt total
    static let receiptOrange = Color(hex: 0xEF833A)
    /// `color/receipt-dash` — Receipt dashed rule
    static let receiptDash = Color(hex: 0xBCAFA0)
    /// `color/bg1`
    static let peach = Color(hex: 0xFE9B57)
    /// `color/bg2`
    static let indigo = Color(hex: 0x3B43BD)
    /// `color/blue2`
    static let navy = Color(hex: 0x0D0640)
}

extension Sky.Radius {
    /// `radius/panel` — Panel corners. Sky.Radius.panel
    static let panel: CGFloat = 30
    /// `radius/card` — Cards, banner, countdown. Sky.Radius.card
    static let card: CGFloat = 22
    /// `radius/field` — Wells and fields. Sky.Radius.field
    static let field: CGFloat = 18
    /// `radius/key` — Draft rows, day keys, nav tile. Sky.Radius.key
    static let key: CGFloat = 14
    /// `radius/pill` — Capsules: buttons, segments, rows
    static let pill: CGFloat = 999
}

extension Sky.Space {
    /// `space/gutter` — Panel side padding
    static let gutter: CGFloat = 20
    /// `space/card` — Card inner padding
    static let card: CGFloat = 14
    /// `space/stack` — Gap between Focus / editor rows
    static let stack: CGFloat = 12
    /// `space/row` — Gap inside rows
    static let row: CGFloat = 8
}

extension Sky.Size {
    /// `size/panel-width` — Metrics.panelWidth
    static let panelWidth: CGFloat = 425
    /// `size/panel-height` — Metrics.panelHeight — never grows
    static let panelHeight: CGFloat = 700
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

// MARK: - Sky type (Figma text styles “Sky/…”)

extension SkyType {
    /// `Sky/Display/Countdown`
    static let displayCountdown = SkyType(family: "Owners Wide", face: "OwnersWide-Bold", weight: .bold, size: 46, tracking: 2)
    /// `Sky/Display/Wins`
    static let displayWins = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 28)
    /// `Sky/Display/Slider`
    static let displaySlider = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 22, tracking: -0.6)
    /// `Sky/Display/Heading`
    static let displayHeading = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 20, tracking: -0.4)
    /// `Sky/Display/Title`
    static let displayTitle = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 19, tracking: 2)
    /// `Sky/Title/Emphasis`
    static let titleEmphasis = SkyType(family: "Owners Wide", face: "OwnersWide-Bold", weight: .bold, size: 14)
    /// `Sky/Title/Row`
    static let titleRow = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 13.5)
    /// `Sky/Body/Default`
    static let bodyDefault = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 13)
    /// `Sky/Body/Small`
    static let bodySmall = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 12)
    /// `Sky/Body/Caption`
    static let bodyCaption = SkyType(family: "Inter", face: nil, weight: .regular, size: 11)
    /// `Sky/Body/Tiny`
    static let bodyTiny = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 12)
    /// `Sky/Label/Button`
    static let labelButton = SkyType(family: "Owners", face: "Owners-Bold", weight: .bold, size: 13, tracking: 0.5)
    /// `Sky/Label/Button Compact`
    static let labelButtonCompact = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 12, tracking: 0.5)
    /// `Sky/Label/Nav`
    static let labelNav = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 10, tracking: 1)
    /// `Sky/Kicker`
    static let kicker = SkyType(family: "Owners", face: "Owners-Bold", weight: .bold, size: 10, tracking: 1.25, uppercase: true)
    /// `Sky/Receipt/Display`
    static let receiptDisplay = SkyType(family: "Owners Wide", face: "OwnersWide-Bold", weight: .bold, size: 15)
    /// `Sky/Display/Window`
    static let displayWindow = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 22, tracking: 2)
    /// `Sky/Title/Card`
    static let titleCard = SkyType(family: "Owners Wide", face: "OwnersWide-Bold", weight: .bold, size: 16)
    /// `Sky/Body/Window`
    static let bodyWindow = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 12.5)
    /// `Sky/Body/Window Emphasis`
    static let bodyWindowEmphasis = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 12.5)
    /// `Sky/Body/Window Caption`
    static let bodyWindowCaption = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 11.5)
    /// `Sky/Kicker/Row`
    static let kickerRow = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 10, tracking: 1.2, uppercase: true)
    /// `Sky/Label/Step`
    static let labelStep = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 10.5)
    /// `Sky/Label/Priority`
    static let labelPriority = SkyType(family: "Owners", face: "Owners-Bold", weight: .bold, size: 11)
    /// `Sky/Kicker/Strong`
    static let kickerStrong = SkyType(family: "Owners Wide", face: "OwnersWide-Bold", weight: .bold, size: 9.5, tracking: 1.14, uppercase: true)
    /// `Sky/Label/Count`
    static let labelCount = SkyType(family: "Owners", face: "Owners-Medium", weight: .medium, size: 10)
    /// `Sky/Banner/Count`
    static let bannerCount = SkyType(family: "Inter", face: nil, weight: .medium, size: 32.8)
    /// `Sky/Banner/Total`
    static let bannerTotal = SkyType(family: "Inter", face: nil, weight: .regular, size: 15.3)
    /// `Sky/Banner/Note`
    static let bannerNote = SkyType(family: "Inter", face: nil, weight: .regular, size: 10.9)
    /// `Sky/Banner/Corner`
    static let bannerCorner = SkyType(family: "Inter", face: nil, weight: .regular, size: 7.1, tracking: 0.44, uppercase: true)
    /// `Sky/Banner/Remaining`
    static let bannerRemaining = SkyType(family: "Inter", face: nil, weight: .regular, size: 7.66)
    /// `Sky/Banner/Offer Title`
    static let bannerOfferTitle = SkyType(family: "Inter", face: nil, weight: .medium, size: 11.5)
    /// `Sky/Banner/Offer Detail`
    static let bannerOfferDetail = SkyType(family: "Inter", face: nil, weight: .regular, size: 10)
}
