#if DEBUG
import AppKit
import SwiftUI

// EXPERIMENT — "Coco Plush Toybox". Debug builds only, on screen only with `--plush-toybox`.
// Nothing in the shared design system was changed for it.
//
// Source of truth: Figma Make file AKhsjPOyTgqtgZQzI8Oadf, style "Plush Toybox"
// (src/themes/PlushToybox.tsx + src/index.css). Values copied from it. Shares Coco's art
// (EOCoco), entrance/pulse helpers and sample data with the other experiments.

/// Plush Toybox tokens — prefix `PT`.
enum PT {
    // MARK: Color

    /// `#E0FBFC` — the room, sunken wells, pillow rims.
    static let aqua = Color(hex: 0xE0FBFC)
    /// `#F7FDFE` — the card and input wells.
    static let ice = Color(hex: 0xF7FDFE)
    /// `#C2F0F4` — the card's 4pt border.
    static let rim = Color(hex: 0xC2F0F4)
    static let white = Color.white
    /// `#2B2D42` — text.
    static let ink = Color(hex: 0x2B2D42)
    /// `#8D99AE` — secondary text and placeholders.
    static let slate = Color(hex: 0x8D99AE)
    /// `#06D6A0` / `#04AF82` — mint: header, Coco's bubbles, "on".
    static let mint = Color(hex: 0x06D6A0)
    static let mintEdge = Color(hex: 0x04AF82)
    /// `#EF476F` / `#D12B55` — berry: Up Next, Add, send, high priority.
    static let berry = Color(hex: 0xEF476F)
    static let berryEdge = Color(hex: 0xD12B55)
    /// `#FFD166` / `#E6AF2E` — butter: Save, the chat avatar, the welcome block.
    static let butter = Color(hex: 0xFFD166)
    static let butterEdge = Color(hex: 0xE6AF2E)

    // MARK: Type — Nunito Black

    /// Nunito (the reference's face) when installed; SF Pro Rounded otherwise.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        let style = switch weight {
        case .black, .heavy: "Black"
        case .bold: "ExtraBold"
        case .semibold: "Bold"
        default: "SemiBold"
        }
        let name = "Nunito-\(style)"
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

    // MARK: Shape

    /// `max-w-[420px] h-[750px] rounded-[60px] border-[4px] border-[#C2F0F4]`.
    static let cardSize = CGSize(width: 420, height: 750)
    static let cardRadius: CGFloat = 60
    static let roomMargin: CGFloat = 24

    enum Radius {
        static let chip: CGFloat = 20   // rounded-[20px]
        static let field: CGFloat = 24  // rounded-[24px]
        static let pillow: CGFloat = 32 // rounded-[32px]
        static let sheet: CGFloat = 48  // rounded-[48px]
    }

    // MARK: Motion

    enum Motion {
        /// `active:translate-y-[6px] transition-all` (150ms).
        static let squish = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)
        /// `.animate-pop` — 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275).
        static let pop = Animation.timingCurve(0.175, 0.885, 0.32, 1.275, duration: 0.3)
        /// `.animate-slide-up` — 0.6s cubic-bezier(0.16, 1, 0.3, 1).
        static let slideUp = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)
        /// `.animate-float` — 4s ease-in-out, 10pt up and back.
        static let float = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)
        static let toggle = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)
    }
}

// MARK: - Puffy surface

extension View {
    /// The reference's pillow: a rounded fill with a darker band sunk into its bottom
    /// (`inset 0 -Npx 0 edge`), a soft coloured glow under it, and an optional rim.
    func ptPuff(_ fill: Color, edge: Color, radius: CGFloat, depth: CGFloat = 8,
                glow: Color? = nil, rim: Color? = nil) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(alignment: .bottom) {
                    // The inset shadow: clipped to the shape, so it follows the corners.
                    Rectangle().fill(edge).frame(height: depth)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    if let rim { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(rim, lineWidth: 4) }
                }
                .shadow(color: (glow ?? .clear), radius: 12, y: 12)
        }
    }

    /// A sunken well: `shadow-[inset_0_4px_8px_rgba(0,0,0,0.05)]`.
    func ptWell(_ fill: Color = PT.ice, radius: CGFloat = PT.Radius.field) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 4)
                        .blur(radius: 3)
                        .offset(y: 2)
                        .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
        }
    }

    func ptPop() -> some View { modifier(PTPop()) }
}

private struct PTPop: ViewModifier {
    @State private var shown = false
    @Environment(\.eoStill) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || still || reduceMotion ? 1 : 0.95)
            .onAppear { if !still { withAnimation(PT.Motion.pop) { shown = true } } }
    }
}

