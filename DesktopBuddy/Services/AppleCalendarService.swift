import AppKit
import EventKit
import Observation
import BuddyIntegrations
import os

/// Apple Calendar: every calendar in Calendar.app — iCloud, Google or Exchange accounts
/// added in System Settings, On My Mac — read through EventKit. Read-only: Coco never
/// creates, changes or deletes an Apple Calendar event.
///
/// macOS asks permission the first time the user clicks Connect (never at launch), and the
/// user can turn Apple Calendar off here without touching that permission. Events are read
/// a week at a time, like Google's, and re-read when Calendar.app reports a change — no polling.
@Observable
final class AppleCalendarService {
    enum Access: Equatable {
        /// Never asked.
        case notDetermined
        /// The user said no, or turned it off in System Settings.
        case denied
        /// Blocked by the Mac's administrator (a profile or Screen Time).
        case restricted
        /// "Add events only": Coco can't read with that.
        case writeOnly
        case granted
    }

    private(set) var access: Access
    /// The user connected Apple Calendar in Coco (separate from the macOS permission).
    private(set) var isEnabled: Bool
    /// Every calendar in Calendar.app, for choosing which ones Coco reads.
    private(set) var calendars: [AppleCalendarInfo] = []
    private(set) var weeks: [Date: Week] = [:]
    private(set) var loadingWeeks: Set<Date> = []
    private(set) var weekProblems: [Date: String] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isRequesting = false

    struct Week: Equatable {
        var start: Date
        var events: [CalendarEvent]
    }

    /// Reading events: connected and allowed.
    var isActive: Bool { isEnabled && access == .granted }

    /// Calendars the user switched on or off; the rest follow `isIncludedByDefault`.
    @ObservationIgnored private var choices: [String: Bool]
    @ObservationIgnored private var reader: any AppleCalendarReading
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private var fetches: [Date: Task<Void, Never>] = [:]
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    /// Bumped by every reload, so a slow read that started before a change is thrown away.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "calendar.apple")

    private enum Key {
        static let enabled = "calendar.apple.enabled"
        static let choices = "calendar.apple.calendars"
    }

