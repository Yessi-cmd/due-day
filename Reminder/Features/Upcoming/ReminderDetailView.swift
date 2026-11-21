import SwiftData
import SwiftUI

struct ReminderDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppClock.self) private var clock
    let item: ReminderItem
    @State private var editor: EditorRequest?
    @State private var confirmDelete = false
    @State private var isDeleting = false

    var body: some View {
        if isDeleting {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        let today = clock.today
        let snapshot = item.snapshot(calendar: clock.calendar)
        let status = snapshot.status(today: today)

        return List {
            Section {
                header(snapshot: snapshot, status: status)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("日期") {
                ForEach(upcoming(snapshot: snapshot, today: today), id: \.self) { occurrence in
                    occurrenceRow(occurrence, snapshot: snapshot, today: today)
                }
            }

            Section("设置") {
                LabeledContent("类型", value: snapshot.kind.title)
                LabeledContent("重复", value: snapshot.rule.summary(start: snapshot.startDate))
                LabeledContent("提醒", value: reminderSummary)
                if !item.paymentMethod.isEmpty { LabeledContent(snapshot.kind == .installment ? "平台" : "付款方式", value: item.paymentMethod) }
                if !item.payee.isEmpty { LabeledContent("收款方", value: item.payee) }
                if snapshot.kind == .subscription { LabeledContent("自动续费", value: item.autoRenew ? "是" : "否") }
                if let end = item.trialEnd { LabeledContent("试用结束", value: Formatting.fullDate(end)) }
                if let end = item.contractEnd { LabeledContent("合同到期", value: Formatting.fullDate(end)) }
                if snapshot.kind == .installment, item.prepaidPeriods > 0 { LabeledContent("此前已还", value: "\(item.prepaidPeriods) 期") }
                if !item.note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注").foregroundStyle(.secondary).font(.footnote)
                        Text(item.note)
                    }
                }
            }

            if !item.paymentList.isEmpty {
                Section("\(snapshot.kind.settleVerb)记录") {
                    ForEach(item.paymentList) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.occurrence.map { Formatting.fullDate($0) } ?? "—")
                                Text("\(snapshot.kind.settleVerb)于 \(record.paidAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let amount = record.amount {
                                Text(Formatting.money(amount, currency: snapshot.currencyCode)).monospacedDigit()
                            }
                        }
                        .swipeActions {
                            Button("撤销", role: .destructive) {
                                if let occurrence = record.occurrence {
                                    ReminderActions.unmarkSettled(item, occurrence: occurrence, context: context)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                if snapshot.kind == .subscription {
                    Button(item.isCancelled ? "恢复订阅" : "标记为已取消订阅") {
                        item.isCancelled.toggle()
                        ReminderActions.save(context)
                    }
                }
                Button(item.isArchived ? "取消归档" : "归档（停止提醒）") {
                    item.isArchived.toggle()
                    ReminderActions.save(context)
                }
                Button("删除", role: .destructive) { confirmDelete = true }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("编辑") { editor = .edit(item) }
        }
        .sheet(item: $editor) { ReminderEditorView(request: $0) }
        .confirmationDialog("删除「\(item.title)」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { delete() }
        } message: {
            Text("提醒和所有记录都会被删除，无法恢复。")
        }
    }

    private func header(snapshot: ReminderSnapshot, status: ReminderStatus) -> some View {
        VStack(spacing: 10) {
            ReminderIcon(symbol: item.symbolName, colorIndex: item.colorIndex, size: 56)
            Text(snapshot.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            if let amount = snapshot.amount {
                Text(Formatting.money(amount, currency: snapshot.currencyCode))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let due = status.due, snapshot.isActive {
                HStack(spacing: 6) {
                    Text(Formatting.smartDate(due.date, today: clock.today))
                    if let period = snapshot.periodLabel(due) { Text("· " + period) }
                    Text("·")
                    DueBadge(days: status.daysUntilDue ?? 0)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button {
                    withAnimation { ReminderActions.markSettled(item, occurrence: due.date, context: context) }
                } label: {
                    Text(snapshot.kind == .custom ? "标记完成" : "标记已付")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            } else if !snapshot.isActive {
                Text(item.isArchived ? "已归档" : "已取消订阅").foregroundStyle(.secondary)
            } else {
                Text(snapshot.kind == .installment ? "已全部结清 🎉" : "没有后续日期了").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Overdue unsettled occurrences plus the next few from today.
    private func upcoming(snapshot: ReminderSnapshot, today: CivilDate) -> [Occurrence] {
        let overdue = snapshot.unsettledOccurrences(today: today, through: today.adding(days: -1))
        let next = OccurrenceGenerator.first(6, of: snapshot.rule, start: snapshot.startDate, from: today)
        return overdue + next
    }

    private func occurrenceRow(_ occurrence: Occurrence, snapshot: ReminderSnapshot, today: CivilDate) -> some View {
        let settled = snapshot.isSettled(occurrence)
        let prepaid = snapshot.kind == .installment && occurrence.index < snapshot.prepaidPeriods
        return HStack(spacing: Theme.spacing) {
            Button {
                guard !prepaid else { return }
                withAnimation {
                    if settled {
                        ReminderActions.unmarkSettled(item, occurrence: occurrence.date, context: context)
                    } else {
                        ReminderActions.markSettled(item, occurrence: occurrence.date, context: context)
                    }
                }
            } label: {
                Image(systemName: settled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(settled ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(settled ? "撤销\(snapshot.kind.settleVerb)" : "标记\(snapshot.kind.settleVerb)")

            VStack(alignment: .leading, spacing: 2) {
                Text(Formatting.smartDate(occurrence.date, today: today))
                    .strikethrough(settled, color: .secondary)
                let detail = [
                    snapshot.rule.calendar == .lunar ? "农历" + LunarCalendar.lunarDate(for: occurrence.date).shortDescription : nil,
                    snapshot.periodLabel(occurrence),
                ].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !settled {
                DueBadge(days: today.days(until: occurrence.date))
            }
        }
    }

    private var reminderSummary: String {
        let days = item.advanceDays.sorted(by: >).map(Formatting.advance).joined(separator: "、")
        return "\(days.isEmpty ? "当天" : days) \(Formatting.time(hour: item.reminderHour, minute: item.reminderMinute))"
    }

    private func delete() {
        isDeleting = true
        dismiss()
        let item = item
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            ReminderActions.delete(item, context: context)
        }
    }
}
