import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct ReminderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = AppClock()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationScheduler.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(clock)
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                    refresh()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    refresh()
                }
        }
        .modelContainer(AppModel.shared.container)
        .onChange(of: scenePhase) {
            if scenePhase == .active { refresh() }
            if scenePhase == .background { NotificationScheduler.scheduleAppRefresh() }
        }
        .backgroundTask(.appRefresh(NotificationScheduler.refreshTaskID)) {
            await NotificationScheduler.rescheduleNow()
        }
    }

    private func refresh() {
        clock.refresh()
        NotificationScheduler.setNeedsReschedule()
    }
}
