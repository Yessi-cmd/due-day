import Foundation
import Testing
@testable import Reminder

@Suite("Recurrence")
struct RecurrenceTests {
    private func dates(_ rule: RecurrenceRule, start: CivilDate, count: Int) -> [CivilDate] {
        Array(OccurrenceSequence(rule: rule, start: start).prefix(count)).map(\.date)
    }

    @Test("Monthly on the 31st clamps without drifting")
    func monthEndClamp() {
        let rule = RecurrenceRule(frequency: .monthly)
        let expected = [
            CivilDate(2025, 1, 31), CivilDate(2025, 2, 28), CivilDate(2025, 3, 31), CivilDate(2025, 4, 30),
            CivilDate(2025, 5, 31), CivilDate(2025, 6, 30), CivilDate(2025, 7, 31), CivilDate(2025, 8, 31),
            CivilDate(2025, 9, 30), CivilDate(2025, 10, 31), CivilDate(2025, 11, 30), CivilDate(2025, 12, 31),
            CivilDate(2026, 1, 31), CivilDate(2026, 2, 28),
        ]
        #expect(dates(rule, start: CivilDate(2025, 1, 31), count: 14) == expected)
        #expect(dates(rule, start: CivilDate(2024, 1, 31), count: 2) == [CivilDate(2024, 1, 31), CivilDate(2024, 2, 29)])
    }

    @Test("Last day of month mode")
    func lastDay() {
        var rule = RecurrenceRule(frequency: .monthly)
        rule.monthlyMode = .lastDay
        #expect(dates(rule, start: CivilDate(2024, 1, 31), count: 4) ==
            [CivilDate(2024, 1, 31), CivilDate(2024, 2, 29), CivilDate(2024, 3, 31), CivilDate(2024, 4, 30)])
    }

    @Test("Feb 29 yearly falls back to Feb 28")
    func leapDayYearly() {
        let rule = RecurrenceRule(frequency: .yearly)
        #expect(dates(rule, start: CivilDate(2024, 2, 29), count: 5) ==
            [CivilDate(2024, 2, 29), CivilDate(2025, 2, 28), CivilDate(2026, 2, 28), CivilDate(2027, 2, 28), CivilDate(2028, 2, 29)])
    }

    @Test("Quarterly and interval rules")
    func intervals() {
        let quarterly = RecurrenceRule(frequency: .monthly, interval: 3)
        #expect(dates(quarterly, start: CivilDate(2025, 11, 30), count: 3) ==
            [CivilDate(2025, 11, 30), CivilDate(2026, 2, 28), CivilDate(2026, 5, 30)])
        let biweekly = RecurrenceRule(frequency: .weekly, interval: 2)
        #expect(dates(biweekly, start: CivilDate(2025, 12, 25), count: 3) ==
            [CivilDate(2025, 12, 25), CivilDate(2026, 1, 8), CivilDate(2026, 1, 22)])
    }

    @Test("End conditions")
    func ends() {
        var rule = RecurrenceRule(frequency: .monthly)
        rule.endKind = .count
        rule.endCount = 3
        #expect(dates(rule, start: CivilDate(2025, 1, 15), count: 10).count == 3)

        rule.endKind = .until
        rule.endDate = CivilDate(2025, 4, 14)
        #expect(dates(rule, start: CivilDate(2025, 1, 15), count: 10).last == CivilDate(2025, 3, 15))

        #expect(dates(.once, start: CivilDate(2025, 1, 15), count: 10) == [CivilDate(2025, 1, 15)])
    }

    @Test("Range queries skip ahead correctly")
    func rangeQuery() {
        let daily = RecurrenceRule(frequency: .daily)
        let result = OccurrenceGenerator.occurrences(
            of: daily, start: CivilDate(2000, 1, 1), from: CivilDate(2025, 3, 1), through: CivilDate(2025, 3, 3))
        #expect(result.map(\.date) == [CivilDate(2025, 3, 1), CivilDate(2025, 3, 2), CivilDate(2025, 3, 3)])
        #expect(result.first?.index == CivilDate(2000, 1, 1).days(until: CivilDate(2025, 3, 1)))

        let monthly = RecurrenceRule(frequency: .monthly)
        let m = OccurrenceGenerator.occurrences(
            of: monthly, start: CivilDate(2010, 1, 31), from: CivilDate(2025, 2, 1), through: CivilDate(2025, 3, 31))
        #expect(m.map(\.date) == [CivilDate(2025, 2, 28), CivilDate(2025, 3, 31)])
    }

    @Test("Lunar yearly: day 30 falls back to 29")
    func lunarThirtieth() {
        let rule = RecurrenceRule(calendar: .lunar, frequency: .yearly)
        // 2024-02-09 is 腊月三十; the next 腊月 (lunar 2024) only has 29 days.
        let result = dates(rule, start: CivilDate(2024, 2, 9), count: 2)
        #expect(result == [CivilDate(2024, 2, 9), CivilDate(2025, 1, 28)])
    }

    @Test("Lunar yearly: leap-month anchor uses the regular month when the leap month is absent")
    func lunarLeapAnchor() {
        let rule = RecurrenceRule(calendar: .lunar, frequency: .yearly)
        let result = Array(OccurrenceSequence(rule: rule, start: CivilDate(2020, 5, 23)).prefix(2))
        #expect(result[0].date == CivilDate(2020, 5, 23))
        #expect(LunarCalendar.lunarDate(for: result[1].date) == LunarDate(lunarYear: 2021, month: 4, isLeapMonth: false, day: 1))
    }

    @Test("Lunar yearly: Mid-Autumn")
    func midAutumn() {
        let rule = RecurrenceRule(calendar: .lunar, frequency: .yearly)
        let result = dates(rule, start: CivilDate(2024, 9, 17), count: 2)
        #expect(result == [CivilDate(2024, 9, 17), CivilDate(2025, 10, 6)])
    }

    @Test("Lunar monthly counts leap months")
    func lunarMonthly() {
        let rule = RecurrenceRule(calendar: .lunar, frequency: .monthly)
        // 2025 六月初一, then 闰六月初一, then 七月初一.
        let start = LunarCalendar.civilDate(lunarYear: 2025, month: 6, isLeapMonth: false, day: 1)!
        let result = dates(rule, start: start, count: 3).map(LunarCalendar.lunarDate(for:))
        #expect(result.map(\.month) == [6, 6, 7])
        #expect(result.map(\.isLeapMonth) == [false, true, false])
        #expect(result.allSatisfy { $0.day == 1 })
    }

    @Test("Rule survives JSON round trip and tolerates missing keys")
    func codable() throws {
        var rule = RecurrenceRule(calendar: .lunar, frequency: .yearly, interval: 2)
        rule.endKind = .until
        rule.endDate = CivilDate(2030, 1, 1)
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(RecurrenceRule.self, from: data) == rule)

        let partial = try JSONDecoder().decode(RecurrenceRule.self, from: Data(#"{"frequency":"monthly","future":1}"#.utf8))
        #expect(partial.frequency == .monthly)
        #expect(partial.calendar == .gregorian)
        #expect(partial.interval == 1)
    }

    @Test func summaries() {
        #expect(RecurrenceRule(frequency: .monthly).summary(start: CivilDate(2025, 7, 25)) == "每月 25 日")
        #expect(RecurrenceRule(frequency: .yearly).summary(start: CivilDate(2025, 7, 25)) == "每年 7 月 25 日")
        #expect(RecurrenceRule(calendar: .lunar, frequency: .yearly).summary(start: CivilDate(2025, 10, 6)) == "农历每年 八月十五")
    }
}
