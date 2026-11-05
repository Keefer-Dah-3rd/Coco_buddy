import SwiftUI
import BuddyCore

/// The compact panel that opens when you click the buddy. Blue Skies Plus look (Figma:
/// Companion/Panel): the date and three round keys up top, the tabs along the bottom, where the
/// mouse already is after the click on Coco, and a navy rim. Coco's lines aren't shown here —
/// the redesign dropped the speech line — so while the panel is open she only mouths along.
struct PanelRootView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Group {
                        switch model.panelTab {
                        case .today: TodayView(model: model)
                        case .focus: FocusView(model: model)
                        case .chat: ChatView(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    nav
                }
                // The new-task form rises over the list and tabs; the header stays in view above it.
                if let draft = model.taskForm {
                    TaskFormView(model: model, draft: draft)
                        .id(draft.id)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Sky.Radius.card, topTrailingRadius: Sky.Radius.card,
                                                          style: .continuous))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: Sky.Radius.card, topTrailingRadius: Sky.Radius.card,
                                                        style: .continuous).strokeBorder(Sky.line))
                        .shadow(color: Sky.ink.opacity(0.10), radius: 14, y: -3)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3), value: model.taskForm?.id)
        }
        .frame(width: Sky.Size.panelWidth, height: Sky.Size.panelHeight)
        .background(Sky.paper)
        .clipShape(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous).strokeBorder(Sky.navy, lineWidth: 2))
        // The Blue Skies look is light by design, so the panel stays light in dark mode too.
        .environment(\.colorScheme, .light)
        .onExitCommand {
            if model.taskForm != nil { model.taskForm = nil } else { model.setPanelOpen(false) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .skyType(.receiptDisplay)
                .foregroundStyle(Sky.muted)
                .lineLimit(1)
            Spacer()
            linkButton
            barkButton
            closeButton
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
        .buttonStyle(SkyRoundStyle(size: 26, tint: Sky.ink))
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
        .background(Sky.indigo)
        .overlay(alignment: .top) { Rectangle().fill(Sky.ink).frame(height: 2) }
    }

    /// Icon over label, white on the indigo bar. The current tab sits on a navy tile and its icon
    /// fills in. Figma: Companion/NavItem.
    private func navItem(_ tab: PanelTab, _ title: String, symbol: String, trailing: String? = nil, key: Character) -> some View {
        let selected = model.panelTab == tab
        return Button { model.panelTab = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .symbolVariant(selected ? .fill : .none)
                    .frame(height: 16)
                HStack(spacing: 4) {
                    Text(title)
                    if let trailing {
                        Text(trailing)
                            .monospacedDigit()
                            .opacity(0.7)
                    }
                }
                .skyType(.labelNav)
            }
            .foregroundStyle(Sky.paper)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous).fill(selected ? Sky.navy : .clear))
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
        model.focus.timer.isActive ? DurationText.clock(model.focus.remaining) : nil
    }
}
