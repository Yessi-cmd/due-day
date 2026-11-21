import Foundation

/// One local notification to schedule. Pure value; turned into a UNNotificationRequest later.
struct PlannedNotification: Hashable, Sendable {
    let identifier: String
    let reminderID: UUID
    let occurrence: CivilDate
    let fireDay: CivilDate
    let hour: Int
    let minute: Int
    let fireDate: Date
    let title: String
    let body: String
    let timeSensitive: Bool
    /// Whether the notification offers the "已付/完成" action.
    let settleable: Bool
    let settleVerb: String
}

/// Decides which notifications should be pending (AGENTS.md §7).
///
/// iOS keeps at most 64 pending local notifications per app, and repeating triggers can't
/// express month-end clamping or lunar dates, so we compute one-shot notifications for the
/// near future and keep only the earliest `limit`.
enum NotificationPlanner {
    static let defaultLimit = 60

    static func plan(
        reminders: [ReminderSnapshot], now: Date, calendar: Calendar,
        timeSensitive: Bool, horizonDays: Int = 120, limit: Int = defaultLimit
    ) -> [PlannedNotification] {
        let today = CivilDate(now, in: calendar)
        let horizon = today.adding(days: horizonDays)
        var result: [PlannedNotification] = []

        for reminder in reminders where reminder.isActive {
            var offsets = Set(reminder.advanceDays.filter { $0 >= 0 })
            if reminder.tracksOverdue { offsets.insert(-1) } // one nudge the day after it's due
            let maxOffset = offsets.max() ?? 0
            let occurrences = reminder.unsettledOccurrences(today: today.adding(days: -1), through: horizon.adding(days: maxOffset))

            for occurrence in occurrences {
                if reminder.nagEnabled {
                    result += nagNotifications(for: reminder, occurrence: occurrence, now: now, calendar: calendar, timeSensitive: timeSensitive)
                }
                for offset in offsets {
                    let fireDay = occurrence.date.adding(days: -offset)
                    guard fireDay <= horizon,
                          let fireDate = fireDay.date(in: calendar, hour: reminder.reminderHour, minute: reminder.reminderMinute),
                          fireDate > now else { continue }
                    result.append(PlannedNotification(
                        identifier: "\(reminder.id.uuidString).\(occurrence.date).\(offset)",
                        reminderID: reminder.id, occurrence: occurrence.date, fireDay: fireDay,
                        hour: reminder.reminderHour, minute: reminder.reminderMinute, fireDate: fireDate,
                        title: reminder.title,
                        body: body(for: reminder, occurrence: occurrence, offset: offset),
                        timeSensitive: timeSensitive && offset == 0,
                        settleable: true, settleVerb: reminder.kind.settleVerb
                    ))
                }
            }
            result += milestoneNotifications(for: reminder, today: today, horizon: horizon, now: now, calendar: calendar)
        }

        return Array(result.sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }.prefix(limit))
    }

    static func body(for reminder: ReminderSnapshot, occurrence: Occurrence, offset: Int) -> String {
        var parts: [String] = []
        if let period = reminder.periodLabel(occurrence) { parts.append(period) }
        switch offset {
        case ..<0: parts.append("已逾期 \(-offset) 天，记得处理")
        case 0: parts.append(reminder.kind == .custom ? "就是今天" : "今天到期")
        default:
            var when = "\(offset) 天后到期（\(Formatting.monthDayWeekday(occurrence.date))"
            if reminder.rule.calendar == .lunar {
                when += "，农历\(LunarCalendar.lunarDate(for: occurrence.date).shortDescription)"
            }
            parts.append(when + "）")
        }
        if let amount = reminder.amount { parts.append(Formatting.money(amount, currency: reminder.currencyCode)) }
        return parts.joined(separator: " · ")
    }

    /// Follow-ups on the due day every `nagIntervalMinutes` after the reminder time, until settled
    /// (marking it paid reschedules and drops the rest). They stop at midnight.
    static func nagNotifications(
        for reminder: ReminderSnapshot, occurrence: Occurrence, now: Date, calendar: Calendar, timeSensitive: Bool
    ) -> [PlannedNotification] {
        let interval = max(5, reminder.nagIntervalMinutes)
        let base = reminder.reminderHour * 60 + reminder.reminderMinute
        let prefix = reminder.kind == .custom ? "还没完成" : "还没标记已付"
        return (1...max(1, reminder.nagCount)).compactMap { k in
            let minutes = base + k * interval
            guard minutes < 24 * 60,
                  let fireDate = occurrence.date.date(in: calendar, hour: minutes / 60, minute: minutes % 60),
                  fireDate > now else { return nil }
            return PlannedNotification(
                identifier: "\(reminder.id.uuidString).\(occurrence.date).nag\(k)",
                reminderID: reminder.id, occurrence: occurrence.date, fireDay: occurrence.date,
                hour: minutes / 60, minute: minutes % 60, fireDate: fireDate,
                title: reminder.title,
                body: "\(prefix)（第 \(k + 1) 次提醒）· " + body(for: reminder, occurrence: occurrence, offset: 0),
                timeSensitive: timeSensitive,
                settleable: true, settleVerb: reminder.kind.settleVerb
            )
        }
    }

    /// Free-trial end (subscriptions) and lease end (rent) get their own heads-up.
    private static func milestoneNotifications(
        for reminder: ReminderSnapshot, today: CivilDate, horizon: CivilDate, now: Date, calendar: Calendar
    ) -> [PlannedNotification] {
        var items: [(day: CivilDate, offset: Int, body: String)] = []
        if reminder.kind == .subscription, let end = reminder.trialEnd {
            items.append((end, 1, "免费试用明天结束，不想续费记得取消"))
            items.append((end, 0, "免费试用今天结束"))
        }
        if reminder.kind == .rent, let end = reminder.contractEnd {
            items.append((end, 30, "租房合同 30 天后到期（\(Formatting.fullDate(end))）"))
            items.append((end, 7, "租房合同 7 天后到期，记得续租或安排搬家"))
        }
        return items.compactMap { item in
            let fireDay = item.day.adding(days: -item.offset)
            guard fireDay <= horizon,
                  let fireDate = fireDay.date(in: calendar, hour: reminder.reminderHour, minute: reminder.reminderMinute),
                  fireDate > now else { return nil }
            return PlannedNotification(
                identifier: "\(reminder.id.uuidString).milestone.\(item.day).\(item.offset)",
                reminderID: reminder.id, occurrence: item.day, fireDay: fireDay,
                hour: reminder.reminderHour, minute: reminder.reminderMinute, fireDate: fireDate,
                title: reminder.title, body: item.body, timeSensitive: false,
                settleable: false, settleVerb: reminder.kind.settleVerb
            )
        }
    }
}
