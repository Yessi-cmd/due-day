import Foundation

/// One alarm to schedule with AlarmKit. Pure value so planning stays testable.
struct PlannedAlarm: Hashable, Sendable {
    let reminderID: UUID
    let occurrence: CivilDate
    let fireDate: Date
    let title: String
}

/// Decides which due-day alarms should exist. Alarms ring like the Clock app (through silent
/// mode and Focus), so only the nearest ones are scheduled; the set is rebuilt on every reschedule.
enum AlarmPlanner {
    /// AlarmKit has a per-app cap (`maximumLimitReached`); stay well below it.
    static let limit = 20

    static func plan(reminders: [ReminderSnapshot], now: Date, calendar: Calendar, horizonDays: Int = 45) -> [PlannedAlarm] {
        let today = CivilDate(now, in: calendar)
        let horizon = today.adding(days: horizonDays)
        var result: [PlannedAlarm] = []

        for reminder in reminders where reminder.isActive && reminder.alarmEnabled {
            for occurrence in reminder.unsettledOccurrences(today: today, through: horizon) where occurrence.date >= today {
                guard let fireDate = occurrence.date.date(in: calendar, hour: reminder.reminderHour, minute: reminder.reminderMinute),
                      fireDate > now else { continue }
                result.append(PlannedAlarm(
                    reminderID: reminder.id, occurrence: occurrence.date, fireDate: fireDate,
                    title: title(for: reminder, occurrence: occurrence)
                ))
            }
            if reminder.kind == .subscription, let end = reminder.trialEnd, end >= today, end <= horizon,
               let fireDate = end.date(in: calendar, hour: reminder.reminderHour, minute: reminder.reminderMinute),
               fireDate > now {
                result.append(PlannedAlarm(reminderID: reminder.id, occurrence: end, fireDate: fireDate,
                                           title: "\(reminder.title) 免费试用今天结束"))
            }
        }
        return Array(result.sorted { ($0.fireDate, $0.title) < ($1.fireDate, $1.title) }.prefix(limit))
    }

    static func title(for reminder: ReminderSnapshot, occurrence: Occurrence) -> String {
        var parts = [reminder.title, reminder.kind == .custom ? "就是今天" : "今天到期"]
        if let period = reminder.periodLabel(occurrence) { parts.append(period) }
        if let amount = reminder.amount { parts.append(Formatting.money(amount, currency: reminder.currencyCode)) }
        return parts.joined(separator: " · ")
    }
}
