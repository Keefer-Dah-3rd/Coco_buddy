import Foundation
import Observation
import BuddyCore

/// Persisted history of focus sessions, for "focused today" and future reflection.
@Observable
final class FocusLogStore {
    private(set) var log: FocusLog

    @ObservationIgnored private let file: JSONFileStore<FocusLog>?

    init(persistent: Bool = true) {
        file = persistent ? try? JSONFileStore(name: "focus-log") : nil
        log = (try? file?.load()) ?? FocusLog()
    }

    func record(taskID: UUID?, seconds: TimeInterval, finished: Bool) {
        log.record(FocusSessionRecord(taskID: taskID, endedAt: .now, seconds: seconds, finished: finished))
        try? file?.save(log)
    }

    func eraseAll() {
        log = FocusLog()
        try? file?.delete()
    }

    var today: FocusLog.DaySummary {
        log.summary(on: .now)
    }
}
