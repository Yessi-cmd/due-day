import Foundation

/// Chinese display strings for dates, times and money.
enum Formatting {
    private static let shortWeekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let longWeekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private static let moneyLocale = Locale(identifier: "zh_CN")

    /// 1 = Sunday.
    static func weekdayName(_ weekday: Int) -> String { shortWeekdays[weekday - 1] }

    static func fullDate(_ d: CivilDate) -> String { "\(d.year)年\(d.month)月\(d.day)日" }

    static func monthDay(_ d: CivilDate) -> String { "\(d.month)月\(d.day)日" }

    static func monthDayWeekday(_ d: CivilDate) -> String { "\(monthDay(d)) \(weekdayName(d.weekday))" }

    static func fullDateWeekday(_ d: CivilDate) -> String { "\(fullDate(d)) \(longWeekdays[d.weekday - 1])" }

    /// Omits the year when it is the current one.
    static func smartDate(_ d: CivilDate, today: CivilDate) -> String {
        d.year == today.year ? monthDayWeekday(d) : "\(fullDate(d)) \(weekdayName(d.weekday))"
    }

    static func time(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    static func money(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency).locale(moneyLocale))
    }

    static func currencySymbol(_ code: String) -> String {
        Locale(identifier: "zh_CN@currency=\(code)").currencySymbol ?? code
    }

    /// "今天" / "明天" / "3 天后" / "逾期 2 天"
    static func relativeDays(_ days: Int) -> String {
        switch days {
        case ..<0: return "逾期 \(-days) 天"
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default: return "\(days) 天后"
        }
    }

    static func advance(_ days: Int) -> String {
        days == 0 ? "当天" : "提前 \(days) 天"
    }

    /// Parses user input such as "39.9" or "1,299" into a Decimal.
    static func parseAmount(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}
