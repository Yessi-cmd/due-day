import Foundation

/// UserDefaults keys and defaults shared by @AppStorage views and non-UI logic.
enum AppSettings {
    static let defaultHourKey = "defaultReminderHour"
    static let defaultMinuteKey = "defaultReminderMinute"
    static let defaultAdvanceKey = "defaultAdvanceDays"
    static let timeSensitiveKey = "useTimeSensitive"
    static let weekStartsOnMondayKey = "weekStartsOnMonday"

    static var defaultHour: Int { UserDefaults.standard.object(forKey: defaultHourKey) as? Int ?? 9 }
    static var defaultMinute: Int { UserDefaults.standard.object(forKey: defaultMinuteKey) as? Int ?? 0 }
    static var defaultAdvance: Int { UserDefaults.standard.object(forKey: defaultAdvanceKey) as? Int ?? 3 }
    static var timeSensitive: Bool { UserDefaults.standard.object(forKey: timeSensitiveKey) as? Bool ?? true }

    /// Options offered for "提前几天提醒".
    static let advanceOptions = [0, 1, 2, 3, 5, 7, 15, 30]
}
