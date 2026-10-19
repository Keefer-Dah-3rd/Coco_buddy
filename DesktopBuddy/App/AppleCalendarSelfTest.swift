#if DEBUG
import AppKit
import EventKit
import BuddyAssistant
import BuddyIntegrations

/// Runs the real Apple Calendar service, the merged agenda and the chat's calendar tools
/// against a stand-in EventKit (and the stand-in Google Calendar): permission states,
/// duplicates across calendars, changes and deletions in one source, a source failing,
/// access revoked. Debug builds only — build without the sandbox so it can't touch the
/// app's real data:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --apple-calendar-selftest
enum AppleCalendarSelfTest {
    static func run() {
        HTTP.standIn = FakeGoogle.self
        var finished = false
        Task { @MainActor in
            await checks()
            finished = true
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        print("apple calendar selftest: \(passed) passed, \(failed) failed")
    }

    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    private static func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else { failed += 1; print("apple calendar selftest FAILED: \(name)") }
    }

    @MainActor
    private static func checks() async {
        let calendar = Calendar.current
        let model = AppModel(preview: true)
        let apple = model.appleCalendar
        let agenda = model.agenda
        let fake = FakeEventKit()
        apple.useTestReader(fake)

        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
        }
        let busy = 9  // well ahead, so nothing is in the past
        let date = CalendarDate(day(busy), calendar: calendar)

        // 11. Access denied the first time: a clear state, nothing invented.
        fake.status = .notDetermined
        fake.answer = .denied
        await apple.connect()
        check(fake.requests == 1 && apple.access == .denied && !apple.isActive, "denied access leaves Apple Calendar off")
        check(!agenda.isConnected, "with nothing connected there's no calendar")
        let noneToday = await model.performForTest(.getToday)
        check(noneToday.result.contains("Calendar: not connected"), "get_today says the calendar isn't connected")
        let noneSchedule = await model.performForTest(.getSchedule(from: date, to: date))
        check(noneSchedule.isError && noneSchedule.result.contains("No calendar is connected"), "get_schedule refuses to guess")
        await apple.connect()
        check(fake.requests == 1, "after a refusal, Connect doesn't ask macOS again (System Settings does)")

        // Allowed in System Settings, then Connect.
        fake.status = .granted
        await apple.connect()
        check(apple.isActive && agenda.isConnected, "granted access connects")
        check(apple.calendars.map(\.title) == ["Work", "Home", "Birthdays"], "calendars listed by account: \(apple.calendars.map(\.title))")

        // 12. No events today.
        let empty = await model.performForTest(.getToday)
        check(empty.result.contains("Calendar: no events today.") && empty.result.contains("Calendars: Apple Calendar"),
              "an empty day says so")

        // Google (stand-in server) and Apple Calendar holding overlapping copies of one day.
        model.calendar.loadTestSignIn(canChangeEvents: true)
        FakeGoogle.reset([
            .init(id: "standup", title: "Standup", start: at(busy, 9), end: at(busy, 9, 15), mine: true, uid: "standup@google.com"),
            .init(id: "review", title: "Design review", start: at(busy, 10), end: at(busy, 11), mine: true, uid: "review@google.com"),
            .init(id: "client", title: "Client call", start: at(busy, 11), end: at(busy, 12), mine: false, uid: "client@google.com"),
        ])
        fake.events = [
            // 1. The same events, synced into Calendar.app through the Google account.
            fake.event("A-standup", "Standup", at(busy, 9), at(busy, 9, 15), calendar: "work", uid: "standup@google.com"),
            fake.event("A-client", "Client call", at(busy, 11), at(busy, 12), calendar: "work", uid: "client@google.com"),
            // 2. A separate copy with a slightly different title and its own notes.
            fake.event("A-review", "design review 🎨", at(busy, 10), at(busy, 11), calendar: "home", uid: "home-review", notes: "Bring sketches"),
            // 3. Different meetings on the same day, one with the same name later on.
            fake.event("A-standup2", "Standup", at(busy, 17), at(busy, 17, 15), calendar: "home", uid: "home-standup"),
            fake.event("A-dentist", "Dentist", at(busy, 15), at(busy, 16), calendar: "home", uid: "dentist",
                       notes: "Video check-in: https://us02web.zoom.us/j/555"),
            fake.event("A-sam", "1:1", at(busy + 1, 14), at(busy + 1, 14, 30), calendar: "work", uid: "one-on-one", attendees: ["Sam Lee"]),
            // 9. Overlapping the client call.
            fake.event("A-lunch", "Lunch", at(busy, 11, 30), at(busy, 12, 30), calendar: "home", uid: "lunch"),
            // 8. All-day across two days, the EventKit way (ends 23:59:59), and one past midnight.
            fake.event("A-trip", "Trip", day(busy + 2), at(busy + 3, 23, 59), calendar: "home", uid: "trip", allDay: true),
            fake.event("A-late", "Launch watch", at(busy, 23), at(busy + 1, 1), calendar: "work", uid: "late"),
            // Birthdays are off by default.
            fake.event("A-bday", "Ana's birthday", day(busy), day(busy + 1), calendar: "birthdays", uid: "bday", allDay: true),
        ]
        await apple.reload()
        // Through busy + 4: the checks below look at that day, which can start a new week.
        do { try await agenda.load(from: day(busy), to: day(busy + 4)) } catch { check(false, "loading both calendars: \(error)") }

