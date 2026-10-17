#if DEBUG
import SwiftUI

// EXPERIMENT — Editorial Orange building blocks. Every repeated pattern in the reference
// lives here once, so the screens only compose them.

// MARK: - Type

/// The uppercase, widely tracked label the reference uses for every section name and state:
/// "VOL. 1 — TASKS", "UP NEXT", "ENABLED", "COCO".
struct EOKicker: View {
    let text: String
    var color: Color = EO.orange
    var size: CGFloat = EO.Size.small
    var weight: EO.Weight = .bold

    init(_ text: String, color: Color = EO.orange, size: CGFloat = EO.Size.small, weight: EO.Weight = .bold) {
        self.text = text
        self.color = color
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Text(text.uppercased())
            .font(EO.font(size, weight))
            .tracking(EO.Tracking.widest(size))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// One line of a display headline; `accent` sets it in orange italic — the reference's
/// signature move ("The Digital *Mascot*", "System *Capabilities*").
struct EOLine: Hashable {
    var text: String
    var accent = false

    static func plain(_ text: String) -> EOLine { EOLine(text: text) }
    static func accent(_ text: String) -> EOLine { EOLine(text: text, accent: true) }
}

/// A stacked display headline at `leading-[0.9] tracking-tighter font-medium`.
struct EODisplay: View {
    let lines: [EOLine]
    var size: CGFloat = EO.Size.display

    init(_ lines: [EOLine], size: CGFloat = EO.Size.display) {
        self.lines = lines
        self.size = size
    }

    init(_ text: String, size: CGFloat = EO.Size.display) {
        self.init([.plain(text)], size: size)
    }

    var body: some View {
        // DM Sans's natural line box is ~1.3em; pull lines together to the reference's 0.9.
        VStack(alignment: .leading, spacing: -0.4 * size) {
            ForEach(lines, id: \.self) { line in
                Text(line.text)
                    .font(EO.font(size, .medium, italic: line.accent))
                    .tracking(EO.Tracking.tighter(size))
                    .foregroundStyle(line.accent ? EO.orange : EO.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Rules and surfaces

/// A 1pt rule. The reference uses three weights: full ink (input tops), 20% (section
/// rules) and 10% (between rows).
struct EORule: View {
    var color: Color = EO.Ink.rule
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// The 20pt dot grid behind every page (`circle r=1 fill=#1A1A1A fill-opacity=0.05`).
struct EODotGrid: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y: CGFloat = 1
            while y < size.height {
                var x: CGFloat = 1
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += 20
                }
                y += 20
            }
            context.fill(dots, with: .color(EO.Ink.dot))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The 12pt orange rule across the top of the page.
struct EOTopRule: View {
    var body: some View { Rectangle().fill(EO.orange).frame(height: EO.topRule) }
}

/// Clear label so the experiment is never mistaken for the real panel.
struct EOExperimentBadge: View {
    var body: some View {
        Text("EXPERIMENT · EDITORIAL ORANGE")
            .font(EO.font(9, .bold))
            .tracking(EO.Tracking.widest(9))
            .foregroundStyle(EO.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Rectangle().strokeBorder(EO.orange, lineWidth: 1))
            .help("Design experiment — not the production panel. Launched with --editorial-orange.")
            .accessibilityLabel("Experiment: Editorial Orange. Not the production panel.")
    }
}

// MARK: - Buttons

/// `w-16 h-16 rounded-full border` → fills orange on hover (500ms). The welcome "→" key;
/// here also start / pause / send.
struct EOCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 64
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, diameter: diameter, filled: filled)
    }

    private struct Styled: View {
        let configuration: Configuration
        let diameter: CGFloat
        let filled: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let lit = (hovering || filled) && isEnabled
            configuration.label
                .font(EO.font(diameter >= 48 ? 20 : 15, .light))
                .foregroundStyle(lit ? EO.paper : EO.ink)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(lit ? EO.orange : Color.clear))
                .overlay(Circle().strokeBorder(lit ? EO.orange : EO.ink, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .opacity(isEnabled ? 1 : 0.3)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(EO.Motion.hover, value: hovering)
                .animation(EO.Motion.quick, value: configuration.isPressed)
        }
    }
}

/// Text with a 2pt underline — the reference's "Confirm" / "Discard" pair.
struct EOUnderlineButtonStyle: ButtonStyle {
    enum Kind {
        /// Orange text and rule; reaches right on hover (`hover:pr-4`).
        case accent
        /// 40% ink, no rule, ink on hover.
        case quiet
        /// Paper on an orange sheet.
        case inverse
    }

    var kind: Kind = .accent
    var size: CGFloat = EO.Size.body

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, kind: kind, size: size)
    }

    private struct Styled: View {
        let configuration: Configuration
        let kind: Kind
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(EO.font(size, kind == .quiet ? .light : .medium))
                .foregroundStyle(foreground)
                .padding(.bottom, 4)
                .padding(.trailing, kind != .quiet && hovering ? 16 : 0)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(rule).frame(height: 2)
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && isEnabled }
                .animation(EO.Motion.hover, value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .accent: EO.orange
            case .quiet: hovering ? EO.ink : EO.Ink.muted
            case .inverse: EO.paper
            }
        }

        private var rule: Color {
            switch kind {
            case .accent: EO.orange
            case .quiet: .clear
            case .inverse: EO.paper
            }
        }
    }
}

