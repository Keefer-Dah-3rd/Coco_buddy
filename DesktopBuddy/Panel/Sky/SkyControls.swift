import SwiftUI

/// A small uppercase label: the comps' kicker ("TODAY", "UP NEXT", "COCO"). Figma: UI/Kicker.
/// Muted, Ink and Faint are plain Sky/Kicker text; Accent sits on a navy pill in accent text.
struct SkyKicker: View {
    enum Tone { case muted, ink, faint, accent }

    let text: String
    var tone: Tone = .muted
    var color: Color?
    var size: CGFloat?

    init(_ text: String, tone: Tone = .muted) {
        self.text = text
        self.tone = tone
    }

    /// A muted kicker at another size.
    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    /// A plain kicker in any colour, optionally at another size.
    init(_ text: String, color: Color, size: CGFloat? = nil) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        if tone == .accent {
            Text(text)
                .font(SkyType.labelCount.font)
                .tracking(1)
                .foregroundStyle(Sky.accentText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule(style: .circular).fill(Sky.navy))
        } else {
            Text(text)
                .skyType(size.map { SkyType.kicker.sized($0) } ?? .kicker)
                .foregroundStyle(color ?? plainColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var plainColor: Color {
        switch tone {
        case .ink: Sky.ink
        case .faint: Sky.faint
        case .muted, .accent: Sky.muted
        }
    }
}

extension View {
    /// A recessed field: the well colour with room around the text and an orange rim, 1 pt at
    /// rest and 1.5 pt while focused. Figma: UI/Input. Pass `rim: nil` for a rimless well.
    func skyField(rim: Color? = Sky.accent, focused: Bool = false) -> some View {
        padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .circular).fill(Sky.well))
            .overlay {
                if let rim {
                    RoundedRectangle(cornerRadius: Sky.Radius.field, style: .circular)
                        .strokeBorder(focused ? Sky.accent : rim, lineWidth: focused ? 1.5 : 1)
                }
            }
    }

    /// A white card with the hairline rim.
    func skyCard(radius: CGFloat = Sky.Radius.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .circular).fill(Sky.paper))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .circular).strokeBorder(Sky.line))
    }

}

/// The pill button. `.accent` is the main action (white on orange with a black rim), `.ink`
/// the strongest, `.outline` a white pill with a hairline, `.quiet` a text-like link that
/// darkens on hover, and `.confirm` a go-now action in green (Join). Figma: UI/Button.
///
/// Rims here use circular corners, as Figma draws them (no corner smoothing).
struct SkyButtonStyle: ButtonStyle {
    enum Kind { case accent, ink, outline, quiet, confirm }

    var kind: Kind = .accent
    var compact = false
    var fillWidth = false

    func makeBody(configuration: Configuration) -> some View {
        SkyButtonBody(configuration: configuration, style: self)
    }
}

private struct SkyButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: SkyButtonStyle
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .skyType(style.compact ? .labelButtonCompact : .labelButton)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, style.kind == .quiet ? 4 : (style.compact ? 12 : 16))
            .frame(height: style.kind == .quiet ? 24 : (style.compact ? 28 : 36))
            .frame(maxWidth: style.fillWidth ? .infinity : nil)
            .background(Capsule(style: .circular).fill(background))
            .overlay(Capsule(style: .circular).strokeBorder(rim, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule(style: .circular))
            .onHover { hovering = $0 }
            .animation(Sky.Motion.quick, value: hovering)
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch style.kind {
        case .accent, .ink: Sky.paper
        case .outline, .confirm: Sky.ink
        case .quiet: hovering ? Sky.ink : Sky.muted
        }
    }

    private var rim: Color {
        switch style.kind {
        case .accent, .confirm: .black
        case .outline: Sky.line
        case .ink, .quiet: .clear
        }
    }

    private var background: Color {
        switch style.kind {
        case .accent: Sky.accent
        case .ink: Sky.ink
        case .outline: hovering ? Sky.well : Sky.paper
        case .quiet: .clear
        case .confirm: Sky.confirm
        }
    }
}

/// A round icon button: the comps' `.bs-round`. Figma: UI/IconButton — Small 22, Medium 26,
/// Large 30; no fill by default, `Sky.accent` for the prominent tone.
struct SkyRoundStyle: ButtonStyle {
    var size: CGFloat = 30
    var fill: Color = .clear
    var tint: Color = Sky.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(Circle())
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }
}

/// A row of pill segments on a black-rimmed well: the selected one fills orange with white
/// text. Figma: UI/Segment. Same items, shortcuts and bindings as the old key segments.
struct SkySegment<Value: Hashable>: View {
    struct Item {
        var value: Value
        var title: String
        var trailing: String?
        var shortcut: KeyEquivalent?

        init(_ value: Value, _ title: String, trailing: String? = nil, shortcut: KeyEquivalent? = nil) {
            self.value = value
            self.title = title
            self.trailing = trailing
            self.shortcut = shortcut
        }
    }

    @Binding var selection: Value
    let items: [Item]
    var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                segmentKey(item)
            }
        }
        .padding(3)
        .frame(height: height)
        .background(Capsule(style: .circular).fill(Sky.well))
        .overlay(Capsule(style: .circular).strokeBorder(.black, lineWidth: 1))
    }

    @ViewBuilder
    private func segmentKey(_ item: Item) -> some View {
        let selected = item.value == selection
        let button = Button {
            withAnimation(Sky.Motion.quick) { selection = item.value }
        } label: {
            HStack(spacing: 5) {
                Text(item.title)
                    .skyType(.labelButtonCompact)
                if let trailing = item.trailing {
                    Text(trailing)
                        .skyType(.labelCount)
                        .monospacedDigit()
                        .opacity(0.65)
                }
            }
            .foregroundStyle(selected ? Sky.paper : Sky.muted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule(style: .circular).fill(selected ? Sky.accent : Color.clear))
            .overlay(Capsule(style: .circular).strokeBorder(selected ? Color.black : .clear, lineWidth: 1))
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.trailing.map { "\(item.title), \($0)" } ?? item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])

        if let shortcut = item.shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }
}

/// The round check: a ring that fills with an ink tick when done. Figma: UI/Checkbox — green
/// (`Sky.confirm`) with an ink rim; top-level task rows fill orange instead, as in the screens.
struct SkyCheck: View {
    let checked: Bool
    var size: CGFloat = 20
    var fill: Color = Sky.confirm

    var body: some View {
        ZStack {
            Circle().fill(checked ? fill : Sky.paper)
            Circle().strokeBorder(checked ? (fill == Sky.confirm ? Sky.ink : fill) : Sky.ring,
                                  lineWidth: checked ? 1 : 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Sky.ink)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: checked)
    }
}
