import SwiftUI
import BuddyCore

/// The compact panel that opens when you click the buddy. Blue Skies Plus look: the speech line
/// up top, the tabs along the bottom, where the mouse already is after the click on Coco.
struct PanelRootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.panelTab {
                case .today: TodayView(model: model)
                case .focus: FocusView(model: model)
                case .chat: ChatView(model: model)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            nav
        }
        .frame(width: Metrics.panelWidth, height: Metrics.panelHeight)
        .background(Sky.paper)
        .clipShape(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous).strokeBorder(Sky.line))
        // The Blue Skies look is light by design, so the panel stays light in dark mode too.
        .environment(\.colorScheme, .light)
        .onExitCommand { model.setPanelOpen(false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.focus.timer.isRunning ? Sky.accent : Sky.faint)
                    .frame(width: 7, height: 7)
                Text(Buddy.name)
                    .font(Sky.display(19))
                    .tracking(-0.4)
                    .foregroundStyle(Sky.ink)
                Text("· " + Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(Sky.text(11.5))
                    .foregroundStyle(Sky.muted)
                Spacer()
                linkButton
                barkButton
                closeButton
            }

            // In Chat the conversation itself is Coco's voice, so the speech line steps aside.
            if model.panelTab != .chat {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("›")
                        .font(Sky.text(15, .bold))
                        .foregroundStyle(Sky.accentText)
                    Text(model.buddyLine)
                        .font(Sky.text(13))
                        .foregroundStyle(Sky.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(model.buddyLine)
                        .transition(.opacity)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Sky.accentPale))
                .animation(Sky.Motion.quick, value: model.buddyLine)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Buddy.name) says: \(model.buddyLine)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var linkButton: some View {
        let connected = model.agenda.isConnected || (Features.notion && model.notion.isConnected)
        return Button { model.openConnections() } label: {
            Image(systemName: "link")
        }
        .buttonStyle(SkyRoundStyle(size: 26, tint: connected ? Sky.ink : Sky.faint))
        .help("Connections — Claude, calendars and Notion")
        .accessibilityLabel("Connections")
    }

    private var barkButton: some View {
        // Coco doesn't speak aloud (her lines are text), so this only mutes her barks.
        let barking = model.preferences.barksEnabled && !model.preferences.soundsMuted
        return Button { model.setBarking(!barking) } label: {
            Image(systemName: barking ? "speaker.wave.2.fill" : "speaker.slash")
        }
        .buttonStyle(SkyRoundStyle(size: 26, tint: barking ? Sky.ink : Sky.faint))
        .help(barking ? "\(Buddy.name) barks — click to mute her" : "Muted — click to let \(Buddy.name) bark")
        .accessibilityLabel(barking ? "Barking on" : "Barking off")
    }

    private var closeButton: some View {
        Button { model.setPanelOpen(false) } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(SkyRoundStyle(size: 26, tint: Sky.muted))
        .help("Close (Esc)")
        .accessibilityLabel("Close")
    }

    /// Today, Focus and Chat along the bottom, with ⌘1–⌘3 as before.
    private var nav: some View {
        HStack(spacing: 4) {
            navItem(.today, "Today", symbol: "sun.max", trailing: todayBadge, key: "1")
            navItem(.focus, "Focus", symbol: "timer", trailing: focusBadge, key: "2")
            navItem(.chat, "Chat", symbol: "heart", key: "3")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(Sky.line).frame(height: 1) }
    }

    /// Icon over label. The current tab sits on a pale tile and its icon fills in.
    private func navItem(_ tab: PanelTab, _ title: String, symbol: String, trailing: String? = nil, key: Character) -> some View {
        let selected = model.panelTab == tab
        return Button { model.panelTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .symbolVariant(selected ? .fill : .none)
                HStack(spacing: 4) {
                    Text(title)
                    if let trailing {
                        Text(trailing)
                            .monospacedDigit()
                            .opacity(0.7)
                    }
                }
                .font(Sky.text(10, .medium))
            }
            .foregroundStyle(selected ? Sky.ink : Sky.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Sky.accentPale : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        .help("\(title) (⌘\(String(key)))")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
