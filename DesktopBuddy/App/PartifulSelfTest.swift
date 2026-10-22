#if DEBUG
import AppKit
import SwiftUI
import BuddyAssistant
import BuddyIntegrations

/// Runs the whole Partiful flow through the real app code — the chat's read_event_link and
/// propose_event tools, the link reader, the event card and Google Calendar — against
/// stand-in Partiful pages and a stand-in Google Calendar. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --partiful-selftest
///
/// With `--live <link>` it instead reads one real Partiful page over the network (one request,
/// the way a link preview would) and prints what the chat would see.
enum PartifulSelfTest {
    static func run() {
        // The invitation checks add events through Google sign-in, which ships switched off;
        // the Google-by-link checks switch it back off.
        Features.googleSignIn = true
        var finished = false
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            HTTP.standIn = FakeGoogle.self
            Task { @MainActor in
                await snapshots(into: folder)
                finished = true
            }
        } else if let index = CommandLine.arguments.firstIndex(of: "--live"), index + 1 < CommandLine.arguments.count {
            let link = CommandLine.arguments[index + 1]
            Task { @MainActor in
                await live(link)
                finished = true
            }
        } else {
            HTTP.standIn = FakeGoogle.self
            Task { @MainActor in
                await checks()
                finished = true
            }
        }
        while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        if passed + failed > 0 { print("partiful selftest: \(passed) passed, \(failed) failed") }
    }

    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    private static func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if condition { passed += 1 } else { failed += 1; print("partiful selftest FAILED: \(name) \(detail())") }
    }

    /// The Connections card before and after importing (`--partiful-selftest --snapshot <folder>`).
    @MainActor
    private static func snapshots(into folder: URL) async {
        let model = AppModel(preview: true)
        func render(_ name: String) {
            let hosting = NSHostingView(rootView: VStack(spacing: 18) {
                CalendarLinkSection(service: model.googleFeed)
                CalendarLinkSection(service: model.partiful)
            }.frame(width: 476).padding(32).background(Theme.paper))
            hosting.frame.size = hosting.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: hosting.frame.size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
            window.orderOut(nil)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        render("partiful-setup.png")
        FakeGoogle.otherHosts = FakePartiful.answer
        let start = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!.addingTimeInterval(19 * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let events = [("Bushwick Mixer", 0), ("Gigi Flea 🕸️ 4100 Bar", 2), ("Golden Gate Walk Club", 5), ("Friendsgiving", 30)]
            .map { "BEGIN:VEVENT\nUID:Snap\($0.0.count)x\($0.1)\nSUMMARY:\($0.0)\nDTSTART:\(formatter.string(from: start + Double($0.1) * 86_400))\nDURATION:PT3H\nEND:VEVENT" }
        FakePartiful.feeds = ["/calendar/me.ics": (200, "BEGIN:VCALENDAR\nPRODID:Partiful\n" + events.joined(separator: "\n") + "\nEND:VCALENDAR")]
        _ = await model.partiful.connect("webcal://api.partiful.com/calendar/me.ics")
        FakePartiful.feeds["/calendar/ical/me@gmail.com/private-abc/basic.ics"] = (200, "BEGIN:VCALENDAR\nX-WR-CALNAME:me@gmail.com\n"
            + "BEGIN:VEVENT\nUID:standup@google.com\nSUMMARY:Standup\nDTSTART:\(formatter.string(from: start - 86_400 * 2))\nDURATION:PT15M\nRRULE:FREQ=DAILY\nEND:VEVENT\n"
            + "END:VCALENDAR")
        _ = await model.googleFeed.connect("https://calendar.google.com/calendar/ical/me%40gmail.com/private-abc/basic.ics")
        render("partiful-connected.png")
        print("Partiful snapshots written to \(folder.path)")
    }

    @MainActor
    private static func live(_ link: String) async {
        let model = AppModel(preview: true)
        let outcome = await model.performForTest(.readEventLink(url: link))
        print("— read_event_link (error: \(outcome.isError)) —\n\(outcome.result)\n— activity: \(outcome.activity ?? "none")")
    }

    @MainActor
    private static func checks() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let partyDay = calendar.date(byAdding: .day, value: 10, to: today)!
        // 7 PM in the user's own zone, so the stand-in "Bushwick Mixer" lines up with their calendar.
        let mixerStart = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: partyDay)!
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // A Los Angeles event: 2 PM there.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laDay = la.date(from: calendar.dateComponents([.year, .month, .day], from: partyDay))!
        let laStart = la.date(bySettingHour: 14, minute: 0, second: 0, of: laDay)!

        FakePartiful.pages = [
            "PublicEvent0001": .event(ld: ["@type": "Event", "name": "Gigi Flea 🕸️ 4100 Bar", "description": "Costumes encouraged",
                                           "startDate": iso.string(from: laStart), "endDate": iso.string(from: laStart + 5 * 3600),
                                           "eventStatus": "https://schema.org/EventScheduled",
                                           "location": ["@type": "Place", "name": "4100 Bar",
                                                        "address": ["streetAddress": "1087 Manzanita St", "addressLocality": "Los Angeles",
                                                                    "addressRegion": "CA", "postalCode": "90029"]]],
                                      timezone: "America/Los_Angeles"),
            "BushwickMixer01": .event(ld: ["@type": "Event", "name": "Bushwick Mixer", "startDate": iso.string(from: mixerStart),
                                           "endDate": iso.string(from: mixerStart + 3 * 3600),
                                           "location": ["@type": "Place", "name": "Brooklyn, NY"]],
                                      timezone: TimeZone.current.identifier),
            "NoEndEvent00002": .event(ld: ["@type": "Event", "name": "Walk club", "startDate": iso.string(from: mixerStart)],
                                      timezone: TimeZone.current.identifier),
            "PasswordEvent03": .password,
            "PrivateEvent004": .empty,
            "LoginEvent00007": .redirect("https://partiful.com/login?next=/e/LoginEvent00007"),
        ]
        FakePartiful.shortLinks = ["Short001": "https://partiful.com/e/PublicEvent0001",
                                   "Evil0001": "https://evil.example/steal"]
        FakePartiful.statuses = ["GoneEvent000005": 404, "BlockedEvent006": 429]
        FakeGoogle.otherHosts = FakePartiful.answer
        FakeGoogle.reset([
            // Added from Partiful's own "add to calendar" earlier: same name and time, no source key.
            .init(id: "manual-mixer", title: "Bushwick Mixer 🎉", start: mixerStart, end: mixerStart + 3 * 3600, mine: true),
        ])

        let model = AppModel(preview: true)
        model.calendar.loadTestSignIn(canChangeEvents: true)
        func read(_ link: String) async -> AssistantService.ToolOutcome { await model.performForTest(.readEventLink(url: link)) }
        func partifulRequests() -> Int { FakeGoogle.hostsRequested.filter { $0.hasSuffix("partiful.com") }.count }

        // Reading a public invitation: everything the page says, converted for the user.
        let publicRead = await read("Can you add this? https://partiful.com/e/PublicEvent0001?c=xyz")
        check(publicRead.isError == false, "a pasted message with a link isn't a URL", publicRead.result)
        let direct = await read("https://partiful.com/e/PublicEvent0001?c=xyz")
        check(!direct.isError, "public event reads", direct.result)
        check(direct.result.contains("Title: Gigi Flea 🕸️ 4100 Bar"), "title")
        check(direct.result.contains("2:00 PM"), "start in the event's zone", direct.result)
        check(direct.result.contains("4100 Bar, 1087 Manzanita St, Los Angeles, CA 90029"), "venue and address")
        check(direct.result.contains("Costumes encouraged"), "description")
        check(direct.result.contains("source_link \"https://partiful.com/e/PublicEvent0001\""), "canonical link to keep")
        let localStart = calendar.dateComponents([.hour, .minute], from: laStart)
        check(direct.result.contains(String(format: "start_time %02d:%02d", localStart.hour!, localStart.minute!)), "start converted to the user's zone")
        check(direct.result.contains("duration_minutes 300"), "length from start and end")
        check(direct.activity?.contains("Gigi Flea") == true, "activity line names the invite")

        // Same link again, and via the short link: no second fetch.
        let before = partifulRequests()
        _ = await read("partiful.com/e/PublicEvent0001")
        check(partifulRequests() == before, "the same link isn't fetched twice")
        let short = await read("https://go.partiful.com/Short001")
        check(short.result.contains("Title: Gigi Flea"), "short link follows Partiful's redirect", short.result)

        // What can't be read is explained, never invented.
        let noEnd = await read("https://partiful.com/e/NoEndEvent00002")
        check(noEnd.result.contains("Ends: not listed") && noEnd.result.contains("ask how long to block"), "missing end time is asked about")
        let password = await read("https://partiful.com/e/PasswordEvent03")
        check(password.isError && password.result.contains("password-protected"), "password-protected", password.result)
        let empty = await read("https://partiful.com/e/PrivateEvent004")
        check(empty.isError && empty.result.contains("no event details"), "page without details", empty.result)
        let gone = await read("https://partiful.com/e/GoneEvent000005")
        check(gone.isError && gone.result.contains("doesn't exist"), "deleted or mistyped event", gone.result)
        let blocked = await read("https://partiful.com/e/BlockedEvent006")
        check(blocked.isError && blocked.result.contains("didn't let Coco"), "rate-limited", blocked.result)
        let login = await read("https://partiful.com/e/LoginEvent00007")
        check(login.isError && login.result.contains("signing in"), "sign-in wall", login.result)

        // Nothing outside Partiful is ever fetched — not even through a redirect.
        let requestsBefore = FakeGoogle.hostsRequested.count
        let other = await read("https://example.com/e/PublicEvent0001")
        check(other.isError && other.result.contains("isn't a Partiful event link"), "other sites refused", other.result)
        check(FakeGoogle.hostsRequested.count == requestsBefore, "nothing fetched for a non-Partiful link")
        let evil = await read("https://go.partiful.com/Evil0001")
        check(evil.isError && evil.result.contains("redirects away"), "redirect off Partiful refused", evil.result)
        check(!FakeGoogle.hostsRequested.contains("evil.example"), "the off-site redirect was never followed", "\(FakeGoogle.hostsRequested)")

        // Adding it: through the real tool parser, as the model would call it.
        func propose(_ input: JSONValue) async -> AssistantService.ToolOutcome? {
            guard case .success(let action) = AssistantTools.action(name: "propose_event", input: input) else { return nil }
            return await model.performForTest(action)
        }
        let date = CalendarDate(laStart, calendar: calendar).text
        let time = String(format: "%02d:%02d", localStart.hour!, localStart.minute!)
        let input: JSONValue = ["title": "Gigi Flea 🕸️ 4100 Bar", "date": .string(date), "start_time": .string(time),
                                "duration_minutes": 300, "location": "4100 Bar, 1087 Manzanita St, Los Angeles, CA 90029",
                                "source_link": "https://partiful.com/e/PublicEvent0001"]
        let first = await propose(input)
        check(first?.result.contains("to confirm") == true, "invite proposed as a card", first?.result ?? "nil")
        check(model.eventRequests.count == 1, "one card")
        let again = await propose(input)
        check(again?.result.contains("already waiting") == true, "shared again: no second card", again?.result ?? "nil")
        check(model.eventRequests.count == 1, "still one card")
        check(FakeGoogle.inserts == 0, "nothing created before confirming")

        guard let card = model.eventRequests.first else { return }
        model.confirmEventRequest(card.id)
        await settle(model, card.id)
        let state = model.eventRequests.first { $0.id == card.id }?.state
        check({ if case .done(let text) = state { text.hasPrefix("Added") } else { false } }(), "Google confirms it", "\(String(describing: state))")
        check(FakeGoogle.inserts == 1, "created once")
        let body = FakeGoogle.lastInsert ?? [:]
        check((body["description"] as? String)?.contains("Partiful invite: https://partiful.com/e/PublicEvent0001") == true, "link in the description")
        check(((body["extendedProperties"] as? [String: Any])?["private"] as? [String: String])?[GoogleCalendarAPI.sourceProperty]
              == "partiful:PublicEvent0001", "source key stored")
        check((body["source"] as? [String: String])?["url"] == "https://partiful.com/e/PublicEvent0001", "Google source link")
        check(calendar.isDate(model.scheduleDay, inSameDayAs: laStart), "calendar card jumps to the day")
        check(model.calendar.events(on: laStart)?.contains { $0.title.hasPrefix("Gigi Flea") } == true, "calendar view refreshed")

        model.dismissEventRequest(card.id)
        let third = await propose(input)
        check(third?.result.contains("already on their calendar") == true, "shared after adding: recognised", third?.result ?? "nil")
        check(model.eventRequests.isEmpty && FakeGoogle.inserts == 1, "no duplicate card or event")

        // Someone added it elsewhere while the card was open: confirming doesn't duplicate.
        let mixer: JSONValue = ["title": "Bushwick Mixer", "date": .string(CalendarDate(mixerStart, calendar: calendar).text),
                                "start_time": "19:00", "duration_minutes": 180, "location": "Brooklyn, NY",
                                "source_link": "https://partiful.com/e/BushwickMixer01"]
        let mixerProposal = await propose(mixer)
        check(mixerProposal?.result.contains("may already be on their calendar as “Bushwick Mixer 🎉”") == true,
              "a same-name, same-time event is pointed out", mixerProposal?.result ?? "nil")
        guard let mixerCard = model.eventRequests.first else { return }
        FakeGoogle.events.append(.init(id: "other-chat", title: "Bushwick Mixer", start: mixerStart, end: mixerStart + 10_800,
                                       mine: true, sourceKey: "partiful:BushwickMixer01"))
        model.confirmEventRequest(mixerCard.id)
        await settle(model, mixerCard.id)
        let mixerState = model.eventRequests.first { $0.id == mixerCard.id }?.state
        check({ if case .done(let text) = mixerState { text.contains("not added again") } else { false } }(),
              "confirm re-checks before adding", "\(String(describing: mixerState))")
        check(FakeGoogle.inserts == 1, "still created only once")

        await feedChecks(model, calendar: calendar, partyDay: partyDay)
        await googleLinkChecks(model, calendar: calendar)

        // A made-up or foreign source link is rejected before anything happens.
        var forged = input
        if case .object(var fields) = forged { fields["source_link"] = "https://evil.example/e/PublicEvent0001"; forged = .object(fields) }
        if case .failure = AssistantTools.action(name: "propose_event", input: forged) { check(true, "") } else { check(false, "foreign source_link rejected") }
    }

    /// Importing the user's own Partiful calendar: connecting, refreshing, failures, and the
    /// chat falling back to it for an invite whose page is locked.
    @MainActor
    private static func feedChecks(_ model: AppModel, calendar: Calendar, partyDay: Date) async {
        let service = model.partiful
        let stamp = { (date: Date) -> String in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return formatter.string(from: date)
        }
        // The day after the other parties, so nothing else overlaps it.
        let dinnerDay = calendar.date(byAdding: .day, value: 1, to: partyDay)!
        let dinner = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dinnerDay)!
        let past = calendar.date(byAdding: .day, value: -30, to: dinner)!
        let feed = """
        BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:Partiful\r\nX-WR-CALNAME:Partiful\r
        BEGIN:VEVENT\r\nUID:PasswordEvent03\r\nSUMMARY:Secret supper club\r\nDTSTART:\(stamp(dinner))\r\nDURATION:PT2H\r
        DESCRIPTION:View this event on Partiful at https://partiful.com/e/PasswordEvent03\\n\\nBring a dish\r
        URL:https://partiful.com/e/PasswordEvent03\r\nLOCATION:Somewhere in Brooklyn\r\nEND:VEVENT\r
        BEGIN:VEVENT\r\nUID:OldParty000000001\r\nSUMMARY:Old party\r\nDTSTART:\(stamp(past))\r\nDURATION:PT2H\r\nEND:VEVENT\r
        BEGIN:VEVENT\r\nUID:Cancelled00000001\r\nSUMMARY:Called off\r\nDTSTART:\(stamp(dinner))\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r
        END:VCALENDAR\r\n
        """
        FakePartiful.feeds = [
            "/calendar/good.ics": (200, feed),
            "/calendar/reset.ics": (404, ""),
            "/calendar/html.ics": (200, "<html>Sign in</html>"),
            "/calendar/sneaky.ics": (302, "https://localhost/feed.ics"),
        ]

        let invite = await service.connect("https://partiful.com/e/PublicEvent0001")
        check(invite?.contains("link to one invitation") == true && !service.isConnected, "an invite link isn't a calendar link", invite ?? "nil")
        let local = await service.connect("https://192.168.1.2/feed.ics")
        check(local?.contains("local network") == true, "local addresses refused", local ?? "nil")
        let reset = await service.connect("webcal://api.partiful.com/calendar/reset.ics")
        check(reset?.contains("may have been reset") == true && !service.isConnected, "a dead link is explained", reset ?? "nil")
        let html = await service.connect("https://api.partiful.com/calendar/html.ics")
        check(html?.contains("didn't return a calendar") == true, "a page that isn't a calendar is explained", html ?? "nil")
        let sneaky = await service.connect("https://api.partiful.com/calendar/sneaky.ics")
        check(sneaky?.contains("redirected somewhere") == true && !FakeGoogle.hostsRequested.contains("localhost"),
              "a redirect to this Mac isn't followed", sneaky ?? "nil")

        let connected = await service.connect("webcal://api.partiful.com/calendar/good.ics")
        check(connected == nil && service.isConnected, "the calendar link connects", connected ?? "")
        check(service.feedEvents.map(\.title) == ["Secret supper club"], "past and cancelled events left out", "\(service.feedEvents.map(\.title))")
        let onDay = service.events(on: dinnerDay) ?? []
        check(onDay.count == 1 && onDay[0].canEdit == false && onDay[0].htmlLink?.absoluteString == "https://partiful.com/e/PasswordEvent03",
              "the day's events, read-only, linking to the invite")
        check(onDay.first?.end.timeIntervalSince(dinner) == 7_200, "Partiful's 2-hour default blocks the time")

        // The invite's page is password-protected, but it's in the user's own calendar.
        let locked = await model.performForTest(.readEventLink(url: "https://partiful.com/e/PasswordEvent03"))
        check(!locked.isError && locked.result.contains("in the user's own Partiful calendar") && locked.result.contains("Secret supper club"),
              "a locked invite is read from the user's calendar", locked.result)
        check(locked.result.contains("Ends: not listed") && locked.result.contains("Bring a dish")
              && !locked.result.contains("View this event on Partiful"), "the feed's default end isn't presented as the host's")

        // In Coco's calendar: merged with a copy Partiful synced into Google, counted as busy,
        // seen by the chat, and read-only.
        let date = CalendarDate(dinner, calendar: calendar)
        FakeGoogle.events.append(.init(id: "synced-supper", title: "Secret supper club", start: dinner, end: dinner + 7_200, mine: false))
        try? await model.calendar.ensureLoaded(from: dinnerDay, to: dinnerDay, maxAge: 0)
        let shown = model.agenda.events(on: dinnerDay)?.filter { $0.title == "Secret supper club" } ?? []
        check(shown.count == 1 && shown.first?.references.map(\.provider).sorted { $0.rawValue < $1.rawValue } == [.google, .partiful],
              "shown once, known to be in Google and Partiful", "\(shown.map(\.references))")
        let schedule = await model.performForTest(.getSchedule(from: date, to: date))
        check(schedule.result.contains("Secret supper club"), "the chat's schedule includes it", schedule.result)
        let free = await model.performForTest(.findFreeTime(FreeTimeRequest(from: date, to: date, durationMinutes: 90,
                                                                           earliest: ClockTime(hour: 20, minute: 0), latest: ClockTime(hour: 22, minute: 0))))
        check(free.result.hasPrefix("No opening"), "it counts as busy", free.result)
        let cardsBefore = model.eventRequests.count
        let synced = await model.performForTest(.proposeEvent(EventProposal(
            title: "Secret supper club", date: date, start: ClockTime(hour: 20, minute: 0), durationMinutes: 120,
            source: EventSource(name: "Partiful", url: Partiful.canonicalURL(id: "PasswordEvent03"), key: "partiful:PasswordEvent03"))))
        check(synced.result.contains("already in their Google Calendar") && model.eventRequests.count == cardsBefore,
              "a synced copy in Google isn't added again", synced.result)

        // Only in the Partiful import: it can be added, and doesn't clash with itself.
        FakeGoogle.events.removeAll { $0.id == "synced-supper" }
        try? await model.calendar.ensureLoaded(from: dinnerDay, to: dinnerDay, maxAge: 0)
        let fresh = await model.performForTest(.proposeEvent(EventProposal(
            title: "Secret supper club", date: date, start: ClockTime(hour: 20, minute: 0), durationMinutes: 150,
            source: EventSource(name: "Partiful", url: Partiful.canonicalURL(id: "PasswordEvent03"), key: "partiful:PasswordEvent03"))))
        check(fresh.result.contains("No conflicts") && fresh.result.contains("already shows in Coco from their Partiful import")
              && !fresh.result.contains("may already be on their calendar"), "no clash with its own Partiful copy", fresh.result)
        check(model.eventRequests.last?.conflicts.isEmpty == true, "the card shows no overlap")
        model.eventRequests.forEach { model.dismissEventRequest($0.id) }
        let delete = await model.performForTest(.proposeEventDeletion(eventID: "partiful:PasswordEvent03"))
        check(delete.isError && delete.result.contains("Partiful"), "Partiful events can't be deleted from Coco", delete.result)

        // Refreshing after the link is reset keeps the last events and says why.
        FakePartiful.feeds["/calendar/good.ics"] = (404, "")
        await service.refresh()
        check(service.problem?.contains("may have been reset") == true && service.feedEvents.count == 1, "a failed refresh keeps the last events")
        service.disconnect()
        check(!service.isConnected && service.feedEvents.isEmpty && service.events(on: dinnerDay) == nil, "disconnect forgets everything")
    }

    /// Google Calendar by its secret iCal address, as it ships: no sign-in, read-only, repeats expanded.
    @MainActor
    private static func googleLinkChecks(_ model: AppModel, calendar: Calendar) async {
        Features.googleSignIn = false
        defer { Features.googleSignIn = true }
        let feed = model.googleFeed
        let day = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: .now))!
        let lunch = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let firstStandup = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: calendar.date(byAdding: .day, value: -10, to: day)!)!
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = calendar.timeZone
        local.dateFormat = "yyyyMMdd'T'HHmmss"
        let zone = calendar.timeZone.identifier
        FakePartiful.feeds["/calendar/ical/me@gmail.com/private-good/basic.ics"] = (200, """
        BEGIN:VCALENDAR\r\nPRODID:-//Google Inc//Google Calendar 70.9054//EN\r\nX-WR-CALNAME:me@gmail.com\r
        BEGIN:VEVENT\r\nUID:standup123@google.com\r\nSUMMARY:Standup\r\nDTSTART;TZID=\(zone):\(local.string(from: firstStandup))\r
        DTEND;TZID=\(zone):\(local.string(from: firstStandup + 900))\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r
        BEGIN:VEVENT\r\nUID:lunch456@google.com\r\nSUMMARY:Lunch with Sam\r\nDTSTART;TZID=\(zone):\(local.string(from: lunch))\r
        DTEND;TZID=\(zone):\(local.string(from: lunch + 3_600))\r\nLOCATION:Russ & Daughters\r\nEND:VEVENT\r
        END:VCALENDAR\r\n
        """)
        FakePartiful.feeds["/calendar/ical/me@gmail.com/public/basic.ics"] = (404, "")

        let page = await feed.connect("https://calendar.google.com/calendar/u/0/r/settings")
        check(page?.contains("Google Calendar page") == true, "a Calendar web page isn't the address", page ?? "nil")
        let other = await feed.connect("https://example.com/me.ics")
        check(other?.contains("isn't a Google Calendar address") == true, "other sites refused", other ?? "nil")
        let publicLink = await feed.connect("https://calendar.google.com/calendar/ical/me%40gmail.com/public/basic.ics")
        check(publicLink?.contains("Secret address") == true && !feed.isConnected, "the public address of a private calendar is explained", publicLink ?? "nil")

        let connected = await feed.connect("webcal://calendar.google.com/calendar/ical/me%40gmail.com/private-good/basic.ics")
        check(connected == nil && feed.isConnected && feed.calendarName == "me@gmail.com", "the secret address connects", connected ?? "")
        let shown = model.agenda.events(on: day) ?? []
        check(shown.map(\.title).sorted() == ["Lunch with Sam", "Standup"], "the day shows the one-off and the repeat", "\(shown.map(\.title))")
        check(shown.allSatisfy { !$0.canEdit && $0.provider == .google }, "Google-by-link events are read-only")
        check(shown.first { $0.title == "Standup" }?.isRecurring == true, "repeats are marked as repeats")
        let standups = (0..<7).compactMap { offset in
            model.agenda.events(on: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!)?.filter { $0.title == "Standup" }.count
        }
        check(standups == Array(repeating: 1, count: 7), "a daily repeat shows once every day", "\(standups)")

        let date = CalendarDate(lunch, calendar: calendar)
        let free = await model.performForTest(.findFreeTime(FreeTimeRequest(from: date, to: date, durationMinutes: 60,
                                                                           earliest: ClockTime(hour: 12, minute: 0), latest: ClockTime(hour: 13, minute: 0))))
        check(free.result.hasPrefix("No opening"), "Google-by-link events count as busy", free.result)
        let add = await model.performForTest(.proposeEvent(EventProposal(title: "Dentist", date: date, start: ClockTime(hour: 15, minute: 0), durationMinutes: 30)))
        check(add.isError && add.result.contains("connected read-only") && model.eventRequests.allSatisfy { if case .create(let draft) = $0.kind { draft.title != "Dentist" } else { true } },
              "nothing can be added", add.result)
        let lunchID = shown.first { $0.title == "Lunch with Sam" }?.id ?? ""
        let delete = await model.performForTest(.proposeEventDeletion(eventID: lunchID))
        check(delete.isError && delete.result.contains("connected read-only"), "nothing can be deleted", delete.result)

        feed.disconnect()
        check(!feed.isConnected && (model.agenda.events(on: day) ?? []).allSatisfy { $0.title != "Lunch with Sam" }, "disconnect forgets the calendar")
    }

    @MainActor
    private static func settle(_ model: AppModel, _ id: AppModel.EventRequest.ID) async {
        for _ in 0..<200 {
            if let state = model.eventRequests.first(where: { $0.id == id })?.state, state != .working, state != .waiting { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Stand-in Partiful: event pages shaped like the real ones, short links, and failures.
nonisolated enum FakePartiful {
    enum Page {
        case event(ld: [String: Any], timezone: String)
        case password
        case empty
        case redirect(String)
    }

    nonisolated(unsafe) static var pages: [String: Page] = [:]
    nonisolated(unsafe) static var shortLinks: [String: String] = [:]
    nonisolated(unsafe) static var statuses: [String: Int] = [:]
    /// The user's personal calendar feeds on api.partiful.com, by path: the text, or a status.
    nonisolated(unsafe) static var feeds: [String: (Int, String)] = [:]

    static func answer(_ request: URLRequest) -> FakeGoogle.Answer {
        guard let url = request.url, let host = url.host else { return .init(status: 400, body: Data()) }
        let html = ["Content-Type": "text/html; charset=utf-8"]
        if host == "go.partiful.com" {
            guard let target = shortLinks[url.lastPathComponent] else { return .init(status: 404, body: Data(), headers: html) }
            return .init(status: 302, body: Data(), headers: ["Location": target])
        }
        if host == "api.partiful.com" || host == "calendar.google.com" {
            guard let (status, text) = feeds[url.path] else { return .init(status: 404, body: Data()) }
            if (300..<400).contains(status) { return .init(status: status, body: Data(), headers: ["Location": text]) }
            return .init(status: status, body: Data(text.utf8), headers: ["Content-Type": "text/calendar"])
        }
        guard host == "partiful.com" else { return .init(status: 404, body: Data(), headers: html) }
        if url.path == "/login" { return .init(status: 200, body: Data("<html>Sign in</html>".utf8), headers: html) }
        let id = url.lastPathComponent
        if let status = statuses[id] { return .init(status: status, body: Data(), headers: html) }
        guard let page = pages[id] else { return .init(status: 404, body: Data(), headers: html) }
        func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }
        func document(ld: [String: Any]?, props: [String: Any]) -> Data {
            var head = "<html><head>"
            if let ld { head += "<script type=\"application/ld+json\">\(json(ld))</script>" }
            let next = json(["props": ["pageProps": props]])
            return Data((head + "</head><body><script id=\"__NEXT_DATA__\" type=\"application/json\">\(next)</script></body></html>").utf8)
        }
        switch page {
        case .event(let ld, let timezone):
            var event: [String: Any] = ["id": id, "timezone": timezone, "visibility": "public"]
            event["title"] = ld["name"]
            return .init(status: 200, body: document(ld: ld, props: ["event": event, "passwordRequired": false]), headers: html)
        case .password:
            return .init(status: 200, body: document(ld: nil, props: ["passwordRequired": true]), headers: html)
        case .empty:
            return .init(status: 200, body: Data("<html><head><title>Partiful</title></head><body></body></html>".utf8), headers: html)
        case .redirect(let target):
            return .init(status: 302, body: Data(), headers: ["Location": target])
        }
    }
}
#endif
