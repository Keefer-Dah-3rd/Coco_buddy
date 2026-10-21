import SwiftUI
import BuddyIntegrations

/// A calendar change Coco suggested in chat: what, when, what it clashes with. Nothing
/// happens in Google Calendar until "Add" / "Move" / "Delete" — and the card reports only
/// what Google confirmed.
struct EventRequestCard: View {
    let request: AppModel.EventRequest
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkyKicker(heading, color: Sky.ink)
            content
            if !request.conflicts.isEmpty, case .waiting = request.state {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(request.conflicts) { event in
                        Text("Overlaps “\(event.title)” \(AppModel.describe(event.start, event.end, allDay: false))")
                            .font(Sky.text(11))
                            .foregroundStyle(Sky.accentText)
                    }
                }
            }
            footer
        }
        .padding(14)
        .skyCard(radius: Sky.Radius.card)
        .accessibilityElement(children: .contain)
    }

    private var heading: String {
        switch request.kind {
        case .create: "Add to Google Calendar"
        case .change: "Change event"
        case .delete: "Delete event"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch request.kind {
        case .create(let draft):
            VStack(alignment: .leading, spacing: 2) {
                line(draft.title, AppModel.describe(draft.start, draft.end, allDay: draft.isAllDay), draft.location)
                if let source = draft.source {
                    Link("From \(source.name) · keeps the invite link", destination: source.url)
                        .font(Sky.text(11)).foregroundStyle(Sky.muted)
                        .accessibilityLabel("Open the \(source.name) invitation")
                }
            }
        case .change(let event, let changes):
            VStack(alignment: .leading, spacing: 2) {
                Text(changes.title ?? event.title).font(Sky.text(13.5, .semibold)).foregroundStyle(Sky.ink)
                if let start = changes.start, let end = changes.end {
                    Text(AppModel.describe(event.start, event.end, allDay: event.isAllDay))
                        .font(Sky.text(12)).foregroundStyle(Sky.faint).strikethrough()
                    Text("→ " + AppModel.describe(start, end, allDay: event.isAllDay))
                        .font(Sky.text(12)).foregroundStyle(Sky.ink)
                }
                if let title = changes.title, title != event.title {
                    Text("Was “\(event.title)”").font(Sky.text(11)).foregroundStyle(Sky.muted)
                }
                if let location = changes.location {
                    Text("Location: \(location)").font(Sky.text(11)).foregroundStyle(Sky.muted)
                }
                if event.isRecurring { SkyKicker("Only this occurrence") }
                separateCopies(of: event)
            }
        case .delete(let event):
            VStack(alignment: .leading, spacing: 2) {
                line(event.title, AppModel.describe(event.start, event.end, allDay: event.isAllDay), event.location)
                if event.isRecurring { SkyKicker("Only this occurrence") }
                separateCopies(of: event)
            }
        }
    }

    /// The same meeting saved separately in another calendar (matched by its details, not
    /// synced): this change won't reach it, so say so before the user confirms.
    @ViewBuilder
    private func separateCopies(of event: CalendarEvent) -> some View {
        let copies = event.alsoIn.filter { $0.match == .details }
        if !copies.isEmpty {
            Text("Only the Google Calendar event changes — the copy in \(copies.map(\.label).joined(separator: " and ")) stays as it is.")
                .font(Sky.text(11)).foregroundStyle(Sky.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ title: String, _ when: String, _ location: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Sky.text(13.5, .semibold)).foregroundStyle(Sky.ink)
            Text(when).font(Sky.text(12)).foregroundStyle(Sky.ink)
            if let location, !location.isEmpty {
                Text(location).font(Sky.text(11)).foregroundStyle(Sky.muted).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch request.state {
        case .waiting:
            if !model.calendar.canChangeEvents {
                Text("The first time, Google asks you to let Coco change events.")
                    .font(Sky.text(11)).foregroundStyle(Sky.muted)
            }
            HStack(spacing: 8) {
                Button(confirmTitle) { model.confirmEventRequest(request.id) }
                    .buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
                Button("Not now") { model.declineEventRequest(request.id) }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            }
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                SkyKicker("Saving to Google Calendar…")
            }
        case .failed(let message):
            Text("Nothing changed: \(message)").font(Sky.text(11)).foregroundStyle(Sky.accentText)
            HStack(spacing: 8) {
                Button("Try again") { model.confirmEventRequest(request.id) }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                Button("Dismiss") { model.dismissEventRequest(request.id) }
                    .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
            }
        case .done(let outcome):
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Sky.accentText)
                Text(outcome).font(Sky.text(11)).foregroundStyle(Sky.ink).lineLimit(2)
                Spacer()
                Button { model.dismissEventRequest(request.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(SkyRoundStyle(size: 22, fill: .clear, tint: Sky.faint))
                    .accessibilityLabel("Dismiss")
            }
        }
    }

    private var confirmTitle: String {
        switch request.kind {
        case .create: "Add"
        case .change: "Change"
        case .delete: "Delete"
        }
    }
}
