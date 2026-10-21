import SwiftUI

/// The pop-up panel's look: Blue Skies Plus (the Figma Make "Blue Skies" style, with Sunny
/// Side's orange as the accent). Values are copied from the style's CSS. Only the panel uses
/// these; the Settings, Connections and welcome windows keep the Theme tokens.
enum Sky {
    // MARK: Colour

    /// Sunny Side's orange: primary buttons, progress, the focus ring.
    static let accent = Color(hex: 0xFF741B)
    /// Blue Skies' soft brand fill: the selected segment and the slider's passed ticks.
    static let accentSoft = Color(hex: 0xFFB07A)
    /// Orange text on white: kickers and urgent notes.
    static let accentText = Color(hex: 0xD9480F)
    /// The pale tint behind Coco's line, her bubbles and the active tab.
    static let accentPale = Color(hex: 0xFFF1E6)
    /// Blue Skies' `--bs-ink`.
    static let ink = Color(hex: 0x1D1F20)
    /// Blue Skies' `--bs-muted`.
    static let muted = Color(hex: 0x71777A)
    /// Placeholders and finished items.
    static let faint = Color(hex: 0xA3ABAE)
    /// Blue Skies' `--bs-line`: the hairlines between rows.
    static let line = Color(hex: 0xEDF0F1)
    /// Input wells.
    static let well = Color(hex: 0xF5F8F9)
    /// Empty checkboxes and the dashed outlines.
    static let ring = Color(hex: 0xBFCBD0)
    /// Your own chat bubbles.
    static let bubbleYou = Color(hex: 0xF2F4F4)
    /// Dark brown for the focus countdown card (Sunny Side's banner).
    static let dusk = Color(hex: 0x39251F)
    static let paper = Color.white

    // MARK: Shape

    enum Radius {
        static let panel: CGFloat = 30
        static let card: CGFloat = 22
        static let field: CGFloat = 18
        static let key: CGFloat = 14
    }

    // MARK: Type
    // The app bundles no fonts, so this is the system face (SF Pro) rather than the comps' DM Sans.

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Big numbers and headings. Callers add the tight tracking the comps use.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }

    // MARK: Motion

    enum Motion {
        static let quick = Animation.easeInOut(duration: 0.2)
        static let enter = Animation.easeInOut(duration: 0.35)
        /// The squish of a pressed or dragged thing.
        static let squish = Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}