        let shown = agenda.events(on: day(busy)) ?? []
        let titles = shown.map(\.title)
        check(titles == ["Standup", "Design review", "Client call", "Lunch", "Dentist", "Standup", "Launch watch"],
              "each meeting once, distinct ones kept: \(titles)")
        let standup = shown.first { $0.id == "standup" }
        check(standup?.alsoIn.map(\.id) == ["apple:A-standup"] && standup?.alsoIn.first?.match == .identifier,
              "the synced copy is matched by its UID")
        let review = shown.first { $0.id == "review" }
        check(review?.alsoIn.first?.match == .details && review?.notes == "Bring sketches", "the separate copy is matched by its details")
        check(shown.filter { $0.title == "Standup" }.count == 2, "the 5 pm standup is a different meeting")
        check(!titles.contains("Ana's birthday"), "birthdays stay off until switched on")
        check(shown.first { $0.title == "Dentist" }?.meetingLink?.host == "us02web.zoom.us", "a video link is found in the notes")
        check(agenda.events(on: day(busy + 1))?.contains { $0.title == "Launch watch" } == true, "an event past midnight shows the next day too")
        check(agenda.events(on: day(busy + 3))?.contains { $0.title == "Trip" } == true
              && agenda.events(on: day(busy + 4))?.contains { $0.title == "Trip" } == false, "a two-day all-day event covers exactly two days")

        // The chat sees the same merged day.
        let schedule = await model.performForTest(.getSchedule(from: date, to: date))
        check(schedule.result.contains("Total: 7 timed events"), "get_schedule counts after merging")
        check(schedule.result.components(separatedBy: "Design review").count - 1 == 1, "get_schedule lists the review once")
        check(schedule.result.contains("[Apple Calendar · Home — read only in Coco]"), "Apple-only events are marked read only")
        check(schedule.result.contains("[also in Apple Calendar · Work]"), "merged events say where else they are")
        check(schedule.result.contains("Overlapping: Client call, Lunch"), "the overlap is reported")
        check(!schedule.result.contains("Bring sketches") && !schedule.result.contains("Sam Lee"), "notes and attendees stay on the Mac")
        let free = await model.performForTest(.findFreeTime(FreeTimeRequest(from: date, to: date, durationMinutes: 60)))
        check(!free.result.contains("15:00–16:00") && free.result.contains("16:00–17:00"), "Apple events block free time")
        let sam = await model.performForTest(.findEvents(query: "Sam", daysAhead: 14, limit: 5))
        check(sam.result.contains("1:1") && sam.result.contains("with Sam Lee"), "find_events finds the meeting with Sam by attendee")
        check(!sam.result.contains("Dentist"), "find_events lists only matches")

        // Changes go to the right record, or nowhere.
        let dentist = await model.performForTest(.proposeEventDeletion(eventID: "apple:A-dentist"))
        check(dentist.isError && dentist.result.contains("can only read"), "an Apple-only event can't be deleted from Coco")
        let viaApple = await model.performForTest(.proposeEventChange(EventChangeProposal(eventID: "apple:A-standup", title: "Daily standup")))
        check(!viaApple.isError, "a synced copy's id resolves to its Google event")
        if case .change(let target, _)? = model.eventRequests.last?.kind {
            check(target.id == "standup", "the change targets the Google record")
        } else {
            check(false, "a change card for the standup")
        }
        let moveReview = await model.performForTest(.proposeEventChange(EventChangeProposal(eventID: "review", title: "Design crit")))
        check(moveReview.result.contains("separate copy in Apple Calendar · Home"), "the card warns that the separate copy won't change")
        check(FakeGoogle.events.first { $0.id == "standup" }?.title == "Standup", "nothing changed before confirming")

