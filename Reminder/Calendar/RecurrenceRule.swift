import Foundation

enum CalendarKind: String, Codable, Sendable, CaseIterable {
    case gregorian
    case lunar
}

/// How a reminder repeats. The anchor (first occurrence) is the reminder's start date.
struct RecurrenceRule: Hashable, Sendable {
    enum Frequency: String, Codable, Sendable, CaseIterable {
        case none, daily, weekly, monthly, yearly
    }

    enum MonthlyMode: String, Codable, Sendable {
        /// Same day number as the anchor, clamped to the month's last day.
        case dayOfMonth
        /// Always the last day of the month.
        case lastDay
    }

    enum EndKind: String, Codable, Sendable {
        case never, until, count
    }

    var calendar: CalendarKind = .gregorian
    var frequency: Frequency = .monthly
    var interval: Int = 1
    var monthlyMode: MonthlyMode = .dayOfMonth
    var endKind: EndKind = .never
    var endDate: CivilDate?
    var endCount: Int?

    static let once = RecurrenceRule(frequency: .none)
}

extension RecurrenceRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case calendar, frequency, interval, monthlyMode, endKind, endDate, endCount
    }

    // Tolerant decoding: missing or unknown values fall back to defaults (AGENTS.md §10).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calendar = (try? c.decode(CalendarKind.self, forKey: .calendar)) ?? .gregorian
        frequency = (try? c.decode(Frequency.self, forKey: .frequency)) ?? .none
        interval = max(1, (try? c.decode(Int.self, forKey: .interval)) ?? 1)
        monthlyMode = (try? c.decode(MonthlyMode.self, forKey: .monthlyMode)) ?? .dayOfMonth
        endKind = (try? c.decode(EndKind.self, forKey: .endKind)) ?? .never
        endDate = try? c.decode(CivilDate.self, forKey: .endDate)
        endCount = try? c.decode(Int.self, forKey: .endCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(calendar, forKey: .calendar)
        try c.encode(frequency, forKey: .frequency)
        try c.encode(interval, forKey: .interval)
        try c.encode(monthlyMode, forKey: .monthlyMode)
        try c.encode(endKind, forKey: .endKind)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(endCount, forKey: .endCount)
    }
}

// MARK: - Description

extension RecurrenceRule {
    /// Human-readable rule, e.g. "每月 25 日" or "农历每年 八月十五".
    func summary(start: CivilDate) -> String {
        let lunar = calendar == .lunar ? LunarCalendar.lunarDate(for: start) : nil
        let n = interval
        var text: String
        switch frequency {
        case .none:
            text = "不重复"
        case .daily:
            text = n == 1 ? "每天" : "每 \(n) 天"
        case .weekly:
            let weekday = Formatting.weekdayName(start.weekday)
            text = n == 1 ? "每\(weekday)" : "每 \(n) 周的\(weekday)"
        case .monthly:
            let every = n == 1 ? "每月" : "每 \(n) 个月"
            if monthlyMode == .lastDay {
                text = (lunar != nil ? "农历" : "") + every + "最后一天"
            } else if let lunar {
                text = "农历\(every) \(lunar.dayName)"
            } else {
                text = "\(every) \(start.day) 日"
            }
        case .yearly:
            let every = n == 1 ? "每年" : "每 \(n) 年"
            if let lunar {
                text = "农历\(every) \(lunar.shortDescription)"
            } else {
                text = "\(every) \(start.month) 月 \(start.day) 日"
            }
        }
        switch endKind {
        case .never: break
        case .until: if let endDate { text += "，至 \(Formatting.fullDate(endDate))" }
        case .count: if let endCount { text += "，共 \(endCount) 次" }
        }
        return text
    }
}
