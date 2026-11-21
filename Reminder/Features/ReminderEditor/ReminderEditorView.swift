import SwiftData
import SwiftUI

struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppClock.self) private var clock
    let request: EditorRequest
    @State private var draft: ReminderDraft?

    private var isEditing: Bool {
        if case .edit = request { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($draft) {
                    ReminderForm(draft: binding, isEditing: isEditing, today: clock.today, calendar: clock.calendar)
                } else {
                    KindPicker { kind in
                        withAnimation { draft = ReminderDraft(kind: kind, today: clock.today, date: requestedDate) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if let draft {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                            .disabled(!draft.isValid)
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var title: String {
        if isEditing { return "编辑提醒" }
        return draft.map { "新建\($0.kind.title)" } ?? "新建提醒"
    }

    private var requestedDate: CivilDate? {
        if case .new(_, let date) = request { return date }
        return nil
    }

    private func load() {
        guard draft == nil else { return }
        switch request {
        case .edit(let item):
            draft = ReminderDraft(item: item, today: clock.today)
        case .new(let kind?, let date):
            draft = ReminderDraft(kind: kind, today: clock.today, date: date)
        case .new(nil, _):
            break
        }
    }

    private func save() {
        guard let draft, draft.isValid else { return }
        let item: ReminderItem
        if case .edit(let existing) = request {
            item = existing
        } else {
            item = ReminderItem(kind: draft.kind)
            context.insert(item)
        }
        draft.apply(to: item)
        ReminderActions.save(context)
        let wantsAlarm = draft.alarmEnabled
        Task {
            await NotificationScheduler.requestAuthorizationIfNeeded()
            if wantsAlarm && AlarmSupport.permission() == .notDetermined {
                _ = await AlarmSupport.requestPermission()
                NotificationScheduler.setNeedsReschedule()
            }
        }
        dismiss()
    }
}

private struct KindPicker: View {
    let onPick: (ReminderKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("要提醒什么？")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.spacing), GridItem(.flexible())], spacing: Theme.spacing) {
                    ForEach(ReminderKind.allCases) { kind in
                        Button { onPick(kind) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                ReminderIcon(symbol: kind.defaultSymbol, colorIndex: kind.defaultColorIndex, size: 40)
                                Text(kind.title).font(.headline).foregroundStyle(.primary)
                                Text(kind.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                            .cardStyle()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct ReminderForm: View {
    @Binding var draft: ReminderDraft
    let isEditing: Bool
    let today: CivilDate
    let calendar: Calendar

    var body: some View {
        Form {
            Section {
                TextField(draft.kind.titlePlaceholder, text: $draft.title)
                HStack {
                    TextField("金额（可选）", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                    Picker("币种", selection: $draft.currencyCode) {
                        ForEach(ReminderDraft.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if draft.kind == .subscription || draft.kind == .installment {
                    TextField(draft.kind == .installment ? "平台 / 卡片（可选）" : "付款方式（可选）", text: $draft.paymentMethod)
                }
                if draft.kind == .rent {
                    TextField("收款方 / 房东（可选）", text: $draft.payee)
                }
            }

            Section {
                Picker("历法", selection: $draft.calendarKind) {
                    Text("公历").tag(CalendarKind.gregorian)
                    Text("农历").tag(CalendarKind.lunar)
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.calendarKind) { draft.normalizePreset() }

                if draft.calendarKind == .gregorian {
                    DatePicker(draft.kind.dateLabel, selection: civilBinding($draft.startDate), in: dateRange, displayedComponents: .date)
                } else {
                    LunarDateField(title: draft.kind.dateLabel, date: $draft.startDate)
                }

                Picker("重复", selection: $draft.preset) {
                    ForEach(PeriodPreset.options(for: draft.kind, calendar: draft.calendarKind)) { Text($0.title).tag($0) }
                }

                if draft.preset == .custom {
                    Picker("单位", selection: $draft.customFrequency) {
                        if draft.calendarKind == .gregorian {
                            Text("天").tag(RecurrenceRule.Frequency.daily)
                            Text("周").tag(RecurrenceRule.Frequency.weekly)
                        }
                        Text("月").tag(RecurrenceRule.Frequency.monthly)
                        Text("年").tag(RecurrenceRule.Frequency.yearly)
                    }
                    Stepper("每 \(draft.customInterval) \(unitName)", value: $draft.customInterval, in: 1...99)
                }

                if draft.frequency == .monthly {
                    Toggle("固定在每月最后一天", isOn: $draft.lastDayOfMonth)
                }

                if draft.kind == .installment {
                    Stepper("共 \(draft.totalPeriods) 期", value: $draft.totalPeriods, in: 1...360)
                        .onChange(of: draft.totalPeriods) { draft.normalizePreset() }
                    Stepper("此前已还 \(draft.prepaidPeriods) 期", value: $draft.prepaidPeriods, in: 0...max(0, draft.totalPeriods - 1))
                }

                if draft.kind == .custom && draft.frequency != .none {
                    Picker("结束", selection: $draft.endKind) {
                        Text("永不").tag(RecurrenceRule.EndKind.never)
                        Text("截止日期").tag(RecurrenceRule.EndKind.until)
                        Text("重复次数").tag(RecurrenceRule.EndKind.count)
                    }
                    if draft.endKind == .until {
                        DatePicker("截止于", selection: civilBinding($draft.endDate), in: dateRange, displayedComponents: .date)
                    } else if draft.endKind == .count {
                        Stepper("共 \(draft.endCount) 次", value: $draft.endCount, in: 1...999)
                    }
                }
            } header: {
                Text("时间")
            } footer: {
                if draft.calendarKind == .lunar {
                    Text("农历日期没有三十时按廿九提醒；闰月日期在没有该闰月的年份按普通月提醒。")
                } else if draft.frequency == .monthly && !draft.lastDayOfMonth && draft.startDate.day > 28 {
                    Text("没有 \(draft.startDate.day) 日的月份，会在当月最后一天提醒。")
                }
            }

            Section {
                DatePicker("提醒时间", selection: timeBinding, displayedComponents: .hourAndMinute)
                AdvanceChips(selection: $draft.advanceDays)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            } header: {
                Text("提醒")
            } footer: {
                if draft.kind == .rent || draft.kind == .installment || (draft.kind == .subscription && !draft.autoRenew) {
                    Text("到期后仍未标记已付，第二天会再提醒一次。")
                }
            }

            Section {
                Toggle(isOn: $draft.alarmEnabled) {
                    Label("到期当天闹钟响铃", systemImage: "alarm")
                }
                .disabled(!AlarmSupport.isAvailable)
                Toggle(isOn: $draft.nagEnabled.animation()) {
                    Label("没处理就重复提醒", systemImage: "bell.badge")
                }
                if draft.nagEnabled {
                    Picker("间隔", selection: $draft.nagIntervalMinutes) {
                        ForEach(AppSettings.nagIntervalOptions, id: \.self) { Text(Formatting.minutes($0)).tag($0) }
                    }
                    Stepper("最多再提醒 \(draft.nagCount) 次", value: $draft.nagCount, in: 1...12)
                }
            } header: {
                Text("强提醒")
            } footer: {
                Text(strongReminderFooter)
            }

            if draft.kind == .subscription {
                Section {
                    Toggle("自动续费", isOn: $draft.autoRenew)
                    Toggle("有免费试用", isOn: $draft.hasTrialEnd.animation())
                    if draft.hasTrialEnd {
                        DatePicker("试用结束", selection: civilBinding($draft.trialEnd), in: dateRange, displayedComponents: .date)
                    }
                    if isEditing {
                        Toggle("已取消订阅", isOn: $draft.isCancelled)
                    }
                } footer: {
                    Text(draft.autoRenew ? "自动续费的订阅到期后自动进入下一期。" : "关闭自动续费后需要手动标记已付，过期未付会显示逾期。")
                }
            }

            if draft.kind == .rent {
                Section {
                    Toggle("设置合同到期日", isOn: $draft.hasContractEnd.animation())
                    if draft.hasContractEnd {
                        DatePicker("合同到期", selection: civilBinding($draft.contractEnd), in: dateRange, displayedComponents: .date)
                    }
                } footer: {
                    Text("合同到期前 30 天和 7 天会额外提醒。")
                }
            }

            Section("外观") {
                HStack(spacing: 14) {
                    ForEach(Theme.palette.indices, id: \.self) { index in
                        Circle()
                            .fill(Theme.color(index))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if index == draft.colorIndex {
                                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { draft.colorIndex = index }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.vertical, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Theme.symbols, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.body)
                            .frame(width: 38, height: 38)
                            .foregroundStyle(symbol == draft.symbolName ? Color.white : Color.primary)
                            .background(
                                symbol == draft.symbolName ? Theme.color(draft.colorIndex) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .onTapGesture { draft.symbolName = symbol }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("备注") {
                TextField("可选", text: $draft.note, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("接下来") {
                let upcoming = OccurrenceGenerator.first(3, of: draft.rule, start: draft.startDate, from: today)
                if upcoming.isEmpty {
                    Text("没有即将到来的日期").foregroundStyle(.secondary)
                }
                ForEach(upcoming, id: \.self) { occurrence in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Formatting.smartDate(occurrence.date, today: today))
                        Text(previewDetail(occurrence)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var strongReminderFooter: String {
        let time = Formatting.time(hour: draft.hour, minute: draft.minute)
        var lines: [String] = []
        if !AlarmSupport.isAvailable {
            lines.append("闹钟响铃需要 iOS 26。")
        } else if draft.alarmEnabled {
            lines.append("到期当天 \(time) 像闹钟一样整屏响铃，静音和专注模式下也会响。")
        }
        if draft.nagEnabled {
            lines.append("之后每 \(Formatting.minutes(draft.nagIntervalMinutes))再通知一次，最多 \(draft.nagCount) 次；标记\(draft.kind.settleVerb)后立即停止。")
        }
        return lines.joined(separator: "\n")
    }

    private var unitName: String {
        switch draft.customFrequency {
        case .daily: "天"
        case .weekly: "周"
        case .monthly: "个月"
        case .yearly, .none: "年"
        }
    }

    private func previewDetail(_ occurrence: Occurrence) -> String {
        var parts: [String] = []
        if draft.calendarKind == .lunar {
            parts.append("农历" + LunarCalendar.lunarDate(for: occurrence.date).shortDescription)
        }
        if draft.kind == .installment { parts.append("第 \(occurrence.index + 1)/\(draft.totalPeriods) 期") }
        let advance = draft.advanceDays.sorted(by: >).map(Formatting.advance).joined(separator: "、")
        parts.append("\(advance.isEmpty ? "当天" : advance) \(Formatting.time(hour: draft.hour, minute: draft.minute)) 提醒")
        return parts.joined(separator: " · ")
    }

    private var dateRange: ClosedRange<Date> {
        CivilDate.minSupported.date(in: calendar, hour: 12)!...CivilDate.maxSupported.date(in: calendar, hour: 12)!
    }

    private func civilBinding(_ binding: Binding<CivilDate>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue.date(in: calendar, hour: 12) ?? .now },
            set: { binding.wrappedValue = CivilDate($0, in: calendar) }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { today.date(in: calendar, hour: draft.hour, minute: draft.minute) ?? .now },
            set: {
                let c = calendar.dateComponents([.hour, .minute], from: $0)
                draft.hour = c.hour ?? 9
                draft.minute = c.minute ?? 0
            }
        )
    }
}

private struct AdvanceChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("提前提醒").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(AppSettings.advanceOptions, id: \.self) { days in
                    let selected = selection.contains(days)
                    Button {
                        if selected { selection.remove(days) } else { selection.insert(days) }
                    } label: {
                        Text(days == 0 ? "当天" : "\(days) 天前")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? Theme.accent : Color.primary)
                            .background(selected ? Theme.accent.opacity(0.15) : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Lunar date row that expands into year / month (incl. leap) / day wheels.
struct LunarDateField: View {
    let title: String
    @Binding var date: CivilDate
    @State private var expanded = false

    var body: some View {
        let lunar = LunarCalendar.lunarDate(for: date)
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(lunar.lunarYear)年 \(lunar.shortDescription)")
                        .foregroundStyle(expanded ? Theme.accent : Color.primary)
                    Text("公历 \(Formatting.fullDate(date))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if expanded {
            LunarWheelPicker(date: $date)
        }
    }
}

struct LunarWheelPicker: View {
    @Binding var date: CivilDate

    var body: some View {
        let lunar = LunarCalendar.lunarDate(for: date)
        let months = LunarCalendar.months(ofLunarYear: lunar.lunarYear)
        let monthIndex = months.firstIndex { $0.month == lunar.month && $0.isLeapMonth == lunar.isLeapMonth } ?? 0

        HStack(spacing: 0) {
            Picker("年", selection: Binding(get: { lunar.lunarYear }, set: { setYear($0, keeping: lunar) })) {
                ForEach(1901...2099, id: \.self) { Text("\(String($0))年").tag($0) }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("月", selection: Binding(get: { monthIndex }, set: { date = months[$0].date(day: lunar.day) })) {
                ForEach(months.indices, id: \.self) { Text(months[$0].name).tag($0) }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            Picker("日", selection: Binding(get: { lunar.day }, set: { date = months[monthIndex].date(day: $0) })) {
                ForEach(1...months[monthIndex].length, id: \.self) { Text(LunarCalendar.dayName($0)).tag($0) }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .pickerStyle(.wheel)
        .frame(height: 180)
    }

    private func setYear(_ year: Int, keeping lunar: LunarDate) {
        let months = LunarCalendar.months(ofLunarYear: year)
        let target = months.first { $0.month == lunar.month && $0.isLeapMonth == lunar.isLeapMonth }
            ?? months.first { $0.month == lunar.month && !$0.isLeapMonth }
        if let target { date = target.date(day: lunar.day) }
    }
}