    init(reader: any AppleCalendarReading = EventKitReader(), defaults: UserDefaults = .standard) {
        self.reader = reader
        self.defaults = defaults
        access = reader.access()
        isEnabled = defaults.bool(forKey: Key.enabled)
        choices = defaults.dictionary(forKey: Key.choices) as? [String: Bool] ?? [:]
        // Calendar.app (or a sync) changed something: re-read what's on screen.
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        }
    }

    // MARK: - Connect / disconnect

    /// Asks macOS for access the first time; afterwards just switches Apple Calendar on.
    func connect() async {
        access = reader.access()
        if access == .notDetermined {
            isRequesting = true
            access = await reader.requestAccess()
            isRequesting = false
        }
        guard access == .granted else {
            log.notice("Apple Calendar access not granted: \(String(describing: self.access), privacy: .public)")
            return
        }
        isEnabled = true
        defaults.set(true, forKey: Key.enabled)
        await reload()
    }

    /// Stops reading Apple Calendar. The macOS permission stays as it is — it's changed in
    /// System Settings › Privacy & Security › Calendars.
    func disconnect() {
        isEnabled = false
        defaults.set(false, forKey: Key.enabled)
        clear()
    }

    /// Part of "Delete all my data".
    func eraseAll() {
        disconnect()
        choices = [:]
        defaults.removeObject(forKey: Key.enabled)
        defaults.removeObject(forKey: Key.choices)
    }

    /// System Settings › Privacy & Security › Calendars, to grant or revoke access.
    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    // MARK: - Calendars

    func isIncluded(_ info: AppleCalendarInfo) -> Bool { choices[info.id] ?? info.isIncludedByDefault }

    func setIncluded(_ included: Bool, _ info: AppleCalendarInfo) {
        choices[info.id] = included
        defaults.set(choices, forKey: Key.choices)
        Task { await reload() }
    }

    private var includedIDs: Set<String> { Set(calendars.filter(isIncluded).map(\.id)) }

    /// Grouped by account ("Google", "iCloud", "On My Mac"), then by name.
    private func sortedCalendars() async -> [AppleCalendarInfo] {
        await reader.calendars().sorted { a, b in
            let account = a.account.localizedCaseInsensitiveCompare(b.account)
            return account == .orderedSame ? a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending : account == .orderedAscending
        }
    }

    // MARK: - Reading

    /// Re-checks the permission and re-reads the calendar list and every loaded week
    /// (always this week).
    func reload() async {
        access = reader.access()
        guard isActive else { clear(); return }
        generation += 1
        calendars = await sortedCalendars()
        var starts = Set(weeks.keys)
        starts.insert(weekStart(for: .now))
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        for start in starts.sorted() { await fetchWeek(start) }
    }

    /// On wake, a new day or a manual refresh. Does nothing until Apple Calendar is connected —
    /// EventKit isn't touched before the user asks for it.
    func refresh() async {
        guard isEnabled else { return }
        reader.refreshSourcesIfNecessary()
        await reload()
    }

    func load(from: Date, to: Date) async throws {
        guard isActive else { throw IntegrationError.notConnected }
        if calendars.isEmpty { calendars = await sortedCalendars() }
        var start = weekStart(for: from)
        let last = weekStart(for: to)
        var starts: [Date] = []
        while start <= last {
            starts.append(start)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { break }
            start = next
        }
        for start in starts where weeks[start] == nil { await fetchWeek(start) }
        if let missing = starts.first(where: { weeks[$0] == nil }) {
            throw IntegrationError.invalidResponse(weekProblems[missing] ?? "Couldn't read Apple Calendar.")
        }
    }

    func prefetch(around day: Date) {
        guard isActive else { return }
        let start = weekStart(for: day)
        for offset in [0, -1, 1] {
            guard let week = calendar.date(byAdding: .weekOfYear, value: offset, to: start), weeks[week] == nil else { continue }
            Task {
                if calendars.isEmpty { calendars = await sortedCalendars() }
                await fetchWeek(week)
            }
        }
    }

    func events(on day: Date) -> [CalendarEvent]? {
        guard isActive, let week = weeks[weekStart(for: day)] else { return nil }
        return Availability.events(on: day, from: week.events, calendar: calendar)
    }

    func isLoading(_ day: Date) -> Bool { loadingWeeks.contains(weekStart(for: day)) }
    func problem(for day: Date) -> String? { weekProblems[weekStart(for: day)] }

    func event(id: String) -> CalendarEvent? {
        weeks.values.lazy.flatMap(\.events).first { $0.id == id }
    }

    func weekStart(for day: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
    }

    /// One read per week at a time; a second caller waits for the first.
    private func fetchWeek(_ start: Date) async {
        if let running = fetches[start] { await running.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.read(start)
        }
        fetches[start] = task
        await task.value
        if fetches[start] == task { fetches[start] = nil }
    }

    private func read(_ start: Date) async {
        guard let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return }
        let ids = includedIDs
        let started = generation
        loadingWeeks.insert(start)
        defer { loadingWeeks.remove(start) }
        do {
            let records = ids.isEmpty ? [] : try await reader.records(from: start, to: end, calendarIDs: ids)
            guard started == generation, isActive else { return }
            weeks[start] = Week(start: start, events: records.compactMap { AppleCalendarMapping.event(from: $0, calendar: calendar) })
            weekProblems[start] = nil
            if start == weekStart(for: .now) { lastUpdated = .now }
        } catch {
            weekProblems[start] = "Couldn't read Apple Calendar: \(error.localizedDescription)"
            log.error("Apple Calendar read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Calendar.app reports changes in bursts (a sync touches many events): wait a moment,
    /// then re-read once. A revoked permission shows up here too.
    private func storeChanged() {
        guard isEnabled else { return }
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    private func clear() {
        generation += 1
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        weeks = [:]
        weekProblems = [:]
        loadingWeeks = []
        calendars = []
        lastUpdated = nil
    }
}

#if DEBUG
extension AppleCalendarService {
    /// Self-test only: a stand-in for EventKit, starting from "never connected".
    func useTestReader(_ reader: any AppleCalendarReading) {
        eraseAll()
        self.reader = reader
        access = reader.access()
    }

    /// Snapshot renderer only: connected, with these calendars and events, no EventKit.
    func loadPreview(calendars: [AppleCalendarInfo], events: [CalendarEvent]) {
        access = .granted
        isEnabled = true
        self.calendars = calendars
        var byWeek: [Date: [CalendarEvent]] = [weekStart(for: .now): []]
        for event in events { byWeek[weekStart(for: event.start), default: []].append(event) }
        weeks = byWeek.mapValues { Week(start: $0.first.map { weekStart(for: $0.start) } ?? weekStart(for: .now), events: $0) }
        for start in weeks.keys { weeks[start]?.start = start }
        lastUpdated = .now
    }
}
#endif

// MARK: - EventKit

/// Snapshots and previews: never asks for access and has no calendars.
struct NoAppleCalendar: AppleCalendarReading {
    func access() -> AppleCalendarService.Access { .notDetermined }
    func requestAccess() async -> AppleCalendarService.Access { .notDetermined }
    func calendars() async -> [AppleCalendarInfo] { [] }
    func records(from: Date, to: Date, calendarIDs: Set<String>) async throws -> [AppleEventRecord] { [] }
    func refreshSourcesIfNecessary() {}
}

/// What the service needs from EventKit — a stand-in replaces it in self-tests.
protocol AppleCalendarReading {
    func access() -> AppleCalendarService.Access
    func requestAccess() async -> AppleCalendarService.Access
    func calendars() async -> [AppleCalendarInfo]
    func records(from: Date, to: Date, calendarIDs: Set<String>) async throws -> [AppleEventRecord]
    func refreshSourcesIfNecessary()
}

/// The real thing. Every EventKit call runs on the store's own actor, off the main thread.
final class EventKitReader: AppleCalendarReading {
    private let store = EventStore()

    func access() -> AppleCalendarService.Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .granted
        @unknown default: .denied
        }
    }

    func requestAccess() async -> AppleCalendarService.Access {
        _ = await store.requestAccess()
        return access()
    }

    func calendars() async -> [AppleCalendarInfo] { await store.calendars() }

    func records(from: Date, to: Date, calendarIDs: Set<String>) async throws -> [AppleEventRecord] {
        await store.records(from: from, to: to, calendarIDs: calendarIDs)
    }

    func refreshSourcesIfNecessary() {
        Task { await store.refreshSources() }
    }
}