/// The squishy button: pressing flattens the sunk band and pushes the face down.
struct PTSquish: ButtonStyle {
    enum Kind {
        case mint, berry, butter, pillow, quiet
        var fill: Color {
            switch self {
            case .mint: PT.mint
            case .berry: PT.berry
            case .butter: PT.butter
            case .pillow: PT.white
            case .quiet: PT.aqua
            }
        }
        var edge: Color {
            switch self {
            case .mint: PT.mintEdge
            case .berry: PT.berryEdge
            case .butter: PT.butterEdge
            case .pillow: PT.aqua
            case .quiet: PT.rim
            }
        }
        var text: Color {
            switch self {
            case .mint, .berry: .white
            case .butter, .pillow, .quiet: PT.ink
            }
        }
        var glow: Color? {
            switch self {
            case .mint: PT.mint.opacity(0.3)
            case .berry: PT.berry.opacity(0.3)
            case .butter: PT.butter.opacity(0.35)
            case .pillow, .quiet: PT.ink.opacity(0.06)
            }
        }
    }

    var kind: Kind = .mint
    var radius: CGFloat = PT.Radius.pillow
    var depth: CGFloat = 8
    var fill = false
    var padding = EdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)
    var size: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        Squished(configuration: configuration, style: self)
    }

    private struct Squished: View {
        let configuration: Configuration
        let style: PTSquish
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed && isEnabled
            configuration.label
                .font(PT.font(style.size))
                .foregroundStyle(style.kind.text)
                .padding(style.padding)
                .padding(.bottom, style.depth * 0.5)
                .frame(maxWidth: style.fill ? .infinity : nil)
                .ptPuff(style.kind.fill, edge: style.kind.edge, radius: style.radius,
                        depth: pressed ? 2 : style.depth, glow: pressed ? nil : style.kind.glow,
                        rim: style.kind == .pillow ? PT.aqua : nil)
                .scaleEffect(hovering && !pressed && isEnabled ? 1.02 : 1)
                .offset(y: pressed ? 6 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: style.radius, style: .continuous))
                .onHover { hovering = $0 }
                .animation(PT.Motion.squish, value: pressed)
                .animation(PT.Motion.pop, value: hovering)
        }
    }
}

/// A rounded chip — "UP NEXT", "1/5", "ONLINE & COZY".
struct PTChip: View {
    let text: String
    var fill: Color = .white.opacity(0.2)
    var color: Color = .white
    var size: CGFloat = 11

    init(_ text: String, fill: Color = .white.opacity(0.2), color: Color = .white, size: CGFloat = 11) {
        self.text = text
        self.fill = fill
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(PT.font(size))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .lineLimit(1)
    }
}

/// The sunken dot (`w-8 h-8 bg-[#E0FBFC] inset shadow`) that puffs up mint when done.
struct PTDot: View {
    let checked: Bool

    var body: some View {
        ZStack {
            if checked {
                Circle().fill(PT.mint)
                    .overlay(alignment: .bottom) { Rectangle().fill(PT.mintEdge).frame(height: 4) }
                    .clipShape(Circle())
                Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            } else {
                Circle().fill(PT.aqua)
                    .overlay(Circle().stroke(Color.black.opacity(0.1), lineWidth: 3).blur(radius: 1).offset(y: 1.5).mask(Circle()))
            }
        }
        .frame(width: 32, height: 32)
        .scaleEffect(checked ? 1.08 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: checked)
    }
}

/// The puffy switch: `w-16 h-10`, berry when on, white thumb slides (300ms).
struct PTToggle: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? PT.berry : PT.aqua)
            .overlay(Capsule().stroke(Color.black.opacity(0.1), lineWidth: 4).blur(radius: 2).offset(y: 2).mask(Capsule()))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.1), radius: 1, y: 1).padding(6)
            }
            .frame(width: 64, height: 40)
            .animation(PT.Motion.toggle, value: isOn)
    }
}

/// The room behind the card: plain `#E0FBFC`, soft as a nursery wall.
struct PTRoom: View {
    var body: some View {
        PT.aqua.ignoresSafeArea()
    }
}

/// The frosted "Hi!" chip from the welcome block, saying what this is.
struct PTExperimentTag: View {
    var body: some View {
        Text("Experiment")
            .font(PT.font(12))
            .foregroundStyle(PT.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.55)))
            .help("Design experiment — Plush Toybox. Not the production panel. Launched with --plush-toybox.")
            .accessibilityLabel("Experiment: Plush Toybox. Not the production panel.")
    }
}
#endif