        // 6. Changed, then deleted, in Calendar.app: picked up from its change notice.
        fake.move("A-dentist", to: at(busy, 16), at(busy, 17))
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await wait { agenda.events(on: day(busy))?.first { $0.title == "Dentist" }?.start == at(busy, 16) }
        check(agenda.events(on: day(busy))?.first { $0.title == "Dentist" }?.start == at(busy, 16), "a moved Apple event moves")
        fake.events.removeAll { $0.calendarItemIdentifier == "A-lunch" }
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await wait { agenda.events(on: day(busy))?.contains { $0.title == "Lunch" } == false }
        check(agenda.events(on: day(busy))?.contains { $0.title == "Lunch" } == false, "a deleted Apple event goes")
        // Deleted in Google, still in Calendar.app until it syncs: shown once, from Apple.
        FakeGoogle.events.removeAll { $0.id == "client" }
        try? await model.calendar.ensureLoaded(from: day(busy), to: day(busy), maxAge: 0)
        let client = agenda.events(on: day(busy))?.filter { $0.title == "Client call" } ?? []
        check(client.count == 1 && client.first?.provider == .apple, "an event deleted in Google shows once until Apple syncs")

        // Choosing calendars.
        if let home = apple.calendars.first(where: { $0.id == "home" }) {
            apple.setIncluded(false, home)
            await wait { agenda.events(on: day(busy))?.contains { $0.title == "Dentist" } == false }
            check(agenda.events(on: day(busy))?.contains { $0.title == "Dentist" } == false, "switching a calendar off hides its events")
            apple.setIncluded(true, home)
            await wait { agenda.events(on: day(busy))?.contains { $0.title == "Dentist" } == true }
        }

        // 10. Apple Calendar temporarily unreadable: Google still answers, and the chat says it's partial.
        fake.failReads = true
        let far = day(busy + 21)
        let partial = await model.performForTest(.getSchedule(from: CalendarDate(far, calendar: calendar), to: CalendarDate(far, calendar: calendar)))
        check(!partial.isError && partial.result.contains("Incomplete — couldn't read Apple Calendar"), "a failing calendar is reported, not hidden")
        fake.failReads = false

        // 7. Access revoked while running.
        fake.status = .denied
        NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil)
        await wait { !apple.isActive }
        check(apple.access == .denied && apple.events(on: day(busy)) == nil, "revoking access clears Apple events")
        check(agenda.events(on: day(busy))?.contains { $0.title == "Dentist" } == false
              && agenda.events(on: day(busy))?.contains { $0.title == "Standup" } == true, "Google keeps working without Apple")

        // Stop using it (permission untouched).
        fake.status = .granted
        await apple.connect()
        check(apple.isActive, "granted again: back on")
        apple.disconnect()
        check(!apple.isActive && fake.status == .granted, "Stop using Apple Calendar leaves the macOS permission alone")
        model.calendar.loadPreview(events: [], account: "")
    }

    /// Waits up to two seconds for something that happens after a change notice.
    @MainActor
    private static func wait(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }
}

/// A stand-in for EventKit: three calendars and whatever events a test puts in them.
final class FakeEventKit: AppleCalendarReading {
    var status: AppleCalendarService.Access = .notDetermined
    /// What the permission prompt answers.
    var answer: AppleCalendarService.Access = .granted
    var requests = 0
    var failReads = false
    var events: [AppleEventRecord] = []
    let calendarList = [
        AppleCalendarInfo(id: "work", title: "Work", account: "Google", color: "#1BADF8", kind: .calDAV, isWritable: true),
        AppleCalendarInfo(id: "home", title: "Home", account: "iCloud", color: "#63DA38", kind: .calDAV, isWritable: true),
        AppleCalendarInfo(id: "birthdays", title: "Birthdays", account: "Other", kind: .birthdays, isWritable: false),
    ]

    func access() -> AppleCalendarService.Access { status }

    func requestAccess() async -> AppleCalendarService.Access {
        guard status == .notDetermined else { return status }
        requests += 1
        status = answer
        return status
    }

    func calendars() async -> [AppleCalendarInfo] { status == .granted ? calendarList : [] }

    func records(from: Date, to: Date, calendarIDs: Set<String>) async throws -> [AppleEventRecord] {
        if failReads { throw CocoaError(.fileReadUnknown) }
        return events.filter { calendarIDs.contains($0.calendarID) && $0.start < to && $0.end > from }
    }

    func refreshSourcesIfNecessary() {}

    func event(_ id: String, _ title: String, _ start: Date, _ end: Date, calendar: String, uid: String,
               allDay: Bool = false, notes: String? = nil, attendees: [String] = []) -> AppleEventRecord {
        let info = calendarList.first { $0.id == calendar }
        var end = end
        if allDay { end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: end.addingTimeInterval(-1)) ?? end }
        return AppleEventRecord(eventIdentifier: id, calendarItemIdentifier: id, externalIdentifier: uid, calendarID: calendar,
                                calendarTitle: info?.title ?? "", calendarColor: info?.color, title: title, start: start, end: end,
                                isAllDay: allDay, notes: notes, attendees: attendees)
    }

    func move(_ id: String, to start: Date, _ end: Date) {
        guard let index = events.firstIndex(where: { $0.calendarItemIdentifier == id }) else { return }
        events[index].start = start
        events[index].end = end
    }
}
#endif
