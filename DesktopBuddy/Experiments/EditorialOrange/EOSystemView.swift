#if DEBUG
import SwiftUI
import BuddyCore

// EXPERIMENT — the reference's "System Capabilities" page: each connection or setting is a
// row whose title turns orange and says ENABLED when it's on. States are read live from the
// real services; connecting still happens in the real Connections window (OAuth, Calendar
// permission, keys) — the experiment doesn't duplicate those flows.

struct EOSystemView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EOKicker(EOSection.system.kicker)
                    .padding(.bottom, EO.Space.sm)
                    .eoEntrance(0)
                EODisplay([.plain("System"), .accent("Capabilities")], size: EO.Size.section)
                    .padding(.bottom, EO.Space.lg)
                    .eoEntrance(0)
                EORule()

                EOKicker("Connections", color: EO.Ink.secondary, size: 10)
                    .padding(.top, EO.Space.md)
                    .eoEntrance(1)
                ForEach(Array(connections.enumerated()), id: \.offset) { index, row in
                    EOCapabilityRow(title: row.title, state: row.state, detail: row.detail) { model.openConnections() }
                        .eoEntrance(2 + index)
                }
                if model.agenda.activeSources.count > 1 {
                    Text("\(model.agenda.connectedNames) are read as one schedule — a meeting in two calendars shows once.")
                        .font(EO.font(13, .light, italic: true))
                        .foregroundStyle(EO.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                EOKicker("\(Buddy.name)", color: EO.Ink.secondary, size: 10)
                    .padding(.top, EO.Space.xl)
                    .eoEntrance(6)
                EOCapabilityRow(title: "Barks", state: model.preferences.barksEnabled ? .on : .off,
                                detail: "A single woof now and then") { model.preferences.barksEnabled.toggle() }
                    .eoEntrance(7)
                EOCapabilityRow(title: "Chats now and then", state: model.preferences.chatterEnabled ? .on : .off,
                                detail: "Every 25–45 minutes, never during focus") { model.preferences.chatterEnabled.toggle() }
                    .eoEntrance(8)
                EOCapabilityRow(title: "Sounds", state: model.preferences.soundsMuted ? .off : .on,
                                detail: "Session chimes and barks") { model.preferences.soundsMuted.toggle() }
                    .eoEntrance(9)
                EOCapabilityRow(title: "Always on top", state: model.preferences.alwaysOnTop ? .on : .off,
                                detail: "Above other windows") { model.preferences.alwaysOnTop.toggle() }
                    .eoEntrance(10)

                HStack(spacing: EO.Space.md) {
                    Button("All settings") { model.openSettings() }
                        .buttonStyle(EOLinkButtonStyle())
                    Button("Connections") { model.openConnections() }
                        .buttonStyle(EOLinkButtonStyle())
                }
                .padding(.top, EO.Space.lg)
                .eoEntrance(11)
            }
            .padding(.horizontal, EO.Space.page)
            .padding(.vertical, EO.Space.lg)
        }
        .scrollIndicators(.never)
    }

    private var connections: [(title: String, state: EOCapabilityRow.State, detail: String)] {
        var rows: [(String, EOCapabilityRow.State, String)] = []
        switch model.assistant.keyStatus {
        case .ready: rows.append(("Claude chat", .on, "API key saved in your Keychain"))
        case .verifying: rows.append(("Claude chat", .working("Checking"), "Verifying the key"))
        case .invalid: rows.append(("Claude chat", .problem("Key rejected"), "Paste a new key in Connections"))
        case .missing: rows.append(("Claude chat", .notConnected, "Needs a Claude API key"))
        }
        switch model.calendar.status {
        case .connected: rows.append(("Google Calendar", .on, "Read-only until you confirm a change"))
        case .connecting: rows.append(("Google Calendar", .working("Connecting"), "Finishing sign-in"))
        case .needsReconnect: rows.append(("Google Calendar", .problem("Reconnect"), "Google asked to sign in again"))
        case .disconnected, .needsClientID: rows.append(("Google Calendar", .notConnected, "Sign in with Google"))
        }
        let apple = model.appleCalendar
        switch apple.access {
        case .granted: rows.append(("Apple Calendar", apple.isEnabled ? .on : .off, apple.isEnabled ? "Read-only, from Calendar.app" : "Allowed, switched off"))
        case .denied, .restricted: rows.append(("Apple Calendar", .problem("No access"), "Allow in System Settings › Privacy"))
        case .writeOnly: rows.append(("Apple Calendar", .problem("Add-only"), "Needs full access to read events"))
        case .notDetermined: rows.append(("Apple Calendar", .notConnected, "Asks for access when you connect"))
        }
        switch model.partiful.status {
        case .connected: rows.append(("Partiful", .on, "Your events, shown in \(Buddy.name) only"))
        case .connecting: rows.append(("Partiful", .working("Loading"), "Reading your calendar link"))
        case .disconnected: rows.append(("Partiful", .notConnected, "Paste your personal calendar link"))
        }
        return rows
    }
}

/// One capability: title (orange medium when on, light ink that italicises on hover when
/// off) with its state on the right, and a quiet line of detail.
struct EOCapabilityRow: View {
    enum State: Equatable {
        case on, off, notConnected
        case working(String)
        case problem(String)

        var label: String {
            switch self {
            case .on: "Enabled"
            case .off: "Disabled"
            case .notConnected: "Not connected"
            case .working(let text), .problem(let text): text
            }
        }
    }

    let title: String
    let state: State
    var detail: String?
    let action: () -> Void
    @SwiftUI.State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(EO.font(EO.Size.item, state == .on ? .medium : .light, italic: hovering && state != .on))
                        .tracking(EO.Tracking.tight(EO.Size.item))
                        .foregroundStyle(state == .on ? EO.orange : EO.ink)
                    if let detail {
                        Text(detail).font(EO.font(13, .light)).foregroundStyle(EO.Ink.secondary)
                    }
                }
                Spacer()
                EOKicker(state.label, color: stateColor, size: 12, weight: .medium)
                    .eoPulse(isWorking)
            }
            .padding(.vertical, EO.Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .onHover { hovering = $0 }
        .animation(EO.Motion.hover, value: hovering)
        .animation(EO.Motion.hover, value: state)
        .accessibilityLabel("\(title): \(state.label)")
    }

    private var isWorking: Bool {
        if case .working = state { return true }
        return false
    }

    private var stateColor: Color {
        switch state {
        case .on, .problem: EO.orange
        case .off, .notConnected: EO.ink.opacity(0.3)
        case .working: EO.Ink.secondary
        }
    }
}
#endif
