import SwiftUI

/// The compact panel that opens when you click the buddy.
struct PanelRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                switch model.panelTab {
                case .today: TodayView(model: model)
                case .focus: FocusView(model: model)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.hairline))
        .onExitCommand { model.setPanelOpen(false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.focus.timer.isRunning ? Theme.accent : Theme.inkTertiary)
                    .frame(width: 6, height: 6)
                MonoLabel(Buddy.name, color: Theme.ink)
                MonoLabel("· " + Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                Spacer()
                Button { model.preferences.voiceEnabled.toggle() } label: {
                    Image(systemName: model.preferences.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.preferences.voiceEnabled ? Theme.ink : Theme.inkTertiary)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.preferences.voiceEnabled ? "\(Buddy.name) speaks aloud — click for text only" : "Text only — click to have \(Buddy.name) speak aloud")
                .accessibilityLabel(model.preferences.voiceEnabled ? "Voice on" : "Voice off")
                Button { model.setPanelOpen(false) } label: {
                    Text("ESC").font(Theme.mono(9, .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.hairline))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("›").font(Theme.mono(14, .bold)).foregroundStyle(Theme.accent)
                Text(model.buddyLine)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(model.buddyLine)
                    .transition(.opacity)
            }
            .frame(minHeight: 36, alignment: .topLeading)
            .animation(.easeOut(duration: 0.2), value: model.buddyLine)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Buddy.name) says: \(model.buddyLine)")

            KeySegment(selection: $model.panelTab, items: [
                .init(.today, "Today", trailing: todayBadge, shortcut: "1"),
                .init(.focus, "Focus", trailing: focusBadge, shortcut: "2"),
            ])
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var todayBadge: String {
        let tasks = model.tasks.today()
        return "\(tasks.filter(\.isCompleted).count)/\(tasks.count)"
    }

    private var focusBadge: String? {
        model.focus.timer.isActive ? AppModel.clock(model.focus.remaining) : nil
    }
}

/// A row of square-shouldered keys acting as a segmented control.
struct KeySegment<Value: Hashable>: View {
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
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                }
                key(item)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
    }

    @ViewBuilder
    private func key(_ item: Item) -> some View {
        let selected = item.value == selection
        let button = Button {
            selection = item.value
        } label: {
            HStack(spacing: 6) {
                Text(item.title.uppercased())
                    .font(Theme.mono(10, .semibold))
                    .tracking(0.8)
                if let trailing = item.trailing {
                    Spacer(minLength: 2)
                    Text(trailing)
                        .font(Theme.mono(11, .medium))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Theme.paper : Theme.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Theme.ink : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])

        if let shortcut = item.shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }
}
