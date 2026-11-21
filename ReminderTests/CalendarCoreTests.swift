import Foundation
import Testing
@testable import Reminder

@Suite("Gregorian")
struct GregorianTests {
    @Test("February length follows leap-year rules", arguments: [
        (1900, 28), (2000, 29), (2023, 28), (2024, 29), (2100, 28),
    ])
    func februaryLength(year: Int, days: Int) {
        #expect(CivilDate.daysInMonth(year: year, month: 2) == days)
    }

    @Test func dayArithmetic() {
        #expect(CivilDate(2024, 2, 28).adding(days: 1) == CivilDate(2024, 2, 29))
        #expect(CivilDate(2023, 2, 28).adding(days: 1) == CivilDate(2023, 3, 1))
        #expect(CivilDate(2024, 12, 31).adding(days: 1) == CivilDate(2025, 1, 1))
        #expect(CivilDate(2024, 1, 1).days(until: CivilDate(2025, 1, 1)) == 366)
        #expect(CivilDate(2025, 3, 1).adding(days: -1) == CivilDate(2025, 2, 28))
    }

    @Test func weekdays() {
        #expect(CivilDate(2025, 1, 1).weekday == 4) // Wednesday
        #expect(CivilDate(2000, 1, 1).weekday == 7) // Saturday
    }

    @Test func parsing() {
        #expect(CivilDate(string: "2025-07-25") == CivilDate(2025, 7, 25))
        #expect(CivilDate(string: "2025-02-29") == nil)
        #expect(CivilDate(string: "garbage") == nil)
        #expect(CivilDate(2025, 7, 5).description == "2025-07-05")
    }

    @Test("Mother's Day and Father's Day")
    func weekdayOrdinals() {
        #expect(CivilDate.nthWeekday(1, ordinal: 2, year: 2025, month: 5) == CivilDate(2025, 5, 11))
        #expect(CivilDate.nthWeekday(1, ordinal: 3, year: 2025, month: 6) == CivilDate(2025, 6, 15))
    }
}

@Suite("Lunar calendar")
struct LunarTests {
    @Test("Leap months are recognised", arguments: [
        (CivilDate(2020, 5, 23), 2020, 4),
        (CivilDate(2023, 3, 22), 2023, 2),
        (CivilDate(2025, 7, 25), 2025, 6),
    ])
    func leapMonthStart(date: CivilDate, year: Int, month: Int) {
        let lunar = LunarCalendar.lunarDate(for: date)
        #expect(lunar == LunarDate(lunarYear: year, month: month, isLeapMonth: true, day: 1))
        #expect(LunarCalendar.leapMonth(ofLunarYear: year) == month)
    }

    @Test("2033 has 闰十一月")
    func year2033() {
        #expect(LunarCalendar.leapMonth(ofLunarYear: 2033) == 11)
    }

    @Test("Years without a leap month have 12 months")
    func regularYear() {
        #expect(LunarCalendar.months(ofLunarYear: 2024).count == 12)
        #expect(LunarCalendar.months(ofLunarYear: 2025).count == 13)
    }

    @Test("Spring Festival dates", arguments: [
        (2020, CivilDate(2020, 1, 25)), (2023, CivilDate(2023, 1, 22)), (2024, CivilDate(2024, 2, 10)),
        (2025, CivilDate(2025, 1, 29)), (2026, CivilDate(2026, 2, 17)), (2027, CivilDate(2027, 2, 6)),
    ])
    func springFestival(year: Int, date: CivilDate) {
        #expect(LunarCalendar.newYear(of: year) == date)
    }

    @Test("Month lengths add up to the whole year")
    func monthsAreContiguous() {
        for year in [1901, 1984, 2020, 2025, 2033, 2099] {
            let months = LunarCalendar.months(ofLunarYear: year)
            for (a, b) in zip(months, months.dropFirst()) {
                #expect(a.firstDay.adding(days: a.length) == b.firstDay)
            }
            let last = months.last!
            #expect(last.firstDay.adding(days: last.length) == LunarCalendar.newYear(of: year + 1))
            #expect(months.allSatisfy { $0.length == 29 || $0.length == 30 })
        }
    }

    @Test("除夕 on 腊月廿九 (2025) and 腊月三十 (2024)")
    func newYearsEve() {
        let eve2025 = LunarCalendar.lunarDate(for: CivilDate(2025, 1, 28))
        #expect(eve2025 == LunarDate(lunarYear: 2024, month: 12, isLeapMonth: false, day: 29))
        #expect(DayInfoProvider.info(for: CivilDate(2025, 1, 28)).festivals.contains("除夕"))

        let eve2024 = LunarCalendar.lunarDate(for: CivilDate(2024, 2, 9))
        #expect(eve2024.day == 30)
        #expect(DayInfoProvider.info(for: CivilDate(2024, 2, 9)).festivals.contains("除夕"))
        #expect(!DayInfoProvider.info(for: CivilDate(2024, 2, 8)).festivals.contains("除夕"))
    }

