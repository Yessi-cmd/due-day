import Foundation
import SwiftData

/// Schema v1. Every model change needs a new VersionedSchema plus a migration stage
/// (AGENTS.md §10) — never edit these classes in a way that drops existing data.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [ReminderItem.self, PaymentRecord.self]
    }

    @Model
    final class ReminderItem {
        @Attribute(.unique) var id: UUID = UUID()
        var kindRaw: String = ReminderKind.custom.rawValue
        var title: String = ""
        /// Decimal stored as a POSIX string ("39.9") — never Double for money.
        var amountRaw: String?
        var currencyCode: String = "CNY"
        /// yyyy-MM-dd, floating (no time zone).
        var startDateRaw: String = "2000-01-01"
        /// JSON-encoded RecurrenceRule.
        var ruleData: Data = Data()
        var reminderHour: Int = 9
        var reminderMinute: Int = 0
        var advanceDays: [Int] = [3, 0]
        var colorIndex: Int = 0
        var symbolName: String = "bell"
        var note: String = ""
        var autoRenew: Bool = true
        var isCancelled: Bool = false
        var isArchived: Bool = false
        /// Installments already paid before the reminder was created.
        var prepaidPeriods: Int = 0
        var paymentMethod: String = ""
        var payee: String = ""
        var trialEndRaw: String?
        var contractEndRaw: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \PaymentRecord.reminder)
        var payments: [PaymentRecord]? = []

        init(kind: ReminderKind) {
            self.id = UUID()
            self.kindRaw = kind.rawValue
            self.symbolName = kind.defaultSymbol
            self.colorIndex = kind.defaultColorIndex
        }
    }

    @Model
    final class PaymentRecord {
        var id: UUID = UUID()
        /// The occurrence this settles, yyyy-MM-dd.
        var occurrenceRaw: String = ""
        var paidAt: Date = Date()
        var amountRaw: String?
        var reminder: ReminderItem?

        init(occurrence: CivilDate, paidAt: Date, amount: Decimal?) {
            self.id = UUID()
            self.occurrenceRaw = occurrence.description
            self.paidAt = paidAt
            self.amountRaw = amount.map { "\($0)" }
        }
    }
}

enum ReminderMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias ReminderItem = SchemaV1.ReminderItem
typealias PaymentRecord = SchemaV1.PaymentRecord

// MARK: - Typed accessors

extension SchemaV1.ReminderItem {
    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var amount: Decimal? {
        get { amountRaw.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
        set { amountRaw = newValue.map { "\($0)" } }
    }

    var startDate: CivilDate {
        get { CivilDate(string: startDateRaw) ?? CivilDate(2000, 1, 1) }
        set { startDateRaw = newValue.description }
    }

    var rule: RecurrenceRule {
        get { (try? JSONDecoder().decode(RecurrenceRule.self, from: ruleData)) ?? .once }
        set { ruleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var trialEnd: CivilDate? {
        get { trialEndRaw.flatMap(CivilDate.init(string:)) }
        set { trialEndRaw = newValue?.description }
    }

    var contractEnd: CivilDate? {
        get { contractEndRaw.flatMap(CivilDate.init(string:)) }
        set { contractEndRaw = newValue?.description }
    }

    var paymentList: [PaymentRecord] {
        (payments ?? []).sorted { $0.paidAt > $1.paidAt }
    }

    func payment(for occurrence: CivilDate) -> PaymentRecord? {
        (payments ?? []).first { $0.occurrenceRaw == occurrence.description }
    }

    func snapshot(calendar: Calendar) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id, kind: kind, title: title, amount: amount, currencyCode: currencyCode,
            startDate: startDate, rule: rule,
            reminderHour: reminderHour, reminderMinute: reminderMinute, advanceDays: advanceDays,
            createdDay: CivilDate(createdAt, in: calendar),
            prepaidPeriods: prepaidPeriods, autoRenew: autoRenew,
            isCancelled: isCancelled, isArchived: isArchived,
            trialEnd: trialEnd, contractEnd: contractEnd,
            paidDates: Set((payments ?? []).compactMap { CivilDate(string: $0.occurrenceRaw) })
        )
    }
}

extension SchemaV1.PaymentRecord {
    var occurrence: CivilDate? { CivilDate(string: occurrenceRaw) }

    var amount: Decimal? {
        amountRaw.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }
}
