import Foundation

/// A day in the Chinese lunisolar calendar.
struct LunarDate: Hashable, Sendable {
    /// Gregorian year in which this lunar year's 正月初一 falls (e.g. 2025 for 乙巳年).
    let lunarYear: Int
    let month: Int
    let isLeapMonth: Bool
    let day: Int

    var monthName: String { LunarCalendar.monthName(month, isLeap: isLeapMonth) }
    var dayName: String { LunarCalendar.dayName(day) }

    /// e.g. "乙巳年（蛇）闰六月初一"
    var fullDescription: String {
        "\(LunarCalendar.ganzhi(lunarYear))年（\(LunarCalendar.zodiac(lunarYear))）\(monthName)\(dayName)"
    }

    /// e.g. "闰六月初一"
    var shortDescription: String { monthName + dayName }
}

/// One month of a lunar year.
struct LunarMonth: Hashable, Sendable {
    let lunarYear: Int
    let month: Int
    let isLeapMonth: Bool
    let firstDay: CivilDate
    let length: Int

    var name: String { LunarCalendar.monthName(month, isLeap: isLeapMonth) }

    func date(day: Int) -> CivilDate { firstDay.adding(days: min(max(day, 1), length) - 1) }
}

/// Chinese calendar conversions built on Foundation's `.chinese` calendar.
///
/// The lunar calendar is defined in Beijing time (UTC+8), so every conversion uses
/// Asia/Shanghai regardless of the device time zone (AGENTS.md §5.1).
enum LunarCalendar {
    static let beijing = TimeZone(identifier: "Asia/Shanghai")!

    static let chinese: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    static let beijingGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    /// Lunar years whose months are guaranteed to be convertible.
    static let supportedLunarYears = 1900...2099

    static func lunarDate(for civil: CivilDate) -> LunarDate {
        let noon = civil.date(in: beijingGregorian, hour: 12)!
        let c = chinese.dateComponents(in: beijing, from: noon)
        let month = c.month!
        let lunarYear = (civil.month <= 2 && month >= 11) ? civil.year - 1 : civil.year
        return LunarDate(lunarYear: lunarYear, month: month, isLeapMonth: c.isLeapMonth ?? false, day: c.day!)
    }

    /// 正月初一 of the lunar year that starts in Gregorian `lunarYear` (always Jan 21 – Feb 20).
    static func newYear(of lunarYear: Int) -> CivilDate {
        var day = CivilDate(lunarYear, 1, 19)
        for _ in 0..<40 {
            let l = lunarDate(for: day)
            if l.month == 1 && l.day == 1 && !l.isLeapMonth { return day }
            day = day.adding(days: 1)
        }
        preconditionFailure("No lunar new year found for \(lunarYear)")
    }

    /// All months of a lunar year in order, including the leap month if there is one.
    static func months(ofLunarYear lunarYear: Int) -> [LunarMonth] {
        let end = newYear(of: lunarYear + 1)
        var start = newYear(of: lunarYear)
        var result: [LunarMonth] = []
        while start < end {
            let l = lunarDate(for: start)
            // A lunar month has 29 or 30 days: day 30 exists iff start+29 is still the same month.
            let length = lunarDate(for: start.adding(days: 29)).day == 30 ? 30 : 29
            result.append(LunarMonth(lunarYear: lunarYear, month: l.month, isLeapMonth: l.isLeapMonth,
                                     firstDay: start, length: length))
            start = start.adding(days: length)
        }
        return result
    }

    static func leapMonth(ofLunarYear lunarYear: Int) -> Int? {
        months(ofLunarYear: lunarYear).first(where: \.isLeapMonth)?.month
    }

    /// Gregorian date of a lunar date; nil if that (leap) month or day doesn't exist that year.
    static func civilDate(lunarYear: Int, month: Int, isLeapMonth: Bool, day: Int) -> CivilDate? {
        guard supportedLunarYears.contains(lunarYear),
              let m = months(ofLunarYear: lunarYear).first(where: { $0.month == month && $0.isLeapMonth == isLeapMonth }),
              (1...m.length).contains(day) else { return nil }
        return m.firstDay.adding(days: day - 1)
    }

    static func month(containing civil: CivilDate) -> LunarMonth {
        let l = lunarDate(for: civil)
        let first = civil.adding(days: -(l.day - 1))
        let length = lunarDate(for: first.adding(days: 29)).day == 30 ? 30 : 29
        return LunarMonth(lunarYear: l.lunarYear, month: l.month, isLeapMonth: l.isLeapMonth, firstDay: first, length: length)
    }

    // MARK: - Names

    private static let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    private static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
    private static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)
    private static let zodiacs = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪").map(String.init)

    static func monthName(_ month: Int, isLeap: Bool) -> String {
        (isLeap ? "闰" : "") + monthNames[month - 1] + "月"
    }

    static func dayName(_ day: Int) -> String {
        switch day {
        case 1...10: return "初" + digits[day - 1]
        case 11...19: return "十" + digits[day - 11]
        case 20: return "二十"
        case 21...29: return "廿" + digits[day - 21]
        default: return "三十"
        }
    }

    /// 干支 of a lunar year, e.g. 2025 → 乙巳. 1984 was 甲子.
    static func ganzhi(_ lunarYear: Int) -> String {
        let index = ((lunarYear - 1984) % 60 + 60) % 60
        return stems[index % 10] + branches[index % 12]
    }

    static func zodiac(_ lunarYear: Int) -> String {
        zodiacs[((lunarYear - 1984) % 12 + 12) % 12]
    }
}
