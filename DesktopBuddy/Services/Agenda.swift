import Foundation
import Observation
import BuddyIntegrations

/// A calendar Coco reads events from: Google Calendar, Apple Calendar, Partiful.
protocol AgendaSource: AnyObject {
    /// "Google Calendar", for messages about it.
    var sourceName: String { get }
    /// Connected (or allowed) and switched on — its events count.
    var isActive: Bool { get }
    /// Events touching a day, or nil while that day isn't loaded.
    func events(on day: Date) -> [CalendarEvent]?
    /// Makes sure every day in `from…to` is loaded; throws if one couldn't be.
    func load(from: Date, to: Date) async throws
    /// Starts loading around a day in the background.
    func prefetch(around day: Date)
    func isLoading(_ day: Date) -> Bool
    func problem(for day: Date) -> String?
    /// A loaded record by its own id.
    func event(id: String) -> CalendarEvent?
    func refresh() async
}

/// Every connected calendar as one schedule, each real event once. The Today card, the
/// week browser, meeting reminders and the chat all read this, so they always agree —
/// counts, free time and "what's next" are worked out after duplicates are merged.
///
/// Merging is for display only (see `CalendarMerge`): every source event is untouched, and
/// a merged event keeps references to all of its records (`alsoIn`), so a change is made
/// to the right one.
@Observable
final class Agenda {
    @ObservationIgnored let sources: [any AgendaSource]
    @ObservationIgnored private let calendar = Calendar.current

    init(sources: [any AgendaSource]) {
        self.sources = sources
    }

    var activeSources: [any AgendaSource] { sources.filter(\.isActive) }
    var isConnected: Bool { sources.contains(where: \.isActive) }
    /// "Google Calendar and Apple Calendar".
    var connectedNames: String {
        let names = activeSources.map(\.sourceName)
        return names.count <= 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// Events touching a day from every connected calendar, duplicates merged; all-day
    /// first, then by start. Nil while no connected calendar has the day loaded.
    func events(on day: Date) -> [CalendarEvent]? {
        let lists = activeSources.compactMap { $0.events(on: day) }
        guard !lists.isEmpty else { return nil }
        return CalendarMerge.merge(lists.flatMap { $0 }, calendar: calendar)
    }

    /// Today, for the Now/Next card, reminders and the chat.
    var schedule: DaySchedule { DaySchedule(events: events(on: .now) ?? []) }

    /// Loads every connected calendar for `from…to`. Returns a note for each calendar that
    /// couldn't be read; throws only when none could.
    @discardableResult
    func load(from: Date, to: Date) async throws -> [String] {
        let active = activeSources
        guard !active.isEmpty else { throw IntegrationError.notConnected }
        var problems: [String] = []
        var firstError: Error?
        for source in active {
            do {
                try await source.load(from: from, to: to)
            } catch {
                firstError = firstError ?? error
                problems.append("\(source.sourceName): \((error as? IntegrationError)?.userMessage ?? error.localizedDescription)")
            }
        }
        if problems.count == active.count, let firstError { throw firstError }
        return problems
    }

    func prefetch(around day: Date) {
        for source in activeSources { source.prefetch(around: day) }
    }

    func refresh() async {
        for source in sources { await source.refresh() }
    }

    func isLoading(_ day: Date) -> Bool { activeSources.contains { $0.isLoading(day) } }

    /// What went wrong reading a day, per calendar ("Apple Calendar: …").
    func problem(for day: Date) -> String? {
        let problems = activeSources.compactMap { source in source.problem(for: day).map { "\(source.sourceName): \($0)" } }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    /// The event as shown (duplicates merged) that has this id — its own or a merged copy's.
    func event(id: String) -> CalendarEvent? {
        guard let record = activeSources.lazy.compactMap({ $0.event(id: id) }).first else { return nil }
        return events(on: record.start)?.first { $0.allIDs.contains(id) }
    }

    /// The Google Calendar record behind a shown event, if it has one — the only kind Coco
    /// can change.
    func googleRecord(for event: CalendarEvent, in google: GoogleCalendarService) -> CalendarEvent? {
        event.references.first { $0.provider == .google }.flatMap { google.event(id: $0.id) }
    }

    /// The next events starting after today, soonest first, from the days already loaded
    /// (up to `days` ahead).
    func comingUp(after now: Date, limit: Int, days: Int = 7) -> [CalendarEvent] {
        var found: [CalendarEvent] = []
        var seen = Set<String>()
        var day = calendar.startOfDay(for: now)
        for _ in 0..<days {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            for event in events(on: day) ?? [] where event.start >= day && seen.insert(event.id).inserted {
                found.append(event)
            }
            if found.count >= limit { break }
        }
        return Array(found.prefix(limit))
    }
}

// MARK: - Sources

extension GoogleCalendarService: AgendaSource {
    var sourceName: String { CalendarProvider.google.displayName }
    /// Connected, or needing a new sign-in — the last events stay on show meanwhile.
    var isActive: Bool { Features.googleSignIn && isConnected }
    func load(from: Date, to: Date) async throws { try await ensureLoaded(from: from, to: to) }
}

extension AppleCalendarService: AgendaSource {
    var sourceName: String { CalendarProvider.apple.displayName }
}
