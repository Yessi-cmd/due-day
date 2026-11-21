import Foundation

/// An immutable, Sendable copy of a reminder used by all pure logic (status, notifications).
struct ReminderSnapshot: Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: ReminderKind
    let title: String
    let amount: Decimal?
    let currencyCode: String
    let startDate: CivilDate
    let rule: RecurrenceRule
    let reminderHour: Int
    let reminderMinute: Int
    let advanceDays: [Int]
    let createdDay: CivilDate
    let prepaidPeriods: Int
    let autoRenew: Bool
    let isCancelled: Bool
    let isArchived: Bool
    let trialEnd: CivilDate?
    let contractEnd: CivilDate?
    let paidDates: Set<CivilDate>

    var isActive: Bool { !isArchived && !(kind == .subscription && isCancelled) }

    /// Rent, installments and manually-paid subscriptions can become overdue. Auto-renewing
    /// subscriptions and custom reminders simply move on to the next occurrence.
    var tracksOverdue: Bool {
        switch kind {
        case .rent, .installment: true
        case .subscription: !autoRenew
        case .custom: false
        }
    }

    var totalPeriods: Int? {
        kind == .installment && rule.endKind == .count ? rule.endCount : nil
    }

    func isSettled(_ occurrence: Occurrence) -> Bool {
        (kind == .installment && occurrence.index < prepaidPeriods) || paidDates.contains(occurrence.date)
    }

    /// Earliest day whose unsettled occurrences still matter.
    func trackingStart(today: CivilDate) -> CivilDate {
        guard tracksOverdue else { return today }
        // Installments track from the first period (prepaid ones count as settled);
        // others ignore anything before the reminder was created.
        return kind == .installment ? startDate : min(createdDay, today)
    }

    func status(today: CivilDate) -> ReminderStatus {
        let candidates = OccurrenceGenerator.occurrences(
            of: rule, start: startDate, from: trackingStart(today: today),
            through: today.adding(days: 3_660), maxCount: 400
        )
        var overdue = 0
        var due: Occurrence?
        for occurrence in candidates where !isSettled(occurrence) {
            if due == nil { due = occurrence }
            if occurrence.date < today { overdue += 1 } else { break }
        }
        return ReminderStatus(due: due, overdueCount: overdue, daysUntilDue: due.map { today.days(until: $0.date) })
    }

    /// Unsettled occurrences from the tracking start through `upper`.
    func unsettledOccurrences(today: CivilDate, through upper: CivilDate) -> [Occurrence] {
        OccurrenceGenerator.occurrences(of: rule, start: startDate, from: trackingStart(today: today), through: upper)
            .filter { !isSettled($0) }
    }

    /// Amount normalized to one month, for subscription spending summaries.
    var monthlyCost: Decimal? {
        guard let amount, rule.frequency != .none else { return nil }
        let n = Decimal(max(1, rule.interval))
        switch rule.frequency {
        case .none: return nil
        case .daily: return amount * Decimal(string: "30.436875")! / n
        case .weekly: return amount * Decimal(string: "4.348125")! / n
        case .monthly: return amount / n
        case .yearly: return amount / (12 * n)
        }
    }

    func periodLabel(_ occurrence: Occurrence) -> String? {
        totalPeriods.map { "第 \(occurrence.index + 1)/\($0) 期" }
    }
}

struct ReminderStatus: Hashable, Sendable {
    /// Earliest unsettled occurrence (may be in the past when overdue); nil when finished.
    let due: Occurrence?
    let overdueCount: Int
    /// Negative when overdue.
    let daysUntilDue: Int?

    var isFinished: Bool { due == nil }
}

/// Sums money per currency so mixed currencies are never added together.
struct MoneyTotal: Hashable, Sendable {
    private(set) var amounts: [String: Decimal] = [:]

    mutating func add(_ amount: Decimal?, currency: String) {
        guard let amount else { return }
        amounts[currency, default: 0] += amount
    }

    var isEmpty: Bool { amounts.values.allSatisfy { $0 == 0 } }

    var formatted: String {
        guard !amounts.isEmpty else { return Formatting.money(0, currency: "CNY") }
        return amounts.sorted { ($0.key == "CNY" ? 0 : 1, $0.key) < ($1.key == "CNY" ? 0 : 1, $1.key) }
            .map { Formatting.money($0.value, currency: $0.key) }
            .joined(separator: " + ")
    }
}
