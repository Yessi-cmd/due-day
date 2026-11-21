import Foundation
import Testing
@testable import Reminder

@Suite("Reminder status and notification planning")
struct PlannerTests {
    private static let shanghai: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func snapshot(
        kind: ReminderKind = .rent,
        start: CivilDate,
        rule: RecurrenceRule = RecurrenceRule(frequency: .monthly),
        created: CivilDate,
        advance: [Int] = [3, 0],
        paid: Set<CivilDate> = [],
        prepaid: Int = 0,
        autoRenew: Bool = true
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: UUID(), kind: kind, title: "测试", amount: Decimal(string: "2500"), currencyCode: "CNY",
            startDate: start, rule: rule, reminderHour: 9, reminderMinute: 0, advanceDays: advance,
            createdDay: created, prepaidPeriods: prepaid, autoRenew: autoRenew,
            isCancelled: false, isArchived: false, trialEnd: nil, contractEnd: nil, paidDates: paid
        )
    }

    @Test("Unpaid rent becomes overdue; paying moves to the next month")
    func rentOverdue() {
        let today = CivilDate(2025, 7, 20)
        let rent = snapshot(start: CivilDate(2025, 1, 15), created: CivilDate(2025, 6, 1))
        let status = rent.status(today: today)
        #expect(status.due?.date == CivilDate(2025, 6, 15))
        #expect(status.overdueCount == 2)
        #expect(status.daysUntilDue == -35)

        let paid = snapshot(start: CivilDate(2025, 1, 15), created: CivilDate(2025, 6, 1),
                            paid: [CivilDate(2025, 6, 15), CivilDate(2025, 7, 15)])
        #expect(paid.status(today: today).due?.date == CivilDate(2025, 8, 15))
        #expect(paid.status(today: today).overdueCount == 0)
    }

    @Test("Auto-renewing subscriptions never go overdue")
    func subscriptionRollsOver() {
        let sub = snapshot(kind: .subscription, start: CivilDate(2025, 1, 10), created: CivilDate(2025, 1, 1))
        let status = sub.status(today: CivilDate(2025, 7, 20))
        #expect(status.due?.date == CivilDate(2025, 8, 10))
        #expect(status.overdueCount == 0)
    }

    @Test("Installments count prepaid periods and finish")
    func installments() {
        var rule = RecurrenceRule(frequency: .monthly)
        rule.endKind = .count
        rule.endCount = 3
        let plan = snapshot(kind: .installment, start: CivilDate(2025, 1, 5), rule: rule,
                            created: CivilDate(2025, 3, 1), prepaid: 2)
        let status = plan.status(today: CivilDate(2025, 3, 1))
        #expect(status.due == Occurrence(index: 2, date: CivilDate(2025, 3, 5)))
        #expect(plan.periodLabel(status.due!) == "第 3/3 期")

        let done = snapshot(kind: .installment, start: CivilDate(2025, 1, 5), rule: rule,
                            created: CivilDate(2025, 3, 1), paid: [CivilDate(2025, 3, 5)], prepaid: 2)
        #expect(done.status(today: CivilDate(2025, 3, 10)).isFinished)
    }

    @Test("Plan respects advance days, paid occurrences and the limit")
    func plan() {
        let calendar = Self.shanghai
        let now = CivilDate(2025, 7, 1).date(in: calendar, hour: 12)!
        let rent = snapshot(start: CivilDate(2025, 7, 15), created: CivilDate(2025, 7, 1),
                            paid: [CivilDate(2025, 8, 15)])
        let plan = NotificationPlanner.plan(reminders: [rent], now: now, calendar: calendar, timeSensitive: true, horizonDays: 60)

        let days = plan.map(\.fireDay)
        #expect(days.contains(CivilDate(2025, 7, 12)))   // 3 days before
        #expect(days.contains(CivilDate(2025, 7, 15)))   // due day
        #expect(days.contains(CivilDate(2025, 7, 16)))   // overdue nudge
        #expect(!plan.contains { $0.occurrence == CivilDate(2025, 8, 15) }) // already paid
        #expect(plan.first { $0.fireDay == CivilDate(2025, 7, 15) }?.timeSensitive == true)
        #expect(plan.first { $0.fireDay == CivilDate(2025, 7, 12) }?.timeSensitive == false)
        #expect(zip(plan, plan.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })

        let many = (0..<30).map { i in
            snapshot(kind: .custom, start: CivilDate(2025, 7, 2).adding(days: i), rule: RecurrenceRule(frequency: .daily),
                     created: CivilDate(2025, 7, 1))
        }
        #expect(NotificationPlanner.plan(reminders: many, now: now, calendar: calendar, timeSensitive: false).count == NotificationPlanner.defaultLimit)
    }

    @Test("Due-day nags repeat until midnight and stop once paid")
    func nags() {
        let calendar = Self.shanghai
        let now = CivilDate(2025, 7, 15).date(in: calendar, hour: 8)!
        var rent = snapshot(start: CivilDate(2025, 7, 15), created: CivilDate(2025, 7, 1), advance: [0])
        rent.nagEnabled = true
        rent.nagIntervalMinutes = 30
        rent.nagCount = 4
        let todays = NotificationPlanner.plan(reminders: [rent], now: now, calendar: calendar, timeSensitive: true)
            .filter { $0.fireDay == CivilDate(2025, 7, 15) }
        #expect(todays.map { $0.hour * 60 + $0.minute } == [540, 570, 600, 630, 660])
        #expect(todays.dropFirst().allSatisfy { $0.body.hasPrefix("还没标记已付") && $0.timeSensitive })

        // Late reminder time: nags never spill past midnight.
        let late = ReminderSnapshot(
            id: rent.id, kind: .rent, title: "测试", amount: nil, currencyCode: "CNY", startDate: rent.startDate,
            rule: rent.rule, reminderHour: 23, reminderMinute: 0, advanceDays: [0], createdDay: rent.createdDay,
            prepaidPeriods: 0, autoRenew: true, isCancelled: false, isArchived: false, trialEnd: nil, contractEnd: nil,
            paidDates: [], alarmEnabled: false, nagEnabled: true, nagIntervalMinutes: 30, nagCount: 4
        )
        let lateNags = NotificationPlanner.nagNotifications(
            for: late, occurrence: Occurrence(index: 0, date: CivilDate(2025, 7, 15)), now: now, calendar: calendar, timeSensitive: false)
        #expect(lateNags.count == 1)

        let paid = ReminderSnapshot(
            id: rent.id, kind: .rent, title: "测试", amount: nil, currencyCode: "CNY", startDate: rent.startDate,
            rule: rent.rule, reminderHour: 9, reminderMinute: 0, advanceDays: [0], createdDay: rent.createdDay,
            prepaidPeriods: 0, autoRenew: true, isCancelled: false, isArchived: false, trialEnd: nil, contractEnd: nil,
            paidDates: [CivilDate(2025, 7, 15)], alarmEnabled: false, nagEnabled: true, nagIntervalMinutes: 30, nagCount: 4
        )
        #expect(!NotificationPlanner.plan(reminders: [paid], now: now, calendar: calendar, timeSensitive: true)
            .contains { $0.occurrence == CivilDate(2025, 7, 15) })
    }

    @Test("Alarms only for enabled, unsettled due days")
    func alarms() {
        let calendar = Self.shanghai
        let now = CivilDate(2025, 7, 1).date(in: calendar, hour: 12)!
        var sub = snapshot(kind: .subscription, start: CivilDate(2025, 7, 10), created: CivilDate(2025, 7, 1),
                           paid: [CivilDate(2025, 8, 10)])
        sub.alarmEnabled = true
        let alarms = AlarmPlanner.plan(reminders: [sub], now: now, calendar: calendar)
        #expect(alarms.map(\.occurrence) == [CivilDate(2025, 7, 10)])
        #expect(alarms.first?.fireDate == CivilDate(2025, 7, 10).date(in: calendar, hour: 9))
        #expect(alarms.first?.title == "测试 · 今天到期 · ¥2,500.00")

        sub.alarmEnabled = false
        #expect(AlarmPlanner.plan(reminders: [sub], now: now, calendar: calendar).isEmpty)
    }

    @Test("Notification bodies")
    func bodies() {
        let rent = snapshot(start: CivilDate(2025, 7, 15), created: CivilDate(2025, 7, 1))
        let occurrence = Occurrence(index: 0, date: CivilDate(2025, 7, 15))
        #expect(NotificationPlanner.body(for: rent, occurrence: occurrence, offset: 0) == "今天到期 · ¥2,500.00")
        #expect(NotificationPlanner.body(for: rent, occurrence: occurrence, offset: 3).hasPrefix("3 天后到期（7月15日 周二）"))
        #expect(NotificationPlanner.body(for: rent, occurrence: occurrence, offset: -1).hasPrefix("已逾期 1 天"))
    }

    @Test("Monthly cost normalisation")
    func monthlyCost() {
        let yearly = snapshot(kind: .subscription, start: CivilDate(2025, 1, 1), rule: RecurrenceRule(frequency: .yearly), created: CivilDate(2025, 1, 1))
        #expect(yearly.monthlyCost.map { NSDecimalNumber(decimal: $0).doubleValue.rounded() } == 208)
        var total = MoneyTotal()
        total.add(Decimal(string: "10"), currency: "CNY")
        total.add(Decimal(string: "5.5"), currency: "CNY")
        #expect(total.formatted == "¥15.50")
    }

    @Test("Amount parsing")
    func parsing() {
        #expect(Formatting.parseAmount("39.9") == Decimal(string: "39.9"))
        #expect(Formatting.parseAmount("1,299") == Decimal(string: "1299"))
        #expect(Formatting.parseAmount("") == nil)
        #expect(Formatting.parseAmount("abc") == nil)
    }
}

