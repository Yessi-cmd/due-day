import Foundation
import SwiftData
import UserNotifications

/// Handles notification presentation and the "已付/完成" and "明天再提醒" actions.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let title = content.title
        let body = content.body
        let category = content.categoryIdentifier
        let reminderID = (content.userInfo["reminderID"] as? String).flatMap(UUID.init(uuidString:))
        let occurrence = (content.userInfo["occurrence"] as? String).flatMap(CivilDate.init(string:))
        guard let reminderID, let occurrence else { return }

        await NotificationActions.handle(
            action: action, reminderID: reminderID, occurrence: occurrence,
            title: title, body: body, category: category
        )
    }
}

@MainActor
enum NotificationActions {
    static func handle(
        action: String, reminderID: UUID, occurrence: CivilDate, title: String, body: String, category: String
    ) async {
        switch action {
        case NotificationScheduler.actionSettle:
            let context = AppModel.shared.container.mainContext
            var descriptor = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == reminderID })
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else { return }
            ReminderActions.markSettled(item, occurrence: occurrence, context: context)
        case NotificationScheduler.actionSnooze:
            NotificationScheduler.snooze(
                title: title, body: body, categoryIdentifier: category,
                userInfo: ["reminderID": reminderID.uuidString, "occurrence": occurrence.description]
            )
        default:
            break
        }
    }
}
