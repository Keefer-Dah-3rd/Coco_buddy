import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Setup for Claude, Apple Calendar, Google Calendar, Partiful and Notion. Each section says exactly what it can see,
/// shows "Connected" only after a real request succeeded, and can delete its data.
struct ConnectionsView: View {
    let model: AppModel
    /// The window's height; snapshots render it taller to show every card at once.
    var height: CGFloat = 680

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connections")
                        .font(Sky.display(22))
                        .tracking(-0.4)
                        .foregroundStyle(Sky.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(Buddy.name) works fully on her own. Connect a service only if you want its data in your day.")
                        .font(Sky.text(13))
                        .foregroundStyle(Sky.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
                AssistantSection(service: model.assistant)
                AppleCalendarSection(service: model.appleCalendar, model: model)
                CalendarSection(service: model.calendar, model: model)
                PartifulSection(service: model.partiful)
                if Features.notion {
                    NotionSection(service: model.notion, model: model)
                }
                Text("Keys and sign-ins are kept in your Keychain. Calendar and task details reach Anthropic only when you ask the chat something that needs them — the chat shows each time. Nothing goes to analytics.")
                    .font(Sky.text(11.5))
                    .foregroundStyle(Sky.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 540, height: height)
        .background(Sky.paper)
        // The Sky colours are light-only, like the panel's.
        .environment(\.colorScheme, .light)
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
                    .textFieldStyle(.plain)
                    .font(Sky.text(13))
                    .skyField()
                HStack {
                    Spacer()
                    if service.keyStatus == .verifying { ProgressView().controlSize(.small) }
                    Button("Connect") {
                        let value = key
                        key = ""
                        Task { await service.connect(key: value) }
                    }
                    .buttonStyle(SkyButtonStyle(kind: .accent))
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || service.keyStatus == .verifying)
                }
            case .ready:
                Text("Your key is saved in the Keychain. If Claude's safety screening ever declines a harmless message, Anthropic automatically retries it on another Claude model.")
                    .bodyStyle()
                HStack {
                    Button("Disconnect and forget key") { service.disconnect() }
                        .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                }
            }
            if let problem = service.keyProblem {
                Text(problem).font(Sky.text(11.5)).foregroundStyle(Sky.accentText).fixedSize(horizontal: false, vertical: true)
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
                            .buttonStyle(SkyButtonStyle(kind: .accent))
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
                            .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        Button("Open Privacy Settings") { AppleCalendarService.openPrivacySettings() }
                            .buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
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
            SkyKicker("Calendars \(Buddy.name) reads")
            ForEach(service.calendars) { info in
                HStack(spacing: Space.sm) {
                    Circle().fill(color(info.color)).frame(width: 8, height: 8)
                    Text(info.title).font(Sky.text(12.5)).foregroundStyle(Sky.ink).lineLimit(1)
                    SkyKicker(info.account)
                    Spacer()
                    Toggle("Read \(info.title)", isOn: Binding(get: { service.isIncluded(info) }, set: { service.setIncluded($0, info) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .tint(Sky.accent)
                }
            }
            if service.calendars.isEmpty {
                Text("No calendars found in the Calendar app.").bodyStyle()
            }
            Text("Birthdays, subscribed calendars (holidays) and calendars you can't edit — usually other people's — start switched off.")
                .font(Sky.text(11.5)).foregroundStyle(Sky.faint).fixedSize(horizontal: false, vertical: true)
        }
        if let problem = service.problem(for: .now) {
            Text(problem).font(Sky.text(11.5)).foregroundStyle(Sky.accentText).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Stop using Apple Calendar") { service.disconnect() }
                .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
            Spacer()
            Button("Privacy Settings…") { AppleCalendarService.openPrivacySettings() }
                .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
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
        guard let hex, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return Sky.faint }
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
                    .textFieldStyle(.plain)
                    .font(Sky.text(13))
                    .skyField()
                HStack {
                    if !service.clientID.isEmpty && service.client == nil {
                        Text("That doesn't look like a Google client ID.").font(Sky.text(11.5)).foregroundStyle(Sky.accentText)
                    }
                    Spacer()
                    Button("Sign in with Google") { connect() }
                        .buttonStyle(SkyButtonStyle(kind: .accent))
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
                        .buttonStyle(SkyButtonStyle(kind: .quiet))
                    Button("Sign in again") { connect() }
                        .buttonStyle(SkyButtonStyle(kind: .accent))
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
                    SkySegment(selection: $service.reminderMinutes, items: [
                        .init(0, "Off"), .init(5, "5m"), .init(10, "10m"), .init(15, "15m"),
                    ], height: 22)
                    .frame(width: 200)
                }
                HStack {
                    Button("Disconnect and delete calendar data") { Task { await service.disconnect() } }
                        .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                    Button(service.isRefreshing ? "Refreshing…" : "Refresh") { Task { await service.refresh() } }
                        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        .disabled(service.isRefreshing)
                }
            }

            if let problem = service.problem {
                Text(problem).font(Sky.text(11.5)).foregroundStyle(Sky.accentText).fixedSize(horizontal: false, vertical: true)
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
                            .font(Sky.text(11.5, .medium)).monospacedDigit().foregroundStyle(Sky.muted)
                        Text(event.title).font(Sky.text(12.5)).foregroundStyle(Sky.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Text("Your calendar link is kept in the Keychain. \(Buddy.name) reads it about every half hour.")
                    .bodyStyle()
                HStack {
                    Button("Disconnect and forget events") { service.disconnect() }
                        .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                    Button(service.isRefreshing ? "Refreshing…" : "Refresh") { Task { await service.refresh() } }
                        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        .disabled(service.isRefreshing)
                }
            } else {
                SetupSteps(steps: [
                    ("On partiful.com, on a computer, open any event you're going to.", URL(string: "https://partiful.com")),
                    ("Click the calendar icon under the event details, then choose Google Calendar.", nil),
                    ("Click Copy Link — that's your personal calendar link. Paste it below.", nil),
                ])
                TextField("Calendar link", text: $link, prompt: Text("webcal://… or https://…"))
                    .textFieldStyle(.plain)
                    .font(Sky.text(13))
                    .skyField()
                    .onSubmit(connect)
                HStack {
                    Text("Keep this link private — anyone with it can see your Partiful events.")
                        .font(Sky.text(11.5)).foregroundStyle(Sky.faint).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(connecting ? "Checking…" : "Import events") { connect() }
                        .buttonStyle(SkyButtonStyle(kind: .accent))
                        .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                }
            }

            if let message = problem ?? service.problem {
                Text(message).font(Sky.text(11.5)).foregroundStyle(Sky.accentText).fixedSize(horizontal: false, vertical: true)
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
                if service.status == .needsReconnect {
                    Text("Notion stopped accepting the saved token — it may have expired or been revoked. Paste a new one to carry on; tasks already on your list stay.")
                        .bodyStyle()
                }
                SetupSteps(steps: [
                    ("In Notion's developer portal, create an internal connection (Read content; add Update content to mark tasks done).", URL(string: "https://app.notion.com/developers/connections")),
                    ("Copy its API token from the Configuration tab.", nil),
                    ("Give it your task database: Content access › Edit access, or in Notion open the database › ••• › Connections › Add connection.", nil),
                    ("Paste the token below. A personal access token works too.", nil),
                ])
                Text("A connection sees only the databases you give it — the least access, and what we recommend. A personal access token sees everything you can see, and expires (Notion lets you pick 7 days to a year); \(Buddy.name) asks you to reconnect when it does. Only a workspace's owner can create connections, and some plans limit tokens too: if Notion won't let you create either, ask the owner, or use a workspace of your own.")
                    .bodyStyle()
                SecureField("Token", text: $token, prompt: Text("ntn_…"))
                    .textFieldStyle(.plain)
                    .font(Sky.text(13))
                    .skyField()
                HStack {
                    Spacer()
                    if service.status == .verifying { ProgressView().controlSize(.small) }
                    Button("Connect") {
                        let value = token
                        token = ""
                        Task { await service.connect(token: value) }
                    }
                    .buttonStyle(SkyButtonStyle(kind: .accent))
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
                            .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                        Spacer()
                        Button("Change database") {
                            choosing = true
                            Task { await service.loadDataSources() }
                        }
                        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        Button("Refresh") { Task { await service.refreshTasks() } }
                            .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                    }
                } else {
                    DataSourcePicker(service: service) { source in
                        Task { draft = await service.schemaAndSuggestion(for: source) }
                    }
                    HStack {
                        Button("Disconnect and forget token") { service.disconnect() }
                            .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                        Spacer()
                        if choosing, service.mapping != nil {
                            Button("Cancel") { choosing = false }
                                .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        }
                    }
                }
            }

            if service.isLoading {
                ProgressView().controlSize(.small)
            }
            if let problem = service.problem {
                Text(problem).font(Sky.text(11.5)).foregroundStyle(Sky.accentText).fixedSize(horizontal: false, vertical: true)
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
                SkyKicker("Choose your task database")
                Spacer()
                Button("Reload") { Task { await service.loadDataSources() } }
                    .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
            }
            ForEach(service.dataSources) { source in
                Button { choose(source) } label: {
                    HStack {
                        Text(source.title).font(Sky.text(13)).foregroundStyle(Sky.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Sky.faint)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Sky.well, in: RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous))
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
            SkyKicker("Map “\(draft.dataSourceTitle)”", color: Sky.accentText)
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
                    .font(Sky.text(12.5))
                    .foregroundStyle(Sky.ink)
            }
            .tint(Sky.accent)
            .disabled(!draft.canWriteCompletion)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
                Button("Use this database", action: save).buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
            }
        }
        .padding(14)
        .background(Sky.well, in: RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(Sky.text(16, .semibold)).foregroundStyle(Sky.ink)
                Spacer()
                StatusPill(text: status.0, on: status.1)
            }
            content
        }
        .padding(20)
        .skyCard()
    }
}

