import Foundation
import UserNotifications

/// Local reminders with Done and Snooze actions. Respects quiet hours.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    enum ActionID {
        static let done = "PULSE_DONE"
        static let snooze = "PULSE_SNOOZE"
        static let category = "PULSE_REMINDER"
    }

    /// (actionIdentifier, reminderID)
    var onAction: ((String, UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
        let done = UNNotificationAction(identifier: ActionID.done, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: ActionID.snooze, title: "Snooze 10 min", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ActionID.category, actions: [done, snooze],
                                   intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces all repeating reminders. Anything inside quiet hours is skipped.
    func scheduleDaily(_ reminders: [Reminder], quietStart: Int, quietEnd: Int) {
        center.getPendingNotificationRequests { [center] pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("daily.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for reminder in reminders where !reminder.oneOff {
                if Self.isQuiet(reminder.minutes, start: quietStart, end: quietEnd) { continue }
                var components = DateComponents()
                components.hour = reminder.minutes / 60
                components.minute = reminder.minutes % 60
                let request = UNNotificationRequest(
                    identifier: "daily." + reminder.id.uuidString,
                    content: Self.content(title: reminder.title, reminderID: reminder.id),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
                center.add(request)
            }
        }
    }

    func scheduleOnce(id: String, title: String, afterMinutes: Int, reminderID: UUID) {
        let request = UNNotificationRequest(
            identifier: "once." + id,
            content: Self.content(title: title, reminderID: reminderID),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(Double(afterMinutes) * 60, 5), repeats: false))
        center.add(request)
    }

    static func isQuiet(_ minutes: Int, start: Int, end: Int) -> Bool {
        start > end ? (minutes >= start || minutes < end) : (minutes >= start && minutes < end)
    }

    private static func content(title: String, reminderID: UUID) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        content.categoryIdentifier = ActionID.category
        content.userInfo = ["reminderID": reminderID.uuidString]
        return content
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["reminderID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        onAction?(response.actionIdentifier, id)
    }
}