    @Test("Lunar festivals")
    func festivals() {
        #expect(DayInfoProvider.info(for: CivilDate(2025, 10, 6)).festivals.contains("中秋节"))
        #expect(DayInfoProvider.info(for: CivilDate(2025, 5, 31)).festivals.contains("端午节"))
        #expect(DayInfoProvider.info(for: CivilDate(2025, 1, 29)).festivals.contains("春节"))
        #expect(DayInfoProvider.info(for: CivilDate(2025, 10, 1)).festivals.contains("国庆节"))
    }

    @Test("Round trip lunar → Gregorian")
    func roundTrip() {
        for date in [CivilDate(2020, 5, 23), CivilDate(2025, 7, 25), CivilDate(1999, 12, 31), CivilDate(2050, 6, 1)] {
            let l = LunarCalendar.lunarDate(for: date)
            #expect(LunarCalendar.civilDate(lunarYear: l.lunarYear, month: l.month, isLeapMonth: l.isLeapMonth, day: l.day) == date)
        }
        #expect(LunarCalendar.civilDate(lunarYear: 2024, month: 6, isLeapMonth: true, day: 1) == nil)
    }

    @Test("Supported range ends convert")
    func rangeEnds() {
        let first = LunarCalendar.lunarDate(for: CivilDate.minSupported)
        #expect(first.lunarYear == 1900)
        let last = LunarCalendar.lunarDate(for: CivilDate.maxSupported)
        #expect(last.lunarYear == 2099)
        #expect(!CivilDate(1900, 12, 31).isSupported)
        #expect(!CivilDate(2100, 1, 1).isSupported)
    }

    @Test("Device time zone does not change lunar dates")
    func timeZoneIndependent() {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        #expect(LunarCalendar.lunarDate(for: CivilDate(2025, 7, 25)) == LunarDate(lunarYear: 2025, month: 6, isLeapMonth: true, day: 1))
        #expect(LunarCalendar.newYear(of: 2026) == CivilDate(2026, 2, 17))
    }

    @Test func names() {
        #expect(LunarCalendar.monthName(11, isLeap: false) == "冬月")
        #expect(LunarCalendar.monthName(6, isLeap: true) == "闰六月")
        #expect(LunarCalendar.dayName(1) == "初一")
        #expect(LunarCalendar.dayName(10) == "初十")
        #expect(LunarCalendar.dayName(20) == "二十")
        #expect(LunarCalendar.dayName(21) == "廿一")
        #expect(LunarCalendar.dayName(30) == "三十")
        #expect(LunarCalendar.ganzhi(2025) == "乙巳")
        #expect(LunarCalendar.ganzhi(1984) == "甲子")
        #expect(LunarCalendar.zodiac(2025) == "蛇")
        #expect(LunarCalendar.lunarDate(for: CivilDate(2025, 7, 25)).fullDescription == "乙巳年（蛇）闰六月初一")
    }
}

@Suite("Solar terms")
struct SolarTermTests {
    @Test("Known solar term dates", arguments: [
        ("立春", CivilDate(2024, 2, 4)), ("冬至", CivilDate(2024, 12, 21)),
        ("立春", CivilDate(2025, 2, 3)), ("春分", CivilDate(2025, 3, 20)), ("清明", CivilDate(2025, 4, 4)),
        ("夏至", CivilDate(2025, 6, 21)), ("冬至", CivilDate(2025, 12, 21)),
        ("立春", CivilDate(2026, 2, 4)),
    ])
    func knownDates(name: String, date: CivilDate) {
        let terms = SolarTerms.terms(in: date.year)
        #expect(terms.first { $0.name == name }?.date == date)
    }

    @Test("24 terms in increasing order every year")
    func ordering() {
        for year in [1901, 1950, 2000, 2025, 2099] {
            let terms = SolarTerms.terms(in: year)
            #expect(terms.count == 24)
            #expect(zip(terms, terms.dropFirst()).allSatisfy { $0.moment < $1.moment })
            #expect(terms.allSatisfy { $0.date.year == year })
        }
    }

    @Test("清明 shows as a festival")
    func qingming() {
        #expect(DayInfoProvider.info(for: CivilDate(2025, 4, 4)).festivals.contains("清明节"))
    }
}
