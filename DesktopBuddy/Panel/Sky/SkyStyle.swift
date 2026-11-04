import AppKit
import SwiftUI

/// The pop-up panel's look: Blue Skies Plus, as redrawn in the Coco-2 Figma file. The panel,
/// the welcome window and the Connections window use these; Settings keeps the Theme tokens.
///
/// The colours, radii, spacing, sizes and text styles are generated from Figma's “Sky” variable
/// collection and “Sky/…” text styles into DesignTokens.generated.swift (docs/DESIGN_SYSTEM.md).
/// This file holds what Figma doesn't: how a text style becomes a font, and the motion.
enum Sky {
    // MARK: Tokens (values in DesignTokens.generated.swift)

    enum Radius {}
    enum Space {}
    enum Size {}

    // MARK: Type
    // `text` and `display` are the system face (SF Pro), which the code uses wherever Figma
    // sets Inter. Owners roles use the named styles in SkyType.

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Big numbers in the system face. Callers add the tight tracking the comps use.
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

/// A Figma “Sky/…” text style: Owners or Owners Wide (MCKL) at a set size, weight and tracking.
///
/// Owners comes from Adobe Fonts, whose licence doesn't allow bundling it, so the app uses it
/// wherever it's installed and otherwise falls back to the system face at the same size and
/// weight — the wide cut falls back to SF Pro's expanded width. Styles Figma sets in Inter
/// have no `face` and always use the system face.
struct SkyType: Sendable {
    /// The Figma family: "Owners", "Owners Wide" or "Inter".
    let family: String
    /// The PostScript name to load, or nil for the system face.
    let face: String?
    let weight: Font.Weight
    let size: CGFloat
    var tracking: CGFloat = 0
    var uppercase = false

    var font: Font {
        if let face, Self.installed.contains(face) {
            return .custom(face, fixedSize: size)
        }
        let system = Font.system(size: size, weight: weight)
        return family.hasSuffix("Wide") ? system.width(.expanded) : system
    }

    /// The same style at another size, for the few places that scale a role.
    func sized(_ size: CGFloat) -> SkyType {
        SkyType(family: family, face: face, weight: weight, size: size, tracking: tracking, uppercase: uppercase)
    }

    /// PostScript names of every font this Mac can use, read once.
    private static let installed = Set(NSFontManager.shared.availableFonts)

    /// Whether the Owners faces are available here (false means the system fallback is showing).
    static var ownersInstalled: Bool { installed.contains("Owners-Medium") }
}

extension View {
    /// Sets a Figma text style: font, tracking and case.
    func skyType(_ style: SkyType) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.uppercase ? .uppercase : nil)
    }
}

extension Text {
    /// `skyType` for Text that gets concatenated (`Text + Text`): font and tracking only, so
    /// upper-case the string yourself. A different name so it never shadows the View version.
    func skyStyled(_ style: SkyType) -> Text {
        font(style.font).tracking(style.tracking)
    }
}
