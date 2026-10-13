import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Setup for Google Calendar and Notion. Each section says exactly what it can see,
/// shows "Connected" only after a real request succeeded, and can delete its data.
struct ConnectionsView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    MonoLabel("Connections", color: Theme.ink)
                    Text("\(Buddy.name) works fully on her own. Connect a service only if you want its data in your day.")
                        .font(.style(.body))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AssistantSection(service: model.assistant)
                AppleCalendarSection(service: model.appleCalendar, model: model)
                CalendarSection(service: model.calendar, model: model)
                PartifulSection(service: model.partiful)
                if Features.notion {
                    NotionSection(service: model.notion, model: model)
                }
                Text("Keys and sign-ins are kept in your Keychain. Calendar and task details reach Anthropic only when you ask the chat something that needs them — the chat shows each time. Nothing goes to analytics.")
                    .font(.style(.caption))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, 34)
            .padding(.bottom, Space.xxl)
        }
        .frame(width: 540, height: 680)
        .background(Theme.paper)
    }
}

// MARK: - AI assistant

private struct AssistantSection: View {
    let service: AssistantService
    @State private var key = ""

    var body: some View {
        Card(title: "Claude (chat)", status: statusLabel) {
            Text("Powers the Chat tab. Sent to Anthropic: your chat messages, and — only when \(Buddy.name) needs them to answer — your tasks, focus timer and the calendar days it needs. The chat marks each time that happens. Usage is billed to your Anthropic account.")
                .bodyStyle()
            Row("Model") { Text("Claude Opus 5.5 · low effort").valueStyle() }

            switch service.keyStatus {
            case .missing, .invalid, .verifying:
                SetupSteps(steps: [
                    ("Create an API key in the Anthropic Console.", URL(string: "https://console.anthropic.com/settings/keys")),
                    ("Paste it below — it's checked with a free request, then saved to your Keychain.", nil),
                ])
                SecureField("API key", text: $key, prompt: Text("sk-ant-…"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    if service.keyStatus == .verifying { ProgressView().controlSize(.small) }
                    Button("Connect") {
                        let value = key
                        key = ""
                        Task { await service.connect(key: value) }
                    }
                    .buttonStyle(KeyButtonStyle(kind: .primary))
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || service.keyStatus == .verifying)
                }
            case .ready:
                Text("Your key is saved in the Keychain. If Claude's safety screening ever declines a harmless message, Anthropic automatically retries it on another Claude model.")
                    .bodyStyle()
                HStack {
                    Button("Disconnect and forget key") { service.disconnect() }
                        .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                }
            }
            if let problem = service.keyProblem {
                Text(problem).font(.style(.caption)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLabel: (String, Bool) {
        switch service.keyStatus {
        case .ready: ("Connected", true)
        case .verifying: ("Checking key", false)
        case .invalid: ("Key rejected", false)
        case .missing: ("Not connected", false)
        }
    }
}

// MARK: - Apple Calendar

/// Calendar.app's calendars, read-only. Access is asked for only when the user clicks
/// Connect, and every state macOS can be in gets its own explanation.
private struct AppleCalendarSection: View {
    let service: AppleCalendarService
    let model: AppModel

    var body: some View {
        Card(title: "Apple Calendar", status: statusLabel) {
            Text("Reads the calendars in the Calendar app on this Mac — iCloud, Google, Exchange or On My Mac — for the days you look at: titles, times, places and video links, to show your week, find open time and remind you of meetings. Read-only: \(Buddy.name) never adds, changes or deletes an Apple Calendar event. An event that's also in your Google Calendar is shown once.")
                .bodyStyle()

            if service.isActive {
                connected
            } else {
                switch service.access {
                case .notDetermined, .granted:
                    if service.access == .notDetermined {
                        Text("macOS will ask whether Desktop Buddy may see your calendars. Choose Allow Full Access.")
                            .bodyStyle()
                    }
                    HStack {
                        Spacer()
                        if service.isRequesting { ProgressView().controlSize(.small) }
                        Button("Connect Apple Calendar") { Task { await service.connect() } }
                            .buttonStyle(KeyButtonStyle(kind: .primary))
                            .disabled(service.isRequesting)
                    }
                case .denied, .writeOnly:
                    Text(service.access == .denied
                         ? "Calendar access is turned off for Desktop Buddy, so \(Buddy.name) can't see Apple Calendar. Everything else keeps working. To allow it: System Settings › Privacy & Security › Calendars › Desktop Buddy › Full Access, then click Check again."
                         : "Desktop Buddy can only add events, not read them. To show your schedule, choose Full Access in System Settings › Privacy & Security › Calendars, then click Check again.")
                        .bodyStyle()
                    HStack {
                        Spacer()
                        Button("Check again") { Task { await service.connect() } }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        Button("Open Privacy Settings") { AppleCalendarService.openPrivacySettings() }
                            .buttonStyle(KeyButtonStyle(kind: .primary, compact: true))
                    }
                case .restricted:
                    Text("Calendar access is blocked on this Mac by its administrator (a profile or Screen Time), so \(Buddy.name) can't read Apple Calendar.")
                        .bodyStyle()
                }
            }
        }
    }

    @ViewBuilder
    private var connected: some View {
        Row("Today") {
            Text("\(service.events(on: .now)?.filter { !$0.isAllDay }.count ?? 0) events"
                 + (service.lastUpdated.map { " · read \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                .valueStyle()
        }
        VStack(alignment: .leading, spacing: Space.xs) {
            MonoLabel("Calendars \(Buddy.name) reads")
            ForEach(service.calendars) { info in
                HStack(spacing: Space.sm) {
                    Circle().fill(color(info.color)).frame(width: 8, height: 8)
                    Text(info.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                    MonoLabel(info.account)
                    Spacer()
                    Toggle("Read \(info.title)", isOn: Binding(get: { service.isIncluded(info) }, set: { service.setIncluded($0, info) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
            }
            if service.calendars.isEmpty {
                Text("No calendars found in the Calendar app.").bodyStyle()
            }
            Text("Birthdays, subscribed calendars (holidays) and calendars you can't edit — usually other people's — start switched off.")
                .font(.style(.caption)).foregroundStyle(Theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
        }
        if let problem = service.problem(for: .now) {
            Text(problem).font(.style(.caption)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Stop using Apple Calendar") { service.disconnect() }
                .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
            Spacer()
            Button("Privacy Settings…") { AppleCalendarService.openPrivacySettings() }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                .help("Turn calendar access off completely in System Settings › Privacy & Security › Calendars")
        }
    }

    private var statusLabel: (String, Bool) {
        if service.isActive { return ("Connected", true) }
        switch service.access {
        case .denied: return ("No access", false)
        case .restricted: return ("Blocked", false)
        case .writeOnly: return ("Add-only access", false)
        case .notDetermined, .granted: return ("Not connected", false)
        }
    }

    private func color(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return Theme.inkTertiary }
        return Color(hex: value)
    }
}

// MARK: - Google Calendar

private struct CalendarSection: View {
    @Bindable var service: GoogleCalendarService
    let model: AppModel

    var body: some View {
        Card(title: "Google Calendar", status: statusLabel) {
            Text("Reads your primary calendar for the days you look at — titles, times, location, colour and meeting links — to show your week, find open time and remind you of meetings. \(Buddy.name) only adds, moves or deletes an event after you confirm it, and Google asks you once for that permission. \(model.calendar.canChangeEvents ? "Event changes: allowed." : "Event changes: not allowed yet.")")
                .bodyStyle()

            switch service.status {
            case .needsClientID, .disconnected:
                SetupSteps(steps: [
                    ("Create a project in Google Cloud Console.", URL(string: "https://console.cloud.google.com/projectcreate")),
                    ("Enable the Google Calendar API.", URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")),
                    ("OAuth consent screen: External, Testing — add your Google account as a test user.", URL(string: "https://console.cloud.google.com/auth/audience")),
                    ("Create an OAuth client ID of type iOS with bundle ID com.keefer.DesktopBuddy.", URL(string: "https://console.cloud.google.com/auth/clients")),
                    ("Paste the client ID below and sign in.", nil),
                ])
                TextField("Client ID", text: $service.clientID, prompt: Text("1234…apps.googleusercontent.com"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if !service.clientID.isEmpty && service.client == nil {
                        Text("That doesn't look like a Google client ID.").font(.style(.caption)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Button("Sign in with Google") { connect() }
                        .buttonStyle(KeyButtonStyle(kind: .primary))
                        .disabled(service.client == nil)
                }

            case .connecting:
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Google…").bodyStyle()
                }

            case .needsReconnect:
                Text("Google no longer accepts the saved sign-in. Your last schedule is still shown until you reconnect.")
                    .bodyStyle()
                HStack {
                    Spacer()
                    Button("Disconnect") { Task { await service.disconnect() } }
                        .buttonStyle(KeyButtonStyle(kind: .quiet))
                    Button("Sign in again") { connect() }
                        .buttonStyle(KeyButtonStyle(kind: .primary))
                }

            case .connected:
                Row("Account") { Text(service.accountName ?? "Connected").valueStyle() }
                Text("Your sign-in is saved in the Keychain, so \(Buddy.name) stays connected when you quit and reopen her.")
                    .bodyStyle()
                Row("Today") {
                    Text("\(service.schedule.events.count) events" + (service.lastUpdated.map { " · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                        .valueStyle()
                }
                Row("Remind me") {
                    KeySegment(selection: $service.reminderMinutes, items: [
                        .init(0, "Off"), .init(5, "5m"), .init(10, "10m"), .init(15, "15m"),
                    ], height: 22)
                    .frame(width: 200)
                }
                HStack {
                    Button("Disconnect and delete calendar data") { Task { await service.disconnect() } }
                        .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                    Button(service.isRefreshing ? "Refreshing…" : "Refresh") { Task { await service.refresh() } }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        .disabled(service.isRefreshing)
                }
            }

            if let problem = service.problem {
                Text(problem).font(.style(.caption)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLabel: (String, Bool) {
        switch service.status {
        case .connected: ("Connected", true)
        case .needsReconnect: ("Reconnect", false)
        case .connecting: ("Connecting", false)
        case .needsClientID, .disconnected: ("Not connected", false)
        }
    }

    private func connect() {
        Task { await service.connect(presentingFrom: NSApp.keyWindow) }
    }
}

// MARK: - Partiful

/// Imports the user's Partiful events from their personal calendar link. Read-only: the events
/// show in Coco's calendar and count for free time; nothing is written anywhere.
/// (Not private: the Partiful self-test renders it on its own.)
struct PartifulSection: View {
    let service: PartifulFeedService
    @State private var link = ""
    @State private var problem: String?
    @State private var connecting = false

    var body: some View {
        Card(title: "Partiful", status: service.isConnected ? ("Connected", true) : ("Not connected", false)) {
            Text("Shows your Partiful events in \(Buddy.name)'s calendar, so she knows when you're busy and can talk about them. Read-only: nothing is added to Google Calendar or changed on Partiful.")
                .bodyStyle()

            if service.isConnected {
                Row("Events") {
                    Text(summary).valueStyle()
                }
                ForEach(upcoming, id: \.uid) { event in
                    HStack(spacing: Space.sm) {
                        Text(event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .font(.style(.monoValue)).foregroundStyle(Theme.inkSecondary)
                        Text(event.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Text("Your calendar link is kept in the Keychain. \(Buddy.name) reads it about every half hour.")
                    .bodyStyle()
                HStack {
                    Button("Disconnect and forget events") { service.disconnect() }
                        .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                    Button(service.isRefreshing ? "Refreshing…" : "Refresh") { Task { await service.refresh() } }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        .disabled(service.isRefreshing)
                }
            } else {
                SetupSteps(steps: [
                    ("On partiful.com, on a computer, open any event you're going to.", URL(string: "https://partiful.com")),
                    ("Click the calendar icon under the event details, then choose Google Calendar.", nil),
                    ("Click Copy Link — that's your personal calendar link. Paste it below.", nil),
                ])
                TextField("Calendar link", text: $link, prompt: Text("webcal://… or https://…"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                HStack {
                    Text("Keep this link private — anyone with it can see your Partiful events.")
                        .font(.style(.caption)).foregroundStyle(Theme.inkTertiary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(connecting ? "Checking…" : "Import events") { connect() }
                        .buttonStyle(KeyButtonStyle(kind: .primary))
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                }
            }

            if let message = problem ?? service.problem {
                Text(message).font(.style(.caption)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var upcoming: [ICalendar.Event] {
        Array(service.feedEvents.filter { $0.end > .now }.prefix(3))
    }

    private var summary: String {
        let count = service.feedEvents.filter { $0.end > .now }.count
        let updated = service.lastUpdated.map { " · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return (count == 1 ? "1 upcoming" : "\(count) upcoming") + updated
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        problem = nil
        Task {
            problem = await service.connect(link)
            if problem == nil { link = "" }
            connecting = false
        }
    }
}

// MARK: - Notion

private struct NotionSection: View {
    let service: NotionService
    let model: AppModel
    @State private var token = ""
    @State private var draft: NotionMapping?
    @State private var choosing = false

    var body: some View {
        Card(title: "Notion", status: statusLabel) {
            Text("Reads tasks from one database you choose, so you can pick some for today. If you allow it, it can mark a task done — and asks you each time.")
                .bodyStyle()

            switch service.status {
            case .disconnected, .verifying, .needsReconnect:
                SetupSteps(steps: [
                    ("Create an internal integration (Read content; add Update content to mark tasks done).", URL(string: "https://www.notion.so/profile/integrations")),
                    ("Copy its Internal Integration Secret.", nil),
                    ("In Notion, open your task database › ••• › Connections, and add the integration.", nil),
                    ("Paste the secret below. A personal access token works too.", nil),
                ])
                SecureField("Token", text: $token, prompt: Text("ntn_…"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    if service.status == .verifying { ProgressView().controlSize(.small) }
                    Button("Connect") {
                        let value = token
                        token = ""
                        Task { await service.connect(token: value) }
                    }
                    .buttonStyle(KeyButtonStyle(kind: .primary))
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || service.status == .verifying)
                }

            case .connected:
                Row("Workspace") { Text(service.identity ?? "Connected").valueStyle() }
                if let draft {
                    MappingEditor(service: service, draft: Binding(get: { draft }, set: { self.draft = $0 })) {
                        let confirmed = draft
                        self.draft = nil
                        choosing = false
                        Task { await service.save(confirmed) }
                    } cancel: {
                        self.draft = nil
                    }
                } else if let mapping = service.mapping, !choosing {
                    Row("Database") { Text(mapping.dataSourceTitle).valueStyle() }
                    Row("Open tasks") {
                        Text("\(service.openTasks.count)" + (service.lastUpdated.map { " · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                            .valueStyle()
                    }
                    Row("Mark done in Notion") {
                        Text(mapping.writeBackEnabled ? "Allowed — asks each time" : "Off").valueStyle()
                    }
                    HStack {
                        Button("Disconnect and forget token") { service.disconnect() }
                            .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                        Spacer()
                        Button("Change database") {
                            choosing = true
                            Task { await service.loadDataSources() }
                        }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        Button("Refresh") { Task { await service.refreshTasks() } }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                    }
                } else {
                    DataSourcePicker(service: service) { source in
                        Task { draft = await service.schemaAndSuggestion(for: source) }
                    }
                    HStack {
                        Button("Disconnect and forget token") { service.disconnect() }
                            .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                        Spacer()
                        if choosing, service.mapping != nil {
                            Button("Cancel") { choosing = false }
                                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        }
                    }
                }
            }

            if service.isLoading {
                ProgressView().controlSize(.small)
            }
            if let problem = service.problem {
                Text(problem).font(.style(.caption)).foregroundStyle(Theme.accent).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusLabel: (String, Bool) {
        switch service.status {
        case .connected: (service.mapping == nil ? "Choose a database" : "Connected", service.mapping != nil)
        case .verifying: ("Checking token", false)
        case .needsReconnect: ("Reconnect", false)
        case .disconnected: ("Not connected", false)
        }
    }
}

private struct DataSourcePicker: View {
    let service: NotionService
    let choose: (NotionDataSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                MonoLabel("Choose your task database")
                Spacer()
                Button("Reload") { Task { await service.loadDataSources() } }
                    .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
            }
            ForEach(service.dataSources) { source in
                Button { choose(source) } label: {
                    HStack {
                        Text(source.title).font(.style(.body)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.horizontal, Space.md)
                    .frame(height: 30)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Lets the user confirm or change how their columns map onto tasks.
private struct MappingEditor: View {
    let service: NotionService
    @Binding var draft: NotionMapping
    let save: () -> Void
    let cancel: () -> Void

    private var schema: NotionSchema { service.schema ?? NotionSchema(properties: []) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            MonoLabel("Map “\(draft.dataSourceTitle)”", color: Theme.accent)
            Row("Task name") {
                propertyPicker(selection: Binding(get: { draft.titleProperty }, set: { draft.titleProperty = $0 }),
                               types: ["title"], allowNone: false)
            }
            Row("Done when") {
                propertyPicker(selection: Binding(get: { draft.statusProperty }, set: { draft.use(status: schema.property(named: $0)) }),
                               types: ["status", "select", "checkbox"], allowNone: true)
            }
            if let status = schema.property(named: draft.statusProperty), status.type != "checkbox" {
                Row("…is set to") {
                    Picker("Done value", selection: Binding(get: { draft.doneValue ?? "" }, set: { value in
                        draft.doneValue = value
                        if !draft.doneValues.contains(value) { draft.doneValues = [value] }
                    })) {
                        ForEach(status.options, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Row("Due date") {
                propertyPicker(selection: $draft.dueProperty, types: ["date"], allowNone: true)
            }
            Row("Priority") {
                propertyPicker(selection: $draft.priorityProperty, types: ["select", "status"], allowNone: true)
            }
            Toggle(isOn: $draft.writeBackEnabled) {
                Text("Let \(Buddy.name) mark tasks done in Notion (she asks first, every time)")
                    .font(.style(.bodySmall))
                    .foregroundStyle(Theme.ink)
            }
            .disabled(!draft.canWriteCompletion)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                Button("Use this database", action: save).buttonStyle(KeyButtonStyle(kind: .primary, compact: true))
            }
        }
        .padding(Space.md)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func propertyPicker(selection: Binding<String?>, types: [String], allowNone: Bool) -> some View {
        Picker("Property", selection: selection) {
            if allowNone { Text("None").tag(String?.none) }
            ForEach(schema.properties.filter { types.contains($0.type) }, id: \.name) { property in
                Text(property.name).tag(Optional(property.name))
            }
        }
        .labelsHidden()
        .frame(width: 200)
    }

    private func propertyPicker(selection: Binding<String>, types: [String], allowNone: Bool) -> some View {
        propertyPicker(selection: Binding<String?>(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } }),
                       types: types, allowNone: allowNone)
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    let title: String
    let status: (String, Bool)
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack {
                Text(title).font(.style(.titleSection)).foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(status.1 ? Theme.accent : Theme.inkTertiary).frame(width: 6, height: 6)
                    MonoLabel(status.0, color: status.1 ? Theme.ink : Theme.inkSecondary)
                }
            }
            content
        }
        .padding(Space.xl)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.section, style: .continuous))
    }
}

private struct SetupSteps: View {
    let steps: [(String, URL?)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text("\(index + 1)").font(.style(.monoMark)).foregroundStyle(Theme.accent).frame(width: 12)
                    Text(step.0).font(.style(.bodySmall)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let url = step.1 {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                        }
                        .help(url.absoluteString)
                    }
                }
            }
        }
        .padding(Space.md)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

private struct Row<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            MonoLabel(label)
            Spacer()
            content
        }
        .frame(minHeight: 24)
    }
}

private extension Text {
    func bodyStyle() -> some View {
        font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }

    func valueStyle() -> some View {
        font(.style(.bodySmallEmphasis)).foregroundStyle(Theme.ink).lineLimit(1)
    }
}
