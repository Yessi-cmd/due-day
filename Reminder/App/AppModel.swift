import Foundation
import Observation
import SwiftData

/// Owns the SwiftData container, shared by views, notification actions and background refresh.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let container: ModelContainer

    private init() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: ReminderMigrationPlan.self
            )
        } catch {
            fatalError("Failed to open data store: \(error)")
        }
    }
}

/// "Today" for the UI; refreshed on day change, time-zone change and foregrounding.
@MainActor
@Observable
final class AppClock {
    private(set) var calendar: Calendar = .autoupdatingCurrent
    private(set) var today: CivilDate = CivilDate(.now, in: .autoupdatingCurrent)

    func refresh() {
        calendar = .autoupdatingCurrent
        let current = CivilDate(.now, in: calendar)
        if current != today { today = current }
    }
}

/// Data mutations that also keep notifications in sync.
@MainActor
enum ReminderActions {
    static func markSettled(_ item: ReminderItem, occurrence: CivilDate, context: ModelContext) {
        guard item.payment(for: occurrence) == nil else { return }
        let record = PaymentRecord(occurrence: occurrence, paidAt: .now, amount: item.amount)
        context.insert(record)
        record.reminder = item
        item.updatedAt = .now
        save(context)
        Task { await NotificationScheduler.removeSnoozes(for: item.id) }
    }

    static func unmarkSettled(_ item: ReminderItem, occurrence: CivilDate, context: ModelContext) {
        guard let record = item.payment(for: occurrence) else { return }
        context.delete(record)
        item.updatedAt = .now
        save(context)
    }

    static func delete(_ item: ReminderItem, context: ModelContext) {
        let id = item.id
        context.delete(item)
        save(context)
        Task { await NotificationScheduler.removeSnoozes(for: id) }
    }

    static func save(_ context: ModelContext) {
        try? context.save()
        NotificationScheduler.setNeedsReschedule()
    }
}
