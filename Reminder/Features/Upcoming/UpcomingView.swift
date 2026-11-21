import SwiftData
import SwiftUI
import UIKit

/// What the editor sheet should open with.
enum EditorRequest: Identifiable {
    case new(ReminderKind?, CivilDate?)
    case edit(ReminderItem)

    var id: String {
        switch self {
        case .new(let kind, let date): "new-\(kind?.rawValue ?? "")-\(date?.description ?? "")"
        case .edit(let item): "edit-\(item.id)"
        }
    }
}

/// A reminder with its computed status for today.
struct ReminderEntry: Identifiable {
    let item: ReminderItem
    let snapshot: ReminderSnapshot
    let status: ReminderStatus

    var id: UUID { snapshot.id }

    init(item: ReminderItem, calendar: Calendar, today: CivilDate) {
        self.item = item
        self.snapshot = item.snapshot(calendar: calendar)
        self.status = snapshot.status(today: today)
    }
}

struct UpcomingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppClock.self) private var clock
    @Query(sort: \ReminderItem.createdAt) private var items: [ReminderItem]
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: EditorRequest?
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .task(id: scenePhase) {
                notificationsDenied = await NotificationScheduler.authorizationStatus() == .denied
            }
            .navigationTitle("即将到期")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = .new(nil, nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建提醒")
                }
            }
            .sheet(item: $editor) { ReminderEditorView(request: $0) }
            .navigationDestination(for: ReminderItem.self) { ReminderDetailView(item: $0) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有提醒", systemImage: "bell")
        } description: {
            Text("订阅续费、分期还款、房租……\n加进来，到期前会提醒你。")
        } actions: {
            Button("新建提醒") { editor = .new(nil, nil) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        let today = clock.today
        let entries = items.map { ReminderEntry(item: $0, calendar: clock.calendar, today: today) }
        let active = entries.filter { $0.snapshot.isActive && !$0.status.isFinished }
            .sorted { ($0.status.daysUntilDue ?? 0, $0.snapshot.title) < ($1.status.daysUntilDue ?? 0, $1.snapshot.title) }
        let groups = [
            EntryGroup(title: "已逾期", entries: active.filter { ($0.status.daysUntilDue ?? 0) < 0 }),
            EntryGroup(title: "今天", entries: active.filter { $0.status.daysUntilDue == 0 }),
            EntryGroup(title: "7 天内", entries: active.filter { (1...7).contains($0.status.daysUntilDue ?? -1) }),
            EntryGroup(title: "30 天内", entries: active.filter { (8...30).contains($0.status.daysUntilDue ?? -1) }),
            EntryGroup(title: "以后", entries: active.filter { ($0.status.daysUntilDue ?? -1) > 30 }),
            EntryGroup(title: "已结束", entries: entries.filter { $0.snapshot.isActive && $0.status.isFinished }),
            EntryGroup(title: "已停用", entries: entries.filter { !$0.snapshot.isActive }),
        ].filter { !$0.entries.isEmpty }

        return List {
            if notificationsDenied {
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("通知已关闭，到期不会提醒你。点此去设置开启。", systemImage: "bell.slash")
                            .font(.subheadline)
                            .foregroundStyle(Theme.overdue)
                    }
                }
            }
            if let expiry = AppInfo.signingExpiry, today.days(until: expiry) <= 30 {
                Section {
                    Label("签名证书将于 \(Formatting.fullDate(expiry)) 到期，到期后 App 无法打开。请先在设置里导出备份。", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.soon)
                }
            }
            Section {
                SummaryCard(entries: entries, today: today, calendar: clock.calendar)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        NavigationLink(value: entry.item) {
                            ReminderRow(entry: entry, today: today)
                        }
                        .swipeActions(edge: .trailing) {
                            if let due = entry.status.due, entry.snapshot.isActive {
                                Button(entry.snapshot.kind.settleVerb) {
                                    withAnimation { ReminderActions.markSettled(entry.item, occurrence: due.date, context: context) }
                                }
                                .tint(Theme.accent)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("编辑") { editor = .edit(entry.item) }
                                .tint(.gray)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct EntryGroup: Identifiable {
    let title: String
    let entries: [ReminderEntry]
    var id: String { title }
}

struct ReminderRow: View {
    let entry: ReminderEntry
    let today: CivilDate

    var body: some View {
        HStack(spacing: Theme.spacing) {
            ReminderIcon(symbol: entry.item.symbolName, colorIndex: entry.item.colorIndex)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.snapshot.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let amount = entry.snapshot.amount {
                    Text(Formatting.money(amount, currency: entry.snapshot.currencyCode))
                        .font(.body.monospacedDigit())
                }
                trailingStatus
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var trailingStatus: some View {
        if !entry.snapshot.isActive {
            Text(entry.snapshot.isArchived ? "已归档" : "已取消").font(.footnote).foregroundStyle(.secondary)
        } else if let days = entry.status.daysUntilDue {
            DueBadge(days: days)
        } else {
            Text(entry.snapshot.kind == .installment ? "已结清" : "已结束").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        guard let due = entry.status.due else { return entry.snapshot.rule.summary(start: entry.snapshot.startDate) }
        var parts = [Formatting.smartDate(due.date, today: today)]
        if entry.snapshot.rule.calendar == .lunar {
            parts.append("农历" + LunarCalendar.lunarDate(for: due.date).shortDescription)
        }
        if let period = entry.snapshot.periodLabel(due) { parts.append(period) }
        if entry.status.overdueCount > 1 { parts.append("共 \(entry.status.overdueCount) 期未付") }
        return parts.joined(separator: " · ")
    }
}

struct SummaryCard: View {
    let entries: [ReminderEntry]
    let today: CivilDate
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metric("本月待付", toPay.formatted)
            Divider().frame(height: 36)
            metric("本月已付", paid.formatted)
            Divider().frame(height: 36)
            metric("订阅月均", subscriptions.formatted)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
    }

    private var toPay: MoneyTotal {
        var total = MoneyTotal()
        for entry in entries where entry.snapshot.isActive {
            for _ in entry.snapshot.unsettledOccurrences(today: today, through: today.lastOfMonth) {
                total.add(entry.snapshot.amount, currency: entry.snapshot.currencyCode)
            }
        }
        return total
    }

    private var paid: MoneyTotal {
        var total = MoneyTotal()
        for entry in entries {
            for record in entry.item.payments ?? [] {
                let day = CivilDate(record.paidAt, in: calendar)
                if day.year == today.year && day.month == today.month {
                    total.add(record.amount, currency: entry.snapshot.currencyCode)
                }
            }
        }
        return total
    }

    private var subscriptions: MoneyTotal {
        var total = MoneyTotal()
        for entry in entries where entry.snapshot.isActive && entry.snapshot.kind == .subscription {
            total.add(entry.snapshot.monthlyCost, currency: entry.snapshot.currencyCode)
        }
        return total
    }
}
