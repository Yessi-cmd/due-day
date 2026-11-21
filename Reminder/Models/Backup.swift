import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Versioned JSON backup (AGENTS.md §10). Every field except id/title is optional so older or
/// newer files still import; unknown keys are ignored by JSONDecoder.
struct BackupFile: Codable, Sendable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var reminders: [ReminderDTO]

    struct ReminderDTO: Codable, Sendable, Equatable {
        var id: UUID
        var title: String
        var kind: String?
        var amount: String?
        var currencyCode: String?
        var startDate: CivilDate?
        var rule: RecurrenceRule?
        var reminderHour: Int?
        var reminderMinute: Int?
        var advanceDays: [Int]?
        var colorIndex: Int?
        var symbolName: String?
        var note: String?
        var autoRenew: Bool?
        var isCancelled: Bool?
        var isArchived: Bool?
        var prepaidPeriods: Int?
        var paymentMethod: String?
        var payee: String?
        var trialEnd: CivilDate?
        var contractEnd: CivilDate?
        var createdAt: Date?
        var updatedAt: Date?
        var alarmEnabled: Bool?
        var nagEnabled: Bool?
        var nagIntervalMinutes: Int?
        var nagCount: Int?
        var payments: [PaymentDTO]?
    }

    struct PaymentDTO: Codable, Sendable, Equatable {
        var id: UUID?
        var occurrence: CivilDate
        var paidAt: Date?
        var amount: String?
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): "这个备份来自更新版本的 App（格式 v\(v)），请先更新 App。"
        }
    }
}

@MainActor
enum BackupService {
    static func export(_ items: [ReminderItem]) throws -> Data {
        let file = BackupFile(version: BackupFile.currentVersion, exportedAt: .now, reminders: items.map(dto))
        return try BackupFile.encoder().encode(file)
    }

    /// Returns the number of reminders imported. `replace` deletes everything first;
    /// otherwise reminders with the same id are overwritten and others are added.
    @discardableResult
    static func importData(_ data: Data, replace: Bool, context: ModelContext) throws -> Int {
        let file = try BackupFile.decoder().decode(BackupFile.self, from: data)
        guard file.version <= BackupFile.currentVersion else { throw BackupError.unsupportedVersion(file.version) }

        var byID: [UUID: ReminderItem] = [:]
        for item in try context.fetch(FetchDescriptor<ReminderItem>()) {
            if replace { context.delete(item) } else { byID[item.id] = item }
        }
        if replace { try context.save() }

        for dto in file.reminders {
            let item: ReminderItem
            if let existing = byID[dto.id] {
                for record in existing.payments ?? [] { context.delete(record) }
                item = existing
            } else {
                item = ReminderItem(kind: .custom)
                item.id = dto.id
                context.insert(item)
            }
            apply(dto, to: item, context: context)
        }
        ReminderActions.save(context)
        return file.reminders.count
    }

    static func dto(_ item: ReminderItem) -> BackupFile.ReminderDTO {
        BackupFile.ReminderDTO(
            id: item.id, title: item.title, kind: item.kindRaw, amount: item.amountRaw,
            currencyCode: item.currencyCode, startDate: item.startDate, rule: item.rule,
            reminderHour: item.reminderHour, reminderMinute: item.reminderMinute, advanceDays: item.advanceDays,
            colorIndex: item.colorIndex, symbolName: item.symbolName, note: item.note,
            autoRenew: item.autoRenew, isCancelled: item.isCancelled, isArchived: item.isArchived,
            prepaidPeriods: item.prepaidPeriods, paymentMethod: item.paymentMethod, payee: item.payee,
            trialEnd: item.trialEnd, contractEnd: item.contractEnd,
            createdAt: item.createdAt, updatedAt: item.updatedAt,
            alarmEnabled: item.alarmEnabled, nagEnabled: item.nagEnabled,
            nagIntervalMinutes: item.nagIntervalMinutes, nagCount: item.nagCount,
            payments: (item.payments ?? []).compactMap { record in
                record.occurrence.map {
                    BackupFile.PaymentDTO(id: record.id, occurrence: $0, paidAt: record.paidAt, amount: record.amountRaw)
                }
            }
        )
    }

    private static func apply(_ dto: BackupFile.ReminderDTO, to item: ReminderItem, context: ModelContext) {
        let kind = dto.kind.flatMap(ReminderKind.init(rawValue:)) ?? .custom
        item.kind = kind
        item.title = dto.title
        item.amountRaw = dto.amount
        item.currencyCode = dto.currencyCode ?? "CNY"
        if let date = dto.startDate { item.startDate = date }
        item.rule = dto.rule ?? .once
        item.reminderHour = dto.reminderHour ?? 9
        item.reminderMinute = dto.reminderMinute ?? 0
        item.advanceDays = dto.advanceDays ?? [3, 0]
        item.colorIndex = dto.colorIndex ?? kind.defaultColorIndex
        item.symbolName = dto.symbolName ?? kind.defaultSymbol
        item.note = dto.note ?? ""
        item.autoRenew = dto.autoRenew ?? true
        item.isCancelled = dto.isCancelled ?? false
        item.isArchived = dto.isArchived ?? false
        item.prepaidPeriods = dto.prepaidPeriods ?? 0
        item.paymentMethod = dto.paymentMethod ?? ""
        item.payee = dto.payee ?? ""
        item.trialEnd = dto.trialEnd
        item.contractEnd = dto.contractEnd
        item.createdAt = dto.createdAt ?? .now
        item.updatedAt = dto.updatedAt ?? .now
        item.alarmEnabled = dto.alarmEnabled ?? true
        item.nagEnabled = dto.nagEnabled ?? true
        item.nagIntervalMinutes = dto.nagIntervalMinutes ?? 30
        item.nagCount = dto.nagCount ?? 4
        for payment in dto.payments ?? [] {
            let record = PaymentRecord(occurrence: payment.occurrence, paidAt: payment.paidAt ?? .now, amount: nil)
            record.amountRaw = payment.amount
            if let id = payment.id { record.id = id }
            context.insert(record)
            record.reminder = item
        }
    }
}

/// Wraps backup JSON for `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
