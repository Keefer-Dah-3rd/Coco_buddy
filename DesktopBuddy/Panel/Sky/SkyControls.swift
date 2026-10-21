import SwiftUI

/// A small uppercase label: the comps' kicker ("TODAY", "UP NEXT", "COCO").
struct SkyKicker: View {
    let text: String
    var color: Color = Sky.muted
    var size: CGFloat = 9.5

    init(_ text: String, color: Color = Sky.muted, size: CGFloat = 9.5) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(Sky.text(size, .medium))
            .tracking(size * 0.12)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// A recessed field: the well colour with room around the text.
    func skyField() -> some View {
        padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.well))
    }

    /// A white card with the hairline rim.
    func skyCard(radius: CGFloat = Sky.Radius.card) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Sky.paper))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Sky.line))
    }

}

/// The pill button. `.accent` is the main action, `.ink` the strongest, `.outline` a white
/// pill with a hairline, and `.quiet` a text-like link that darkens on hover.
struct SkyButtonStyle: ButtonStyle {
    enum Kind { case accent, ink, outline, quiet }

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
            .font(Sky.text(style.compact ? 11.5 : 13, .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, style.kind == .quiet ? 4 : (style.compact ? 12 : 16))
            .frame(height: style.kind == .quiet ? 24 : (style.compact ? 28 : 36))
            .frame(maxWidth: style.fillWidth ? .infinity : nil)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(style.kind == .outline ? Sky.line : .clear, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(Sky.Motion.quick, value: hovering)
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch style.kind {
        case .accent, .outline: Sky.ink
        case .ink: .white
        case .quiet: hovering ? Sky.ink : Sky.muted
        }
    }

    private var background: Color {
        switch style.kind {
        case .accent: Sky.accent
        case .ink: Sky.ink
        case .outline: hovering ? Sky.well : Sky.paper
        case .quiet: .clear
        }
    }
}

/// A round icon button: the comps' `.bs-round`.
struct SkyRoundStyle: ButtonStyle {
    var size: CGFloat = 30
    var fill: Color = Sky.well
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

/// A row of pill segments on a well: the selected one fills soft orange. Replaces the old
/// square-cornered key segments, with the same items, shortcuts and bindings.
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
        .background(Capsule().fill(Sky.well))
    }

    @ViewBuilder
    private func segmentKey(_ item: Item) -> some View {
        let selected = item.value == selection
        let button = Button {
            withAnimation(Sky.Motion.quick) { selection = item.value }
        } label: {
            HStack(spacing: 5) {
                Text(item.title)
                    .font(Sky.text(11.5, .medium))
                if let trailing = item.trailing {
                    Text(trailing)
                        .font(Sky.text(10.5, .medium))
                        .monospacedDigit()
                        .opacity(0.65)
                }
            }
            .foregroundStyle(selected ? Sky.ink : Sky.muted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(selected ? Sky.accentSoft : Color.clear))
            .contentShape(Capsule())
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

/// The round check: a ring that fills orange with a tick when done.
struct SkyCheck: View {
    let checked: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle().fill(checked ? Sky.accent : Sky.paper)
            Circle().strokeBorder(checked ? Sky.accent : Sky.ring, lineWidth: 1.5)
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
