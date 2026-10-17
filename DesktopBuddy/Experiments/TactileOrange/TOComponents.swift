#if DEBUG
import AppKit
import SwiftUI

// EXPERIMENT — "Coco Tactile Orange". Debug builds only, on screen only with
// `--tactile-orange`. Nothing in the shared design system was changed for it.
//
// Source of truth: Figma Make file AKhsjPOyTgqtgZQzI8Oadf, style "Tactile Orange"
// (src/themes/OrganicOrangeTactile.tsx + src/index.css). Values copied from it.
// Shares Coco's masthead art (EOCoco), entrance and pulse helpers with the Editorial
// Orange experiment; everything visual below is its own.

/// Tactile Orange tokens — prefix `TO`.
enum TO {
    // MARK: Color

    /// `#D5D3C8` — the desk behind the card, with 16pt polka dots.
    static let desk = Color(hex: 0xD5D3C8)
    /// `#E8E5D9` — the card, and recessed wells.
    static let card = Color(hex: 0xE8E5D9)
    /// `#F5F4EE` — the embossed editor sheet and chat page.
    static let paper = Color(hex: 0xF5F4EE)
    static let white = Color.white
    /// `#D5D3C8` — the bottom edge under white and well keys.
    static let edge = Color(hex: 0xD5D3C8)
    /// `#A8A69D` — the solid drop under the whole card.
    static let drop = Color(hex: 0xA8A69D)
    static let orange = Color(hex: 0xF25C05)
    /// `#c24a04` — under orange keys; also the "on" icon tile.
    static let orangeEdge = Color(hex: 0xC24A04)
    /// `#913702` — under the "on" icon tile.
    static let orangeDeep = Color(hex: 0x913702)
    static let ink = Color(hex: 0x1A1A1A)
    static let inkSecondary = Color(hex: 0x1A1A1A).opacity(0.6)
    static let inkMuted = Color(hex: 0x1A1A1A).opacity(0.4)

    // MARK: Type — Fredoka

    /// Fredoka (the reference's face) when installed; SF Pro Rounded otherwise.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        let style = weight == .bold || weight == .heavy || weight == .black ? "Bold"
            : weight == .semibold ? "SemiBold" : weight == .medium ? "Medium" : weight == .light ? "Light" : "Regular"
        let name = "Fredoka-\(style)"
        if Installed.check(name) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight, design: .rounded)
    }

    private enum Installed {
        nonisolated(unsafe) private static var known: [String: Bool] = [:]
        static func check(_ name: String) -> Bool {
            if let cached = known[name] { return cached }
            let found = NSFont(name: name, size: 12) != nil
            known[name] = found
            return found
        }
    }

    // MARK: Shape & space

    /// `max-w-[420px] h-[750px] rounded-[48px] border-8 border-white`.
    static let cardSize = CGSize(width: 420, height: 750)
    static let cardRadius: CGFloat = 48
    static let rim: CGFloat = 8
    /// `shadow-[0_24px_0_#A8A69D]`.
    static let cardDrop: CGFloat = 24
    /// Space around the card on the desk.
    static let deskMargin: CGFloat = 20
    /// `p-8`.
    static let page: CGFloat = 32

    enum Radius {
        static let tile: CGFloat = 16   // rounded-[16px]
        static let field: CGFloat = 20  // rounded-[20px]
        static let key: CGFloat = 24    // rounded-[24px]
        static let sheet: CGFloat = 32  // rounded-[32px]
        static let bubble: CGFloat = 40 // rounded-[40px]
    }

    // MARK: Motion

    enum Motion {
        /// `active:translate-y + transition-all` (Tailwind's 150ms).
        static let press = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)
        /// `.animate-pop` — 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275), 0.95 → 1.05 → 1.
        static let pop = Animation.timingCurve(0.175, 0.885, 0.32, 1.275, duration: 0.3)
        /// `duration-300` toggle thumb.
        static let toggle = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)
        /// `animate-bounce` at 2s.
        static let bounce = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
    }
}

// MARK: - The key

/// The reference's one idea, applied everywhere: a rounded face over a thicker bottom edge.
/// Pressing sinks the face onto the edge (`active:border-b-0 active:translate-y`).
struct TOKey: ButtonStyle {
    enum Kind {
        case orange, white, well, ink
        var face: Color {
            switch self {
            case .orange: TO.orange
            case .white: TO.white
            case .well: TO.card
            case .ink: TO.ink
            }
        }
        var edge: Color {
            switch self {
            case .orange: TO.orangeEdge
            case .white, .well: TO.edge
            case .ink: .black
            }
        }
        var text: Color {
            switch self {
            case .orange, .ink: TO.white
            case .white, .well: TO.ink
            }
        }
    }