@Suite("Backup")
struct BackupTests {
    @Test("Backup JSON round trip")
    func roundTrip() throws {
        let dto = BackupFile.ReminderDTO(
            id: UUID(), title: "房租", kind: "rent", amount: "2500", currencyCode: "CNY",
            startDate: CivilDate(2025, 1, 15), rule: RecurrenceRule(frequency: .monthly),
            reminderHour: 9, reminderMinute: 30, advanceDays: [3, 0], colorIndex: 0, symbolName: "house",
            note: "", autoRenew: true, isCancelled: false, isArchived: false, prepaidPeriods: 0,
            paymentMethod: "", payee: "王先生", trialEnd: nil, contractEnd: CivilDate(2026, 1, 14),
            createdAt: Date(timeIntervalSince1970: 1_750_000_000), updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            payments: [BackupFile.PaymentDTO(id: UUID(), occurrence: CivilDate(2025, 1, 15),
                                             paidAt: Date(timeIntervalSince1970: 1_750_000_000), amount: "2500")]
        )
        let file = BackupFile(version: 1, exportedAt: Date(timeIntervalSince1970: 1_750_000_000), reminders: [dto])
        let data = try BackupFile.encoder().encode(file)
        let decoded = try BackupFile.decoder().decode(BackupFile.self, from: data)
        #expect(decoded.reminders == [dto])
    }

    @Test("Minimal backup decodes")
    func minimal() throws {
        let json = #"{"version":1,"exportedAt":"2025-07-01T00:00:00Z","reminders":[{"id":"7C8E2C4E-2E0B-4C55-9A49-1A2B3C4D5E6F","title":"x","extra":true}]}"#
        let decoded = try BackupFile.decoder().decode(BackupFile.self, from: Data(json.utf8))
        #expect(decoded.reminders.first?.title == "x")
        #expect(decoded.reminders.first?.rule == nil)
    }
}
