#if DEBUG
import AppKit
import SwiftUI

// EXPERIMENT — "Coco Editorial Orange". Debug builds only, and only on screen when the app
// is launched with `--editorial-orange`. Nothing here is used by the real panel, and nothing
// in the shared design system (Theme, DesignTokens, tokens.json) was changed for it.
//
// Source of truth: Figma Make file AKhsjPOyTgqtgZQzI8Oadf, style "Editorial Orange"
// (src/themes/OrganicOrangeEditorial.tsx + src/index.css). Values below are copied from it;
// Tailwind names are noted where they map to a number.

/// Editorial Orange design tokens. Scoped to the experiment — prefix `EO`.
enum EO {
    // MARK: Color

    /// `#F5F4EE` — warm newsprint, the page and window background.
    static let paper = Color(hex: 0xF5F4EE)
    /// `#1A1A1A` — text, rules and outlines.
    static let ink = Color(hex: 0x1A1A1A)
    /// `#F25C05` — the one accent: kickers, the italic word, selected/enabled states, the top rule.
    static let orange = Color(hex: 0xF25C05)

    /// The ink tints the reference uses (`text-[#1A1A1A]/60` etc.).
    enum Ink {
        static let secondary = EO.ink.opacity(0.6)
        static let muted = EO.ink.opacity(0.4)
        static let faint = EO.ink.opacity(0.3)
        static let rule = EO.ink.opacity(0.2)
        static let hairline = EO.ink.opacity(0.1)
        static let dot = EO.ink.opacity(0.05)
    }

    // MARK: Type — DM Sans

    enum Weight { case light, regular, medium, bold }

    /// DM Sans at a size, picking the optical-size cut the browser would (DM Sans is a
    /// variable font with an `opsz` axis of 9–40; `font-optical-sizing: auto` tracks the
    /// px size). Installed as static families: "DM Sans", "DM Sans 18pt/24pt/36pt".
    /// Falls back to the system font on a Mac without DM Sans.
    static func font(_ size: CGFloat, _ weight: Weight = .regular, italic: Bool = false) -> Font {
        let family = size >= 36 ? "DMSans36pt" : size >= 24 ? "DMSans24pt" : size >= 18 ? "DMSans18pt" : "DMSans"
        let style: String = switch (weight, italic) {
        case (.light, false): "Light"
        case (.light, true): "LightItalic"
        case (.regular, false): "Regular"
        case (.regular, true): "Italic"
        case (.medium, false): "Medium"
        case (.medium, true): "MediumItalic"
        case (.bold, false): "Bold"
        case (.bold, true): "BoldItalic"
        }
        let name = "\(family)-\(style)"
        if FontCheck.isInstalled(name) { return .custom(name, fixedSize: size) }
        let system: Font.Weight = switch weight {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .bold: .bold
        }
        let font = Font.system(size: size, weight: system)
        return italic ? font.italic() : font
    }

    private enum FontCheck {
        nonisolated(unsafe) private static var known: [String: Bool] = [:]
        static func isInstalled(_ name: String) -> Bool {
            if let cached = known[name] { return cached }
            let found = NSFont(name: name, size: 12) != nil
            known[name] = found
            return found
        }
    }

    /// Letter-spacing presets, as Tailwind defines them (em × size).
    enum Tracking {
        /// `tracking-tighter` −0.05em — display headlines.
        static func tighter(_ size: CGFloat) -> CGFloat { -0.05 * size }
        /// `tracking-tight` −0.025em — list titles, chat headlines.
        static func tight(_ size: CGFloat) -> CGFloat { -0.025 * size }
        /// `tracking-wide` 0.025em — buttons, numbered lists.
        static func wide(_ size: CGFloat) -> CGFloat { 0.025 * size }
        /// `tracking-widest` 0.1em — the uppercase kickers.
        static func widest(_ size: CGFloat) -> CGFloat { 0.1 * size }
    }

    /// The reference's type scale (px = pt here).
    enum Size {
        static let masthead: CGFloat = 72   // "The Digital Mascot"
        static let display: CGFloat = 64    // "Today"
        static let section: CGFloat = 54    // "System Capabilities"
        static let editorTitle: CGFloat = 48
        static let numeral: CGFloat = 40    // "1 / 5"
        static let headline: CGFloat = 36   // text-4xl
        static let title: CGFloat = 30      // text-3xl — "Dialog"
        static let item: CGFloat = 24       // text-2xl — list rows
        static let lead: CGFloat = 20       // text-xl — inputs, chat lines
        static let body: CGFloat = 18       // text-lg — buttons, numbered lists
        static let small: CGFloat = 14      // text-sm — kickers
        static let caption: CGFloat = 12    // text-xs
        static let micro: CGFloat = 10      // "UP NEXT"
    }

    // MARK: Space & shape

    enum Space {
        /// `p-12` — the page margin.
        static let page: CGFloat = 48
        /// `p-10` — the chat page margin.
        static let pageTight: CGFloat = 40
        /// `py-6` — list row padding.
        static let row: CGFloat = 24
        static let xs: CGFloat = 8
        static let sm: CGFloat = 16   // gap-4
        static let md: CGFloat = 24   // gap-6
        static let lg: CGFloat = 32   // mt-8 / pb-8
        static let xl: CGFloat = 48   // mb-12
        static let xxl: CGFloat = 64  // mb-16
    }

    /// `border-t-[12px] border-[#F25C05]`.
    static let topRule: CGFloat = 12
    /// The card the reference draws: `max-w-[480px] h-[800px]`, square corners.
    static let pageSize = CGSize(width: 480, height: 800)

    // MARK: Motion

    enum Motion {
        /// `.animate-slide-up` — 0.6s cubic-bezier(0.16, 1, 0.3, 1), from 20px below.
        static let slideUp = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
        static let slideDistance: CGFloat = 20
        /// `.animate-fade-in` — 0.4s ease-out.
        static let fadeIn = Animation.easeOut(duration: 0.4)
        /// `transition-* duration-500` with Tailwind's default curve.
        static let hover = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)
        /// Tailwind's default `transition` (150ms).
        static let quick = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)
        /// `animate-pulse` — 2s, opacity 1 → 0.5.
        static let pulse = Animation.timingCurve(0.4, 0, 0.6, 1, duration: 1).repeatForever(autoreverses: true)
        /// Gap between staggered entrances.
        static let stagger: Double = 0.06
    }
}
#endif
