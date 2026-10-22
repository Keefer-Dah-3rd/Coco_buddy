#if DEBUG
import AppKit
import BuddyAssistant
import BuddyIntegrations

/// Runs the real calendar service and the chat's calendar tools against a stand-in Google
/// Calendar answering inside the process — paging, caching, shared fetches, creating, moving
/// and deleting, failures and expired access. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --calendar-selftest
enum CalendarSelfTest {
    static func run() {
        // These drive the Google sign-in code, which ships switched off.
        Features.googleSignIn = true
        HTTP.standIn = FakeGoogle.self
        var finished = false
        Task { @MainActor in
            await checks()
            finished = true
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        print("calendar selftest: \(passed) passed, \(failed) failed")
    }

    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    private static func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else { failed += 1; print("calendar selftest FAILED: \(name)") }
    }

    @MainActor
    private static func checks() async {
        let calendar = Calendar.current
        let model = AppModel(preview: true)
        let service = model.calendar
        service.loadTestSignIn(canChangeEvents: true)

        // A week ahead with a busy Tuesday-ish day, a late event crossing midnight, and
        // someone else's meeting. Five events in one week makes the server page (2 per page).
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
        }
        let busy = 9  // well ahead, so nothing is in the past
        FakeGoogle.reset([
            .init(id: "standup", title: "Standup", start: at(busy, 9), end: at(busy, 9, 15), mine: true),
            .init(id: "review", title: "Design review", start: at(busy, 10), end: at(busy, 11), mine: true),
            .init(id: "client", title: "Client call", start: at(busy, 11), end: at(busy, 12), mine: true),
            .init(id: "critique", title: "Portfolio critique", start: at(busy, 14), end: at(busy, 15, 30), mine: false),
            .init(id: "late", title: "Launch watch", start: at(busy, 23), end: at(busy + 1, 1), mine: true),
        ])

        // Loading: pages, the week cache, and one shared fetch.
        do {
            try await service.ensureLoaded(from: day(busy), to: day(busy + 1))
            check(true, "range loads")
        } catch {
            check(false, "range loads: \(error)")
        }
        let titles = service.events(on: day(busy))?.map(\.title) ?? []
        check(titles == ["Standup", "Design review", "Client call", "Portfolio critique", "Launch watch"], "every page read, in order: \(titles)")
        check(service.events(on: day(busy + 1))?.map(\.id) == ["late"], "late event also shows the next morning")
        let afterFirst = FakeGoogle.gets
        try? await service.ensureLoaded(from: day(busy), to: day(busy))
        check(FakeGoogle.gets == afterFirst, "a fresh week isn't fetched again")

        let far = day(30)
        service.prefetch(around: far)
        service.prefetch(around: far)
        try? await service.ensureLoaded(from: far, to: far)
        let farWeek = service.weekStart(for: far)
        check(FakeGoogle.getsByWeek[farWeek] == 1, "two prefetches and a load share one fetch (\(FakeGoogle.getsByWeek[farWeek] ?? 0))")

        // The chat's view of it.
        let date = CalendarDate(day(busy), calendar: calendar)
        let schedule = await model.performForTest(.getSchedule(from: date, to: date))
        check(!schedule.isError && schedule.result.contains("Open within working hours") && schedule.result.contains("[id critique]"),
              "get_schedule lists events with ids and open time")
        check(schedule.result.contains("someone else's — read only"), "get_schedule marks events she can't change")

        let free = await model.performForTest(.findFreeTime(FreeTimeRequest(from: date, to: date, durationMinutes: 60,
                                                                           earliest: nil, latest: nil)))
        check(!free.isError && free.result.contains("12:00–13:00"), "find_free_time finds the hour after the client call")
        check(!free.result.contains("10:00–11:00") && !free.result.contains("14:00–15:00"), "find_free_time never offers a booked hour")

        // Creating: proposal, conflict, confirmation, and only then the event.
        let proposal = await model.performForTest(.proposeEvent(EventProposal(
            title: "Pairing", date: date, start: ClockTime(hour: 14, minute: 30), durationMinutes: 30,
            allDay: false, location: nil, notes: nil)))
        check(proposal.result.contains("NOT created"), "proposing doesn't create")
        check(FakeGoogle.events.count == 5, "nothing written before confirming")
        check(model.eventRequests.last?.conflicts.map(\.id) == ["critique"], "the clash with the critique is found")
        guard let createID = model.eventRequests.last?.id else { return check(false, "a request card exists") }
        model.confirmEventRequest(createID)
        await settle(model, createID)
        let created = FakeGoogle.events.first { $0.title == "Pairing" }
        check(created != nil, "confirming creates it in Google Calendar")
        check(service.events(on: day(busy))?.contains { $0.title == "Pairing" } == true, "the new event shows on that day")
        check(calendar.isDate(model.scheduleDay, inSameDayAs: day(busy)), "the week browser jumps to the new event's day")

