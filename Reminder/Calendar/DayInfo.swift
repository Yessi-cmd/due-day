import Foundation

/// Everything the calendar shows about one day.
struct DayInfo: Hashable, Sendable {
    let date: CivilDate
    let lunar: LunarDate
    let solarTerm: String?
    let festivals: [String]

    /// Cell subtitle: festival > solar term > lunar day (month name on 初一).
    var subtitle: String {
        if let festival = festivals.first { return festival }
        if let solarTerm { return solarTerm }
        return lunar.day == 1 ? lunar.monthName : lunar.dayName
    }

    var isHighlighted: Bool { !festivals.isEmpty || solarTerm != nil }
}

enum Festivals {
    private static let gregorian: [Int: String] = [
        0101: "元旦", 0214: "情人节", 0308: "妇女节", 0312: "植树节", 0501: "劳动节", 0504: "青年节",
        0601: "儿童节", 0701: "建党节", 0801: "建军节", 0910: "教师节", 1001: "国庆节",
        1224: "平安夜", 1225: "圣诞节",
    ]

    /// Only matched in non-leap months (闰五月初五 is not 端午).
    private static let lunar: [Int: String] = [
        0101: "春节", 0115: "元宵节", 0202: "龙抬头", 0505: "端午节", 0707: "七夕",
        0715: "中元节", 0815: "中秋节", 0909: "重阳节", 1208: "腊八节",
    ]

    static func festivals(on date: CivilDate, lunar l: LunarDate, nextDay: LunarDate, solarTerm: String?) -> [String] {
        var result: [String] = []
        // 除夕 is the last day of the lunar year — 腊月廿九 in years when 腊月 has 29 days.
        if nextDay.month == 1 && nextDay.day == 1 && !nextDay.isLeapMonth { result.append("除夕") }
        if !l.isLeapMonth, let name = lunar[l.month * 100 + l.day] { result.append(name) }
        if solarTerm == "清明" { result.append("清明节") }
        if let name = gregorian[date.month * 100 + date.day] { result.append(name) }
        if date == CivilDate.nthWeekday(1, ordinal: 2, year: date.year, month: 5) { result.append("母亲节") }
        if date == CivilDate.nthWeekday(1, ordinal: 3, year: date.year, month: 6) { result.append("父亲节") }
        return result
    }
}

enum DayInfoProvider {
    /// Day info for a contiguous range of days (computes each year's solar terms once).
    static func infos(from start: CivilDate, through end: CivilDate) -> [CivilDate: DayInfo] {
        guard start <= end else { return [:] }
        var terms: [Int: [CivilDate: String]] = [:]
        for year in start.year...end.year { terms[year] = SolarTerms.termsByDate(in: year) }

        var result: [CivilDate: DayInfo] = [:]
        var day = start
        var lunar = LunarCalendar.lunarDate(for: day)
        while day <= end {
            let next = day.adding(days: 1)
            let nextLunar = LunarCalendar.lunarDate(for: next)
            let term = terms[day.year]?[day]
            result[day] = DayInfo(
                date: day, lunar: lunar, solarTerm: term,
                festivals: Festivals.festivals(on: day, lunar: lunar, nextDay: nextLunar, solarTerm: term)
            )
            day = next
            lunar = nextLunar
        }
        return result
    }

    static func info(for day: CivilDate) -> DayInfo {
        infos(from: day, through: day)[day]!
    }
}