/// Full-width outlined button: "Save Entry". Inverts on hover (500ms).
struct EOOutlineButtonStyle: ButtonStyle {
    /// On the orange sheet: paper outline, fills paper with orange text on hover.
    var onOrange = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, onOrange: onOrange)
    }

    private struct Styled: View {
        let configuration: Configuration
        let onOrange: Bool
        @State private var hovering = false

        var body: some View {
            let line = onOrange ? EO.paper : EO.ink
            configuration.label
                .font(EO.font(EO.Size.body, .medium))
                .tracking(EO.Tracking.wide(EO.Size.body))
                .foregroundStyle(hovering ? (onOrange ? EO.orange : EO.paper) : line)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Rectangle().fill(hovering ? (onOrange ? EO.paper : EO.orange) : Color.clear))
                .overlay(Rectangle().strokeBorder(hovering && !onOrange ? EO.orange : line, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(EO.Motion.hover, value: hovering)
        }
    }
}

/// A small kicker-styled action: "WEEK →", "CONNECT →". The arrow steps right on hover.
struct EOLinkButtonStyle: ButtonStyle {
    var color: Color = EO.ink
    var arrow = "→"

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, color: color, arrow: arrow)
    }

    private struct Styled: View {
        let configuration: Configuration
        let color: Color
        let arrow: String
        @State private var hovering = false

        var body: some View {
            HStack(spacing: hovering ? 8 : 5) {
                configuration.label
                    .font(EO.font(11, .bold))
                    .tracking(EO.Tracking.widest(11))
                    .textCase(.uppercase)
                if !arrow.isEmpty {
                    Text(arrow).font(EO.font(12, .light))
                }
            }
            .foregroundStyle(hovering ? EO.orange : color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(EO.Motion.hover, value: hovering)
        }
    }
}

/// A row of words where the chosen one is underlined in medium italic — the reference's
/// "Low / *High*" priority picker, used for every small choice.
struct EOTextTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var size: CGFloat = EO.Size.lead
    var onOrange = false
    var spacing: CGFloat = EO.Space.sm

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Tab(title: option.1, selected: option.0 == selection, size: size, onOrange: onOrange) {
                    withAnimation(EO.Motion.quick) { selection = option.0 }
                }
            }
        }
    }

    private struct Tab: View {
        let title: String
        let selected: Bool
        let size: CGFloat
        let onOrange: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            let ink = onOrange ? EO.paper : EO.ink
            Button(action: action) {
                Text(title)
                    .font(EO.font(size, selected ? .medium : .light, italic: selected))
                    .foregroundStyle(selected || hovering ? ink : ink.opacity(0.6))
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selected ? ink : hovering ? ink.opacity(0.5) : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(EO.Motion.quick, value: hovering)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// The task check: the reference's `w-4 h-4 rounded-full border` — fills orange when done.
struct EOCheck: View {
    let checked: Bool
    var onOrange = false

    var body: some View {
        ZStack {
            Circle()
                .fill(checked ? EO.orange : Color.clear)
            Circle()
                .strokeBorder(checked ? EO.orange : (onOrange ? EO.paper : EO.ink), lineWidth: 1)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(EO.paper)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .scaleEffect(checked ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: checked)
    }
}

/// `animate-pulse` — opacity breathing for things waiting on the user ("!", listening).
struct EOPulse: ViewModifier {
    var active = true
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active && dim && !reduceMotion ? 0.5 : 1)
            .onAppear { if active { withAnimation(EO.Motion.pulse) { dim = true } } }
    }
}

// MARK: - Motion

/// The reference's page entrance: fade in and slide up 20pt on the slide-up curve,
/// staggered by `index` so a page assembles top to bottom. Plain fade with Reduce Motion.
struct EOEntrance: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.eoStill) private var still

    func body(content: Content) -> some View {
        let visible = shown || still
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : EO.Motion.slideDistance)
            .onAppear {
                guard !still else { return }
                let delay = Double(min(index, 8)) * EO.Motion.stagger
                withAnimation((reduceMotion ? EO.Motion.fadeIn : EO.Motion.slideUp).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func eoEntrance(_ index: Int = 0) -> some View { modifier(EOEntrance(index: index)) }
    func eoPulse(_ active: Bool = true) -> some View { modifier(EOPulse(active: active)) }
}

/// True when rendering stills (snapshots): entrances start finished, Coco holds a pose.
private struct EOStillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var eoStill: Bool {
        get { self[EOStillKey.self] }
        set { self[EOStillKey.self] = newValue }
    }
}

// MARK: - Fields

extension View {
    /// The reference's bare input: no box, light weight, placeholder at 30% ink.
    func eoField(size: CGFloat = EO.Size.lead, weight: EO.Weight = .light, italic: Bool = false, color: Color = EO.ink) -> some View {
        textFieldStyle(.plain)
            .font(EO.font(size, weight, italic: italic))
            .foregroundStyle(color)
    }
}
#endif