/// Owns the one `EKEventStore` (slow to create, so made on first use, off the main thread).
private actor EventStore {
    private var made: EKEventStore?

    private var store: EKEventStore {
        if let made { return made }
        let new = EKEventStore()
        made = new
        return new
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func refreshSources() { store.refreshSourcesIfNecessary() }

    func calendars() -> [AppleCalendarInfo] {
        store.calendars(for: .event)
            .map { calendar in
                AppleCalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                  account: calendar.source?.title ?? "", color: Self.hex(calendar.cgColor),
                                  kind: Self.kind(calendar.type), isWritable: calendar.allowsContentModifications)
            }
    }

    /// Every occurrence overlapping `from..<to` in the chosen calendars — repeating events
    /// come back expanded, one per occurrence.
    func records(from: Date, to: Date, calendarIDs: Set<String>) -> [AppleEventRecord] {
        let chosen = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: chosen)
        return store.events(matching: predicate).map(Self.record)
    }

    nonisolated private static func record(_ event: EKEvent) -> AppleEventRecord {
        let rule = event.recurrenceRules?.first
        let me = event.attendees?.first(where: \.isCurrentUser)
        let others = (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { person -> String? in
            if let name = person.name, !name.isEmpty { return name }
            let address = person.url.absoluteString
            return address.hasPrefix("mailto:") ? String(address.dropFirst(7)) : nil
        }
        return AppleEventRecord(
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: hex(event.calendar?.cgColor),
            title: event.title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            timeZone: event.timeZone?.identifier,
            location: event.location,
            notes: event.notes,
            url: event.url,
            occurrenceDate: event.occurrenceDate,
            isRecurring: event.hasRecurrenceRules || event.isDetached,
            recurrence: rule.map { AppleCalendarMapping.recurrenceText(frequency: frequency($0.frequency), interval: $0.interval) },
            isFree: event.availability == .free,
            isCancelled: event.status == .canceled,
            isDeclined: me?.participantStatus == .declined,
            lastModified: event.lastModifiedDate,
            attendees: others)
    }

    nonisolated private static func frequency(_ value: EKRecurrenceFrequency) -> String {
        switch value {
        case .daily: "daily"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        @unknown default: "yearly"
        }
    }

    nonisolated private static func kind(_ type: EKCalendarType) -> AppleCalendarInfo.Kind {
        switch type {
        case .local: .local
        case .calDAV: .calDAV
        case .exchange: .exchange
        case .subscription: .subscription
        case .birthday: .birthdays
        @unknown default: .subscription
        }
    }

    nonisolated private static func hex(_ color: CGColor?) -> String? {
        guard let color, let rgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return nil }
        let value = { (c: CGFloat) in Int((min(1, max(0, c)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", value(rgb.redComponent), value(rgb.greenComponent), value(rgb.blueComponent))
    }
}