        // Moving keeps the id.
        guard let createdID = created?.id else { return }
        _ = await model.performForTest(.proposeEventChange(EventChangeProposal(
            eventID: createdID, date: CalendarDate(day(busy + 2), calendar: calendar), start: ClockTime(hour: 10, minute: 0))))
        guard let moveID = model.eventRequests.last?.id else { return check(false, "a move card exists") }
        model.confirmEventRequest(moveID)
        await settle(model, moveID)
        let moved = FakeGoogle.events.first { $0.id == createdID }
        check(moved?.start == at(busy + 2, 10) && moved?.end == at(busy + 2, 10, 30), "moving keeps the id and the 30-minute length")
        check(FakeGoogle.events.filter { $0.title == "Pairing" }.count == 1, "moving doesn't duplicate")
        check(service.events(on: day(busy))?.contains { $0.id == createdID } == false
              && service.events(on: day(busy + 2))?.contains { $0.id == createdID } == true, "both days update after the move")

        // Deleting.
        _ = await model.performForTest(.proposeEventDeletion(eventID: createdID))
        guard let deleteID = model.eventRequests.last?.id else { return check(false, "a delete card exists") }
        model.confirmEventRequest(deleteID)
        await settle(model, deleteID)
        check(!FakeGoogle.events.contains { $0.id == createdID }, "confirming deletes it")
        check(service.events(on: day(busy + 2))?.contains { $0.id == createdID } == false, "the deleted event leaves the browser")

        // Refusals.
        let theirs = await model.performForTest(.proposeEventDeletion(eventID: "critique"))
        check(theirs.isError, "someone else's meeting can't be deleted")
        let unknown = await model.performForTest(.proposeEventChange(EventChangeProposal(eventID: "nope", title: "x")))
        check(unknown.isError, "an unknown id is refused")
        let past = await model.performForTest(.proposeEvent(EventProposal(
            title: "Too late", date: CalendarDate(day(-1), calendar: calendar), start: ClockTime(hour: 9, minute: 0),
            durationMinutes: 30, allDay: false, location: nil, notes: nil)))
        check(past.isError, "times in the past are refused")

        // Failures.
        FakeGoogle.failNextWrite = 500
        _ = await model.performForTest(.proposeEvent(EventProposal(
            title: "Doomed", date: date, start: ClockTime(hour: 16, minute: 0), durationMinutes: 30, allDay: false, location: nil, notes: nil)))
        guard let doomedID = model.eventRequests.last?.id else { return }
        model.confirmEventRequest(doomedID)
        await settle(model, doomedID)
        if case .failed = model.eventRequests.first(where: { $0.id == doomedID })?.state { check(true, "") } else {
            check(false, "a failed create shows as failed")
        }
        check(!FakeGoogle.events.contains { $0.title == "Doomed" }, "a failed create writes nothing")

        FakeGoogle.events.append(.init(id: "outside", title: "Added on the web", start: at(busy, 16), end: at(busy, 17), mine: true))
        try? await service.ensureLoaded(from: day(busy), to: day(busy), maxAge: 0)
        check(service.events(on: day(busy))?.contains { $0.id == "outside" } == true, "an event added in Google shows after a refresh")

        FakeGoogle.failNextGets = 1
        try? await service.ensureLoaded(from: day(busy), to: day(busy), maxAge: 0)
        check(service.events(on: day(busy))?.contains { $0.id == "outside" } == true, "a failed refresh keeps the last good events")
        check(service.problem(for: day(busy)) != nil, "a failed refresh is reported")

        FakeGoogle.failNextGets = 1
        let lost = day(60)
        do {
            try await service.ensureLoaded(from: lost, to: lost)
            check(false, "a week that never loaded reports an error")
        } catch {
            check(true, "")
        }

