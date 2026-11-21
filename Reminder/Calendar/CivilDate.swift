import Foundation

/// A Gregorian calendar day with no time and no time zone ("floating" date).
///
/// All day arithmetic goes through a UTC Gregorian calendar, so it is immune to DST and
/// device time-zone changes. Convert to a real `Date` only at the edges (UI, notifications).
struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.init(year: year, month: month, day: day)
    }

    /// The civil day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, in calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Parses `yyyy-MM-dd`.
    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let candidate = CivilDate(parts[0], parts[1], parts[2])
        guard candidate.isValid else { return nil }
        self = candidate
    }

    static let minSupported = CivilDate(1901, 1, 1)
    static let maxSupported = CivilDate(2099, 12, 31)

    /// Gregorian calendar fixed to UTC, used only for pure day arithmetic.
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    var isValid: Bool {
        (1...12).contains(month) && day >= 1 && day <= CivilDate.daysInMonth(year: year, month: month)
    }

    var isSupported: Bool { self >= CivilDate.minSupported && self <= CivilDate.maxSupported }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight UTC of this day. Only meaningful together with `utcCalendar`.
    var utcDate: Date {
        CivilDate.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// This day at the given wall-clock time in `calendar`'s time zone.
    func date(in calendar: Calendar, hour: Int = 0, minute: Int = 0) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    func adding(days: Int) -> CivilDate {
        let shifted = CivilDate.utcCalendar.date(byAdding: .day, value: days, to: utcDate)!
        return CivilDate(shifted, in: CivilDate.utcCalendar)
    }

    /// Whole days from `self` to `other` (negative if `other` is earlier).
    func days(until other: CivilDate) -> Int {
        CivilDate.utcCalendar.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// Year and month `months` after this date's month (day is not involved).
    func monthShifted(by months: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + months
        let y = Int((Double(total) / 12).rounded(.down))
        return (y, total - y * 12 + 1)
    }

    /// 1 = Sunday … 7 = Saturday.
    var weekday: Int {
        CivilDate.utcCalendar.component(.weekday, from: utcDate)
    }

    var firstOfMonth: CivilDate { CivilDate(year, month, 1) }

    var lastOfMonth: CivilDate { CivilDate(year, month, CivilDate.daysInMonth(year: year, month: month)) }

    static func daysInMonth(year: Int, month: Int) -> Int {
        let first = utcCalendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return utcCalendar.range(of: .day, in: .month, for: first)!.count
    }

    /// The `ordinal`-th given weekday (1 = Sunday) of a month, e.g. the 2nd Sunday of May.
    static func nthWeekday(_ weekday: Int, ordinal: Int, year: Int, month: Int) -> CivilDate {
        let first = CivilDate(year, month, 1)
        let offset = (weekday - first.weekday + 7) % 7
        return first.adding(days: offset + (ordinal - 1) * 7)
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CivilDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CivilDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(raw)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
