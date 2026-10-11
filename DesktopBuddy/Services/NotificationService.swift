import Foundation
import Observation
import UserNotifications
import BuddyCore
import os

/// Native notifications for session ends. Permission is requested the first time
/// the user starts a session — not at launch.
@Observable
final class NotificationService: NSObject {
    enum Authorization {
        case notDetermined, allowed, denied, unavailable
    }

    private(set) var authorization: Authorization = .notDetermined

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "notifications")
    private static let sessionEndID = "focus.session-end"

    override init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: authorization = .allowed
        case .denied: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .unavailable
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard authorization == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorization = granted ? .allowed : .denied
        } catch {
            log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            authorization = .unavailable
        }
    }

    func scheduleSessionEnd(at date: Date, phase: FocusPhase, minutes: Int, taskTitle: String?,
                            next: FocusPhase, nextMinutes: Int) {
        cancelSessionEnd()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        switch phase {
        case .focus:
            content.title = "Focus session complete"
            let on = taskTitle.map { " on “\($0)”" } ?? ""
            content.body = "\(minutes) minutes\(on). Time for a \(nextMinutes)-minute \(next == .longBreak ? "long " : "")break."
        case .shortBreak, .longBreak:
            content.title = "Break's over"
            content.body = "Ready for another round? \(Buddy.name) is standing by."
        }
        // Silent: the app plays its own (mutable) chime when it's running.
        content.sound = nil
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.sessionEndID, content: content, trigger: trigger)
        Task {
            await requestAuthorizationIfNeeded()
            guard authorization == .allowed else { return }
            do {
                try await center.add(request)
            } catch {
                log.error("Couldn't schedule notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A one-off notification at a given time (meeting reminders).
    func schedule(id: String, title: String, body: String, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        Task {
            await requestAuthorizationIfNeeded()
            guard authorization == .allowed else { return }
            try? await center.add(request)
        }
    }

    func cancel(prefix: String) {
        Task {
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cancelSessionEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.sessionEndID])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Show the banner even while one of the buddy's windows is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