        FakeGoogle.unauthorized = true
        try? await service.ensureLoaded(from: day(busy), to: day(busy), maxAge: 0)
        check(service.status == .needsReconnect, "revoked access asks to reconnect")
        FakeGoogle.unauthorized = false
    }

    @MainActor
    private static func settle(_ model: AppModel, _ id: AppModel.EventRequest.ID) async {
        for _ in 0..<200 {
            if let state = model.eventRequests.first(where: { $0.id == id })?.state, state != .working, state != .waiting { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// A tiny Google Calendar: events.list with paging, insert, patch and delete. Requests to
/// other hosts go to `otherHosts` (the Partiful self-test's stand-in pages).
nonisolated final class FakeGoogle: URLProtocol, @unchecked Sendable {
    struct Event {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var mine: Bool
        /// Coco's private source property, when it was created from an invitation.
        var sourceKey: String? = nil
        /// The iCalendar UID, which Apple Calendar shows for the same event.
        var uid: String? = nil
    }

    struct Answer {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }
    nonisolated(unsafe) static var otherHosts: ((URLRequest) -> Answer)?
    /// Every host asked for, in order.
    nonisolated(unsafe) static var hostsRequested: [String] = []
    nonisolated(unsafe) static var lastInsert: [String: Any]?
    nonisolated(unsafe) static var inserts = 0

    nonisolated(unsafe) static var events: [Event] = []
    nonisolated(unsafe) static var gets = 0
    nonisolated(unsafe) static var getsByWeek: [Date: Int] = [:]
    nonisolated(unsafe) static var failNextGets = 0
    nonisolated(unsafe) static var failNextWrite: Int?
    nonisolated(unsafe) static var unauthorized = false
    nonisolated(unsafe) private static var counter = 0
    private static let lock = NSLock()

    static func reset(_ seed: [Event]) {
        lock.withLock {
            events = seed
            gets = 0
            getsByWeek = [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self.hostsRequested.append(host) }
        if host != "www.googleapis.com", let other = Self.otherHosts {
            let answer = other(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers)!
            if (300..<400).contains(answer.status), let location = answer.headers["Location"], let next = URL(string: location) {
                var redirected = request
                redirected.url = next
                client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
                // If the redirect is declined, the 3xx itself is the answer (as on the network);
                // if it's followed, this load was already cancelled and these are ignored.
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (status, body) = Self.lock.withLock { Self.answer(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func answer(_ request: URLRequest) -> (Int, Data) {
        if unauthorized { return (401, Data(#"{"error":{"message":"Invalid Credentials"}}"#.utf8)) }
        let url = request.url!
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        let id = url.path.components(separatedBy: "/events/").dropFirst().first?.removingPercentEncoding
        switch request.httpMethod ?? "GET" {
        case "GET":
            if let property = items["privateExtendedProperty"] {
                let key = property.components(separatedBy: "=").dropFirst().joined(separator: "=")
                let found = events.filter { $0.sourceKey == key }
                return (200, try! JSONSerialization.data(withJSONObject: ["items": found.map(json)]))
            }
            gets += 1
            if failNextGets > 0 { failNextGets -= 1; return (500, Data()) }
            let formatter = ISO8601DateFormatter()
            guard let from = items["timeMin"].flatMap(formatter.date), let to = items["timeMax"].flatMap(formatter.date) else { return (400, Data()) }
            if items["pageToken"] == nil { getsByWeek[from, default: 0] += 1 }
            let matching = events.filter { $0.start < to && $0.end > from }.sorted { $0.start < $1.start }
            let offset = Int(items["pageToken"] ?? "0") ?? 0
            let page = Array(matching.dropFirst(offset).prefix(2))
            var root: [String: Any] = ["summary": "me@example.com", "items": page.map(json)]
            if offset + 2 < matching.count { root["nextPageToken"] = String(offset + 2) }
            return (200, try! JSONSerialization.data(withJSONObject: root))
        case "POST":
            if let status = failNextWrite { failNextWrite = nil; return (status, Data()) }
            guard let body = request.bodyData.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
                  let start = time(body["start"]), let end = time(body["end"]) else { return (400, Data()) }
            counter += 1
            inserts += 1
            lastInsert = body
            let key = ((body["extendedProperties"] as? [String: Any])?["private"] as? [String: String])?[GoogleCalendarAPI.sourceProperty]
            let event = Event(id: "new\(counter)", title: body["summary"] as? String ?? "", start: start, end: end, mine: true, sourceKey: key)
            events.append(event)
            return (200, try! JSONSerialization.data(withJSONObject: json(event)))
        case "PATCH":
            guard let id, let index = events.firstIndex(where: { $0.id == id }) else { return (404, Data()) }
            let body = request.bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if let title = body["summary"] as? String { events[index].title = title }
            if let start = time(body["start"]) { events[index].start = start }
            if let end = time(body["end"]) { events[index].end = end }
            return (200, try! JSONSerialization.data(withJSONObject: json(events[index])))
        case "DELETE":
            guard let id, events.contains(where: { $0.id == id }) else { return (404, Data()) }
            events.removeAll { $0.id == id }
            return (204, Data())
        default:
            return (405, Data())
        }
    }

    private static func json(_ event: Event) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        var item: [String: Any] = ["id": event.id, "status": "confirmed", "summary": event.title,
                "start": ["dateTime": formatter.string(from: event.start)], "end": ["dateTime": formatter.string(from: event.end)],
                "organizer": event.mine ? ["self": true] : ["email": "someone@example.com"]]
        if let uid = event.uid { item["iCalUID"] = uid }
        return item
    }

    private static func time(_ value: Any?) -> Date? {
        guard let object = value as? [String: Any], let text = object["dateTime"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

private extension URLRequest {
    /// URLSession hands protocols the body as a stream.
    nonisolated var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
#endif