    var kind: Kind = .white
    var radius: CGFloat = TO.Radius.key
    var depth: CGFloat = 6
    var fill = false
    var padding = EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
    var size: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        Pressed(configuration: configuration, style: self)
    }

    private struct Pressed: View {
        let configuration: Configuration
        let style: TOKey
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(TO.font(style.size))
                .foregroundStyle(style.kind.text)
                .padding(style.padding)
                .frame(maxWidth: style.fill ? .infinity : nil)
                .toFace(style.kind.face, edge: style.kind.edge, radius: style.radius,
                        depth: pressed ? 0 : style.depth, lift: hovering && isEnabled ? 1 : 0)
                .offset(y: pressed ? style.depth : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous))
                .onHover { hovering = $0 }
                .animation(TO.Motion.press, value: pressed)
                .animation(TO.Motion.press, value: hovering)
        }
    }
}

extension View {
    /// A rounded face with a solid bottom edge of `depth` points below it.
    func toFace(_ face: Color, edge: Color, radius: CGFloat, depth: CGFloat, lift: CGFloat = 0) -> some View {
        background {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(edge)
                    .offset(y: depth + lift)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(face)
            }
        }
        .padding(.bottom, depth + lift)
    }

    /// The reference's `.animate-pop` on appear.
    func toPop() -> some View { modifier(TOPop()) }
}

private struct TOPop: ViewModifier {
    @State private var shown = false
    @Environment(\.eoStill) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || still || reduceMotion ? 1 : 0.95)
            .onAppear { if !still { withAnimation(TO.Motion.pop) { shown = true } } }
    }
}

// MARK: - Pieces

/// A recessed white field over a grey edge; the edge turns orange and the field sinks 2pt
/// while you type in it (`focus-within:border-[#F25C05] focus-within:translate-y-[2px]`).
struct TOField<Content: View>: View {
    var focused: Bool
    var face: Color = TO.white
    var radius: CGFloat = TO.Radius.key
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .toFace(face, edge: focused ? TO.orange : TO.edge, radius: radius, depth: focused ? 2 : 4)
            .offset(y: focused ? 2 : 0)
            .animation(TO.Motion.press, value: focused)
    }
}

/// A small rounded pill label — "UP NEXT", "ONLINE", "NEXT · IN 18M".
struct TOPill: View {
    let text: String
    var face: Color = TO.white.opacity(0.2)
    var color: Color = TO.white

    init(_ text: String, face: Color = TO.white.opacity(0.2), color: Color = TO.white) {
        self.text = text
        self.face = face
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(TO.font(11))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(face))
            .lineLimit(1)
    }
}

/// The ring check: grey ring on a well, fills orange with a white tick.
struct TOCheck: View {
    let checked: Bool

    var body: some View {
        ZStack {
            Circle().fill(checked ? TO.orange : TO.card)
            Circle().strokeBorder(checked ? TO.orangeEdge : TO.edge, lineWidth: 3)
            if checked {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(checked ? 1.1 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: checked)
    }
}

/// The "Power Ups" switch: a sunken pill whose white thumb slides (300ms).
struct TOToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? TO.orangeEdge : TO.card)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 24, height: 24).shadow(color: .black.opacity(0.12), radius: 1, y: 1).padding(4)
            }
            .frame(width: 56, height: 32)
            .padding(.bottom, 2)
            .background(alignment: .bottom) { Capsule().fill(isOn ? TO.orangeDeep : TO.edge).frame(height: 32) }
            .animation(TO.Motion.toggle, value: isOn)
    }
}

/// The desk: `#D5D3C8` with 16pt polka dots (`circle cx=8 cy=8 r=1, 10% ink`).
struct TODesk: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += 16
                }
                y += 16
            }
            context.fill(dots, with: .color(TO.ink.opacity(0.1)))
        }
        .background(TO.desk)
        .allowsHitTesting(false)
    }
}

/// The tilted orange tag the reference uses for "v2.0" — here it says what this is.
struct TOExperimentTag: View {
    var body: some View {
        Text("Experiment")
            .font(TO.font(12))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .toFace(TO.orange, edge: TO.orangeEdge, radius: 99, depth: 4)
            .rotationEffect(.degrees(6))
            .help("Design experiment — Tactile Orange. Not the production panel. Launched with --tactile-orange.")
            .accessibilityLabel("Experiment: Tactile Orange. Not the production panel.")
    }
}
#endif
