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
                case .chat: ChatView(model: model)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Metrics.panelWidth, height: Metrics.panelHeight)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Theme.hairline))
        .onExitCommand { model.setPanelOpen(false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(model.focus.timer.isRunning ? Theme.accent : Theme.inkTertiary)
                    .frame(width: 6, height: 6)
                MonoLabel(Buddy.name, color: Theme.ink)
                MonoLabel("· " + Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                Spacer()
                Button { model.openConnections() } label: {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(model.agenda.isConnected ? Theme.ink : Theme.inkTertiary)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Connections — Claude and Google Calendar")
                .accessibilityLabel("Connections")
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
                    Text("ESC").font(.style(.monoTiny)).tracking(0.6)
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 5).padding(.vertical, Space.xxxs)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.hairline))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }

            // In Chat the conversation itself is Coco's voice, so the header line steps aside.
            if model.panelTab != .chat {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("›").font(Theme.mono(14, .bold)).foregroundStyle(Theme.accent)
                Text(model.buddyLine)
                    .font(.style(.speechPanel))
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
            }

            KeySegment(selection: $model.panelTab, items: [
                .init(.today, "Today", trailing: todayBadge, shortcut: "1"),
                .init(.focus, "Focus", trailing: focusBadge, shortcut: "2"),
                .init(.chat, "Chat", shortcut: "3"),
            ])
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, 14)
        .padding(.bottom, Space.lg)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.hairline))
    }

    @ViewBuilder
    private func key(_ item: Item) -> some View {
        let selected = item.value == selection
        let button = Button {
            selection = item.value
        } label: {
            HStack(spacing: Space.xs) {
                Text(item.title.uppercased())
                    .font(.style(.monoLabel))
                    .tracking(TypeStyle.monoLabel.tracking)
                if let trailing = item.trailing {
                    Spacer(minLength: 2)
                    Text(trailing)
                        .font(.style(.monoValue))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .foregroundStyle(selected ? Theme.paper : Theme.ink)
            .padding(.horizontal, Space.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Theme.ink : Color.clear)
            .contentShape(Rectangle())
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
