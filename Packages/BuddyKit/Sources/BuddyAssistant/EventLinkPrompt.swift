import Foundation
import BuddyIntegrations

extension AssistantPrompt {
    /// What read_event_link returns: the event exactly as the page gave it, in the event's own
    /// time zone and the user's, what's missing, and the propose_event details already worked
    /// out in the user's time zone — so the model never does time-zone maths or fills gaps.
    public static func linkedEvent(_ event: LinkedEvent, now: Date, calendar: Calendar = .current) -> String {
        var lines = ["Read from the Partiful page just now. Use only these details; anything \"not listed\" is unknown — ask, don't guess."]
        lines.append("Title: \(event.title)")
        if event.isCancelled { lines.append("Status: the host has marked this event CANCELLED.") }
        if event.isPostponed { lines.append("Status: the host has marked this event POSTPONED.") }

        let userZone = calendar.timeZone
        let eventZone = event.timeZone ?? userZone
        let differentZone = event.timeZone.map { $0.secondsFromGMT(for: event.start ?? now) != userZone.secondsFromGMT(for: event.start ?? now) } ?? false
        func both(_ date: Date) -> String {
            let theirs = stamp(date, in: eventZone)
            guard differentZone else { return "\(theirs) (\(eventZone.identifier))" }
            return "\(theirs) in the event's time zone (\(eventZone.identifier)) = \(stamp(date, in: userZone)) the user's time (\(userZone.identifier))"
        }

        if let start = event.start {
            lines.append("Starts: " + both(start))
            lines.append("Ends: " + (event.end.map(both) ?? "not listed"))
            if event.timeZone == nil { lines.append("The page doesn't state a time zone; times are shown in the user's.") }
            if (event.end ?? start) < now { lines.append("This event is in the past.") }
        } else {
            lines.append("Date and time: not listed (the host may not have set them yet).")
        }
        if let location = event.location {
            lines.append("Where: \(location)")
        } else {
            lines.append("Where: not listed (Partiful can hide the address until a guest RSVPs).")
        }
        if let description = event.description {
            let short = description.count > 600 ? String(description.prefix(600)) + "…" : description
            lines.append("Description: \(short)")
        }
        lines.append("Link: \(event.url.absoluteString)")

        guard let start = event.start, !event.isCancelled, (event.end ?? start) >= now else { return lines.joined(separator: "\n") }
        var local = calendar
        local.timeZone = userZone
        let parts = local.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        let date = CalendarDate(year: parts.year!, month: parts.month!, day: parts.day!).text
        let time = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        var call = "To put it on their calendar: propose_event with title \"\(event.title)\", date \(date), start_time \(time)"
        var caveat: String?
        if let end = event.end {
            let minutes = Int(end.timeIntervalSince(start) / 60)
            if minutes <= 720 {
                call += ", duration_minutes \(minutes)"
            } else {
                caveat = "It runs over 12 hours (until \(stamp(end, in: userZone))), and propose_event can block at most 12 hours — ask which part to put in."
            }
        } else {
            caveat = "No end time is listed: ask how long to block (or when they'll leave) before proposing — don't pick a length yourself."
        }
        if let location = event.location { call += ", location \"\(location)\"" }
        call += ", source_link \"\(event.url.absoluteString)\". The date and time are already in the user's time zone."
        lines.append(call)
        if let caveat { lines.append(caveat) }
        if differentZone { lines.append("The event's time zone differs from the user's — give both times when you confirm.") }
        return lines.joined(separator: "\n")
    }

    /// "Sat 25 Oct 2026, 2:00 PM" in a given time zone.
    private static func stamp(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEE d MMM yyyy, h:mm a"
        return formatter.string(from: date)
    }
}
