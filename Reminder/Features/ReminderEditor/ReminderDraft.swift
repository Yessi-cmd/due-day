import Foundation

/// Repeat options shown in the editor; each maps to a RecurrenceRule frequency + interval.
enum PeriodPreset: String, CaseIterable, Identifiable, Hashable {
    case once, daily, weekly, monthly, quarterly, halfYearly, yearly, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "不重复"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .quarterly: "每季度"
        case .halfYearly: "每半年"
        case .yearly: "每年"
        case .custom: "自定义"
        }
    }

    var fixed: (RecurrenceRule.Frequency, Int)? {
        switch self {
        case .once: (.none, 1)
        case .daily: (.daily, 1)
        case .weekly: (.weekly, 1)
        case .monthly: (.monthly, 1)
        case .quarterly: (.monthly, 3)
        case .halfYearly: (.monthly, 6)
        case .yearly: (.yearly, 1)
        case .custom: nil
        }
    }

    static func options(for kind: ReminderKind, calendar: CalendarKind) -> [PeriodPreset] {
        if calendar == .lunar { return [.once, .monthly, .yearly, .custom] }
        switch kind {
        case .subscription: return [.monthly, .quarterly, .halfYearly, .yearly, .weekly, .custom]
        case .installment: return [.monthly, .custom]
        case .rent: return [.monthly, .quarterly, .halfYearly, .yearly, .custom]
        case .custom: return [.once, .daily, .weekly, .monthly, .yearly, .custom]
        }
    }

    static func from(_ rule: RecurrenceRule) -> PeriodPreset {
        switch (rule.frequency, rule.interval) {
        case (.none, _): .once
        case (.daily, 1): .daily
        case (.weekly, 1): .weekly
        case (.monthly, 1): .monthly
        case (.monthly, 3): .quarterly
        case (.monthly, 6): .halfYearly
        case (.yearly, 1): .yearly
        default: .custom
        }
    }
}

/// Editable copy of a reminder; written back to the model only on save.
struct ReminderDraft {
    var kind: ReminderKind
    var title = ""
    var amountText = ""
    var currencyCode = "CNY"
    var calendarKind: CalendarKind = .gregorian
    var startDate: CivilDate
    var preset: PeriodPreset
    var customFrequency: RecurrenceRule.Frequency = .monthly
    var customInterval = 2
    var lastDayOfMonth = false
    var endKind: RecurrenceRule.EndKind = .never
    var endDate: CivilDate
    var endCount = 10
    var totalPeriods = 12
    var prepaidPeriods = 0
    var hour: Int
    var minute: Int
    var advanceDays: Set<Int>
    var autoRenew = true
    var isCancelled = false
    var paymentMethod = ""
    var payee = ""
    var hasTrialEnd = false
    var trialEnd: CivilDate
    var hasContractEnd = false
    var contractEnd: CivilDate
    var note = ""
    var colorIndex: Int
    var symbolName: String
    var alarmEnabled: Bool
    var nagEnabled: Bool
    var nagIntervalMinutes: Int
    var nagCount: Int

    static let currencies = ["CNY", "USD", "HKD", "EUR", "JPY", "GBP"]

    init(kind: ReminderKind, today: CivilDate, date: CivilDate?) {
        self.kind = kind
        self.startDate = date ?? today
        self.preset = PeriodPreset.options(for: kind, calendar: .gregorian).first ?? .monthly
        self.endDate = today.adding(days: 365)
        self.hour = AppSettings.defaultHour
        self.minute = AppSettings.defaultMinute
        self.advanceDays = Set([AppSettings.defaultAdvance, 0])
        self.trialEnd = today.adding(days: 7)
        self.contractEnd = today.adding(days: 365)
        self.colorIndex = kind.defaultColorIndex
        self.symbolName = kind.defaultSymbol
        self.alarmEnabled = AppSettings.defaultAlarm
        self.nagEnabled = AppSettings.defaultNag
        self.nagIntervalMinutes = AppSettings.defaultNagInterval
        self.nagCount = AppSettings.defaultNagCount
    }

