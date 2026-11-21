import Foundation

struct Occurrence: Hashable, Sendable {
    /// 0-based position in the series (installment period = index + 1).
    let index: Int
    let date: CivilDate
}

/// The single source of truth for "when does this rule fire" (AGENTS.md §6.2).
///
/// Every occurrence is derived from the anchor (`start`) and its index — never from the
/// previous occurrence — so month-end clamping cannot drift (Jan 31 → Feb 28 → Mar 31).
struct OccurrenceSequence: Sequence, IteratorProtocol {
    let rule: RecurrenceRule
    let start: CivilDate
    private var index: Int
    private let lunarAnchor: LunarDate?
    private var lunarYears: [Int: [LunarMonth]] = [:]
    /// Consecutive lunar months beginning with the anchor's month (for lunar monthly rules).
    private var monthChain: [LunarMonth] = []

    init(rule: RecurrenceRule, start: CivilDate, startIndex: Int = 0) {
        self.rule = rule
        self.start = start
        self.index = max(0, startIndex)
        self.lunarAnchor = rule.calendar == .lunar ? LunarCalendar.lunarDate(for: start) : nil
    }

    mutating func next() -> Occurrence? {
        if rule.frequency == .none && index > 0 { return nil }
        if rule.endKind == .count, let count = rule.endCount, index >= count { return nil }
        guard let date = date(at: index), date <= CivilDate.maxSupported else { return nil }
        if rule.endKind == .until, let until = rule.endDate, date > until { return nil }
        defer { index += 1 }
        return Occurrence(index: index, date: date)
    }

    private mutating func date(at n: Int) -> CivilDate? {
        let step = max(1, rule.interval)
        switch rule.frequency {
        case .none:
            return start
        case .daily:
            return start.adding(days: n * step)
        case .weekly:
            return start.adding(days: n * step * 7)
        case .monthly:
            if let anchor = lunarAnchor { return lunarMonthly(anchor: anchor, offset: n * step) }
            let (y, m) = start.monthShifted(by: n * step)
            let length = CivilDate.daysInMonth(year: y, month: m)
            return CivilDate(y, m, rule.monthlyMode == .lastDay ? length : min(start.day, length))
        case .yearly:
            if let anchor = lunarAnchor { return lunarYearly(anchor: anchor, year: anchor.lunarYear + n * step) }
            let y = start.year + n * step
            return CivilDate(y, start.month, min(start.day, CivilDate.daysInMonth(year: y, month: start.month)))
        }
    }

    private mutating func months(ofLunarYear year: Int) -> [LunarMonth]? {
        guard LunarCalendar.supportedLunarYears.contains(year) else { return nil }
        if let cached = lunarYears[year] { return cached }
        let months = LunarCalendar.months(ofLunarYear: year)
        lunarYears[year] = months
        return months
    }

    private mutating func lunarMonthly(anchor: LunarDate, offset: Int) -> CivilDate? {
        if monthChain.isEmpty {
            guard let months = months(ofLunarYear: anchor.lunarYear),
                  let i = months.firstIndex(where: { $0.month == anchor.month && $0.isLeapMonth == anchor.isLeapMonth })
            else { return nil }
            monthChain = Array(months[i...])
        }
        while monthChain.count <= offset {
            guard let next = months(ofLunarYear: monthChain.last!.lunarYear + 1) else { return nil }
            monthChain.append(contentsOf: next)
        }
        let month = monthChain[offset]
        return month.date(day: rule.monthlyMode == .lastDay ? month.length : anchor.day)
    }

    /// Leap-month anchors use the leap month when that year has it, otherwise the regular month;
    /// day 30 falls back to 29 in short months (AGENTS.md §5.6).
    private mutating func lunarYearly(anchor: LunarDate, year: Int) -> CivilDate? {
        guard let months = months(ofLunarYear: year) else { return nil }
        let match = months.first { $0.month == anchor.month && $0.isLeapMonth == anchor.isLeapMonth }
            ?? months.first { $0.month == anchor.month && !$0.isLeapMonth }
        return match?.date(day: anchor.day)
    }
}

enum OccurrenceGenerator {
    /// Occurrences with `lower <= date <= upper`, in order.
    static func occurrences(
        of rule: RecurrenceRule, start: CivilDate,
        from lower: CivilDate, through upper: CivilDate, maxCount: Int = 500
    ) -> [Occurrence] {
        var sequence = OccurrenceSequence(rule: rule, start: start, startIndex: skipEstimate(rule: rule, start: start, lower: lower))
        var result: [Occurrence] = []
        while result.count < maxCount, let occurrence = sequence.next() {
            if occurrence.date > upper { break }
            if occurrence.date >= lower { result.append(occurrence) }
        }
        return result
    }

    static func first(_ count: Int, of rule: RecurrenceRule, start: CivilDate, from lower: CivilDate) -> [Occurrence] {
        occurrences(of: rule, start: start, from: lower, through: CivilDate.maxSupported, maxCount: count)
    }

    static func occurrence(at index: Int, of rule: RecurrenceRule, start: CivilDate) -> Occurrence? {
        var sequence = OccurrenceSequence(rule: rule, start: start, startIndex: index)
        return sequence.next()
    }

    /// A safe lower bound for the first index on or after `lower`, so long-running
    /// daily/weekly series don't iterate from the very beginning.
    private static func skipEstimate(rule: RecurrenceRule, start: CivilDate, lower: CivilDate) -> Int {
        let days = start.days(until: lower)
        guard days > 0 else { return 0 }
        let step = max(1, rule.interval)
        switch rule.frequency {
        case .none: return 0
        case .daily: return days / step - 1
        case .weekly: return days / (7 * step) - 1
        case .monthly: return rule.calendar == .lunar ? 0 : days / (31 * step) - 1
        case .yearly: return days / (366 * step) - 1
        }
    }
}
