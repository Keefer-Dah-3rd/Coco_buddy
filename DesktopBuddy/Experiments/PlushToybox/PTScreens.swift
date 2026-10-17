#if DEBUG
import SwiftUI
import BuddyCore

// EXPERIMENT — Plush Toybox screens. PTPanelView was written against these before they
// existed, which broke the build. Until plush versions are designed, each one shows the
// Editorial Orange screen it shares the same AppModel and sections with. Replace a
// placeholder by giving it its own body; the names and parameters are what PTPanelView uses.

/// Placeholder: the Editorial Orange Today screen.
struct PTTodayView: View {
    let model: AppModel
    @Binding var expandedEventID: String?
    var openSection: (EOSection) -> Void

    var body: some View {
        EOTodayView(model: model, expandedEventID: $expandedEventID, openSection: openSection)
    }
}

/// Placeholder: the Editorial Orange Focus screen.
struct PTFocusView: View {
    @Bindable var model: AppModel

    var body: some View { EOFocusView(model: model) }
}

/// Placeholder: the Editorial Orange Chat screen. Links to other sections are ignored here,
/// since PTPanelView doesn't pass a way to switch sections to its chat.
struct PTChatView: View {
    @Bindable var model: AppModel

    var body: some View { EOChatView(model: model, openSection: { _ in }) }
}

/// Placeholder: the Editorial Orange extras ("System") screen.
struct PTExtras: View {
    @Bindable var model: AppModel

    var body: some View { EOSystemView(model: model) }
}

/// Placeholder: the Editorial Orange task editor.
struct PTEditorSheet: View {
    let task: BuddyTask
    @Bindable var model: AppModel

    var body: some View { EOEditorSheet(task: task, model: model) }
}

/// Placeholder: the Editorial Orange review of tasks heard by voice.
struct PTVoiceReview: View {
    @Bindable var model: AppModel

    var body: some View { EOVoiceReviewSheet(model: model) }
}
#endif