    init(item: ReminderItem, today: CivilDate) {
        let rule = item.rule
        self.init(kind: item.kind, today: today, date: item.startDate)
        title = item.title
        amountText = item.amount.map { "\($0)" } ?? ""
        currencyCode = item.currencyCode
        calendarKind = rule.calendar
        preset = PeriodPreset.from(rule)
        if preset == .custom {
            customFrequency = rule.frequency
            customInterval = rule.interval
        }
        lastDayOfMonth = rule.monthlyMode == .lastDay
        endKind = rule.endKind
        if let date = rule.endDate { endDate = date }
        if let count = rule.endCount { endCount = count; totalPeriods = count }
        prepaidPeriods = item.prepaidPeriods
        hour = item.reminderHour
        minute = item.reminderMinute
        advanceDays = Set(item.advanceDays)
        autoRenew = item.autoRenew
        isCancelled = item.isCancelled
        paymentMethod = item.paymentMethod
        payee = item.payee
        if let end = item.trialEnd { hasTrialEnd = true; trialEnd = end }
        if let end = item.contractEnd { hasContractEnd = true; contractEnd = end }
        note = item.note
        colorIndex = item.colorIndex
        symbolName = item.symbolName
        alarmEnabled = item.alarmEnabled
        nagEnabled = item.nagEnabled
        nagIntervalMinutes = item.nagIntervalMinutes
        nagCount = item.nagCount
    }

    var frequency: RecurrenceRule.Frequency { preset.fixed?.0 ?? customFrequency }

    var rule: RecurrenceRule {
        var rule = RecurrenceRule()
        rule.calendar = calendarKind
        rule.frequency = frequency
        rule.interval = preset.fixed?.1 ?? max(1, customInterval)
        rule.monthlyMode = frequency == .monthly && lastDayOfMonth ? .lastDay : .dayOfMonth
        if kind == .installment {
            rule.endKind = .count
            rule.endCount = max(1, totalPeriods)
        } else if kind == .custom && frequency != .none {
            rule.endKind = endKind
            rule.endDate = endKind == .until ? endDate : nil
            rule.endCount = endKind == .count ? max(1, endCount) : nil
        }
        return rule
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var amount: Decimal? { Formatting.parseAmount(amountText) }

    var isValid: Bool {
        !trimmedTitle.isEmpty && (amountText.trimmingCharacters(in: .whitespaces).isEmpty || amount != nil)
    }

    /// Keeps the repeat option valid after switching between Gregorian and lunar.
    mutating func normalizePreset() {
        if !PeriodPreset.options(for: kind, calendar: calendarKind).contains(preset) {
            preset = calendarKind == .lunar ? .yearly : (PeriodPreset.options(for: kind, calendar: calendarKind).first ?? .monthly)
        }
        if calendarKind == .lunar && customFrequency != .monthly && customFrequency != .yearly {
            customFrequency = .monthly
        }
        prepaidPeriods = min(prepaidPeriods, max(0, totalPeriods - 1))
    }

    func apply(to item: ReminderItem) {
        item.kind = kind
        item.title = trimmedTitle
        item.amount = amount
        item.currencyCode = currencyCode
        item.startDate = startDate
        item.rule = rule
        item.reminderHour = hour
        item.reminderMinute = minute
        item.advanceDays = advanceDays.sorted(by: >)
        item.autoRenew = kind == .subscription ? autoRenew : true
        item.isCancelled = kind == .subscription && isCancelled
        item.prepaidPeriods = kind == .installment ? prepaidPeriods : 0
        item.paymentMethod = paymentMethod.trimmingCharacters(in: .whitespaces)
        item.payee = payee.trimmingCharacters(in: .whitespaces)
        item.trialEnd = kind == .subscription && hasTrialEnd ? trialEnd : nil
        item.contractEnd = kind == .rent && hasContractEnd ? contractEnd : nil
        item.note = note
        item.colorIndex = colorIndex
        item.symbolName = symbolName
        item.alarmEnabled = alarmEnabled
        item.nagEnabled = nagEnabled
        item.nagIntervalMinutes = nagIntervalMinutes
        item.nagCount = nagCount
        item.updatedAt = .now
    }
}
