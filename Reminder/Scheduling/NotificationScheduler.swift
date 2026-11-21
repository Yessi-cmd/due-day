import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

/// Keeps the pending local notifications in sync with the data (AGENTS.md §7).
@MainActor
enum NotificationScheduler {
    static let categoryPay = "DUE_PAY"
    static let categoryDone = "DUE_DONE"
    static let categoryInfo = "INFO"
    static let actionSettle = "SETTLE"
    static let actionSnooze = "SNOOZE"
    static let snoozePrefix = "snooze."
    static let refreshTaskID = "app.aurora7963.honey1287.refresh"

    private static var pendingWork: Task<Void, Never>?

    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: actionSnooze, title: "明天再提醒")
        let pay = UNNotificationAction(identifier: actionSettle, title: "已付")
        let done = UNNotificationAction(identifier: actionSettle, title: "完成")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: categoryPay, actions: [pay, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: categoryDone, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: categoryInfo, actions: [snooze], intentIdentifiers: []),
        ])
    }

    static func requestAuthorizationIfNeeded() async {
        guard await authorizationStatus() == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                continuation.resume()
            }
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    static func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    /// Debounced reschedule; call after any data change.
    static func setNeedsReschedule() {
        pendingWork?.cancel()
        pendingWork = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await rescheduleNow()
        }
    }

    static func rescheduleNow(now: Date = .now, calendar: Calendar = .autoupdatingCurrent) async {
        let context = AppModel.shared.container.mainContext
        let items = (try? context.fetch(FetchDescriptor<ReminderItem>())) ?? []
        let snapshots = items.map { $0.snapshot(calendar: calendar) }
        let snoozes = await snoozeCount()
        let plan = NotificationPlanner.plan(
            reminders: snapshots, now: now, calendar: calendar,
            timeSensitive: AppSettings.timeSensitive,
            limit: NotificationPlanner.defaultLimit - min(4, snoozes)
        )

        let center = UNUserNotificationCenter.current()
        let stale = await pendingIdentifiers().filter { !$0.hasPrefix(snoozePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for item in plan {
            center.add(request(for: item, calendar: calendar), withCompletionHandler: nil)
        }

        let today = CivilDate(now, in: calendar)
        let badge = snapshots.filter(\.isActive).filter { ($0.status(today: today).daysUntilDue ?? 1) <= 0 }.count
        center.setBadgeCount(badge, withCompletionHandler: nil)
        scheduleAppRefresh()
    }

    private static func snoozeCount() async -> Int {
        await pendingIdentifiers().filter { $0.hasPrefix(snoozePrefix) }.count
    }

    private static func request(for item: PlannedNotification, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.categoryIdentifier = item.settleable ? (item.settleVerb == "完成" ? categoryDone : categoryPay) : categoryInfo
        content.userInfo = ["reminderID": item.reminderID.uuidString, "occurrence": item.occurrence.description]
        content.threadIdentifier = item.reminderID.uuidString
        if item.timeSensitive { content.interruptionLevel = .timeSensitive }

        // Full wall-clock components (no repeats): follows the device time zone at fire time.
        let components = DateComponents(
            year: item.fireDay.year, month: item.fireDay.month, day: item.fireDay.day,
            hour: item.hour, minute: item.minute
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
    }

    /// "明天再提醒": re-post the same notification 24 hours later.
    static func snooze(title: String, body: String, categoryIdentifier: String, userInfo: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 24 * 3600, repeats: false)
        let id = snoozePrefix + (userInfo["reminderID"] ?? UUID().uuidString) + "." + (userInfo["occurrence"] ?? "")
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil
        )
    }

    static func removeSnoozes(for reminderID: UUID) async {
        let ids = await pendingIdentifiers().filter { $0.hasPrefix(snoozePrefix + reminderID.uuidString) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Ask iOS to wake us roughly daily so the 60-notification window keeps rolling forward.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