/// "Connected" on pale orange with an orange dot; anything else on the well, greyed.
private struct StatusPill: View {
    let text: String
    let on: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(on ? Sky.accent : Sky.faint).frame(width: 6, height: 6)
            SkyKicker(text, color: on ? Sky.accentText : Sky.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(on ? Sky.accentPale : Sky.well))
    }
}

private struct SetupSteps: View {
    let steps: [(String, URL?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(Sky.text(10.5, .semibold))
                        .foregroundStyle(Sky.accentText)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Sky.accentPale))
                    Text(step.0).font(Sky.text(12.5)).foregroundStyle(Sky.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let url = step.1 {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(SkyRoundStyle(size: 22, fill: Sky.paper, tint: Sky.accentText))
                        .help(url.absoluteString)
                    }
                }
            }
        }
        .padding(14)
        .background(Sky.well, in: RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous))
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
            SkyKicker(label, size: 10)
            Spacer()
            content
        }
        .frame(minHeight: 26)
    }
}

private extension Text {
    func bodyStyle() -> some View {
        font(Sky.text(12.5)).foregroundStyle(Sky.muted).fixedSize(horizontal: false, vertical: true)
    }

    func valueStyle() -> some View {
        font(Sky.text(12.5, .medium)).foregroundStyle(Sky.ink).lineLimit(1)
    }
}
