import SwiftUI

/// Design tokens. A restrained, warm-paper palette with one accent, sans for reading,
/// mono for labels and numbers — the "instrument panel" detail used sparingly.
enum Theme {
    static let paper = dynamic(light: 0xF3F1EC, dark: 0x1C1C1A)
    static let well = dynamic(light: 0xE8E5DE, dark: 0x272724)
    static let ink = dynamic(light: 0x1A1A18, dark: 0xEFECE5)
    static let inkSecondary = dynamic(light: 0x6E6A61, dark: 0x9C988E)
    static let inkTertiary = dynamic(light: 0xA6A196, dark: 0x64615A)
    static let hairline = dynamic(light: 0xD9D5CB, dark: 0x363531)
    static let accent = dynamic(light: 0xFF5A1F, dark: 0xFF6A33)
    /// Text on accent fills. Dark in both modes, like a printed key cap.
    static let onAccent = Color(hex: 0x1A1A18)
    /// The tiny LCD used for the countdown chip — same in both modes.
    static let lcd = Color(hex: 0x1D1E1B)
    static let phosphor = Color(hex: 0xFFE6B0)

    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 480
    static let corner: CGFloat = 12

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
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
            .font(Theme.mono(10, .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// A flat, square-shouldered button styled like a hardware key.
struct KeyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    var fillWidth = false

    func makeBody(configuration: Configuration) -> some View {
        KeyButton(configuration: configuration, kind: kind, fillWidth: fillWidth)
    }

    private struct KeyButton: View {
        let configuration: Configuration
        let kind: Kind
        let fillWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.mono(11, .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    }
                }
                .offset(y: configuration.isPressed ? 1 : 0)
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            kind == .primary ? Theme.onAccent : Theme.ink
        }

        private var background: Color {
            switch kind {
            case .primary: Theme.accent.opacity(configuration.isPressed ? 0.85 : 1)
            case .secondary: hovering ? Theme.well : Theme.paper
            case .quiet: hovering || configuration.isPressed ? Theme.well : .clear
            }
        }
    }
}
