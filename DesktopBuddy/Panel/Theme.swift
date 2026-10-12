import SwiftUI

/// Design tokens. A restrained, warm-paper palette with one accent, sans for reading,
/// mono for labels and numbers — the "instrument panel" detail used sparingly.
///
/// The values live in design/tokens.json (synced with Figma) and are generated into
/// DesktopBuddy/Generated/DesignTokens.generated.swift: colors as `Theme.paper` etc.,
/// plus `Space`, `Radius`, `Metrics`, `BrandPalette` and the `TypeStyle` presets.
enum Theme {
    /// For one-off glyphs only; text uses a `TypeStyle`.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// A color that follows the light / dark appearance; used by the generated tokens.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

/// A named text style: a font plus the tracking and case that go with it.
/// The presets (`.body`, `.monoLabel`…) are generated from the Figma text styles.
nonisolated struct TypeStyle: Sendable {
    var design: Font.Design
    var weight: Font.Weight
    var size: CGFloat
    var tracking: CGFloat = 0
    var uppercase = false

    var font: Font { .system(size: size, weight: weight, design: design) }
}

extension Font {
    /// The font of a design-system text style, e.g. `.font(.style(.bodySmall))`.
    static func style(_ style: TypeStyle) -> Font { style.font }
}

extension View {
    /// Applies a text style's font, tracking and (for label styles) uppercase.
    /// Tracking and case are only set when the style has them, so inherited ones survive.
    @ViewBuilder
    func textStyle(_ style: TypeStyle) -> some View {
        let styled = font(style.font)
            .transformEnvironment(\.textCase) { if style.uppercase { $0 = .uppercase } }
        if style.tracking != 0 {
            styled.tracking(style.tracking)
        } else {
            styled
        }
    }
}

/// Small uppercase mono label, e.g. "TODAY", "LENGTH".
struct MonoLabel: View {
    var text: String
    var color: Color = Theme.inkSecondary

    init(_ text: String, color: Color = Theme.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.style(.monoLabel))
            .tracking(TypeStyle.monoLabel.tracking)
            .foregroundStyle(color)
    }
}

/// A flat, square-shouldered button styled like a hardware key.
struct KeyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    var fillWidth = false
    /// Smaller key for inline actions inside cards and banners.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, kind: kind, fillWidth: fillWidth, compact: compact)
    }

    private struct KeyButton: View {
        let configuration: Configuration
        let kind: Kind
        let fillWidth: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let style: TypeStyle = compact ? .monoKeyCompact : .monoKey
            configuration.label
                .textStyle(style)
                .lineLimit(1)
                .fixedSize(horizontal: !fillWidth, vertical: false)
                .foregroundStyle(foreground)
                .padding(.horizontal, compact ? Space.sm : Space.lg)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: compact ? 24 : 30)
                .background(background, in: RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: Metrics.hairline)
                    }
                }
                .offset(y: configuration.isPressed ? 1 : 0)
                .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            kind == .primary ? Theme.onAccent : Theme.ink
        }

        private var background: Color {
            switch kind {
            case .primary: Theme.accent.opacity(configuration.isPressed ? Metrics.pressedOpacity : 1)
            case .secondary: hovering ? Theme.well : Theme.paper
            case .quiet: hovering || configuration.isPressed ? Theme.well : .clear
            }
        }
    }
}
