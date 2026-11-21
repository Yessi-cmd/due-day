import SwiftData
import SwiftUI

struct CalendarScreen: View {
    @Environment(AppClock.self) private var clock
    @Query(sort: \ReminderItem.createdAt) private var items: [ReminderItem]
    @AppStorage(AppSettings.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    /// First day of the displayed month; nil = current month.
    @State private var month: CivilDate?
    @State private var selected: CivilDate?
    @State private var showMonthPicker = false
    @State private var editor: EditorRequest?

    var body: some View {
        let today = clock.today
        let shownMonth = month ?? today.firstOfMonth
        let selectedDay = selected ?? today
        let days = gridDays(for: shownMonth)
        let infos = DayInfoProvider.infos(from: days.first!, through: days.last!)
        let events = occurrencesByDay(from: days.first!, through: days.last!)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader(shownMonth)

                    VStack(spacing: 6) {
                        weekdayHeader
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                            ForEach(days, id: \.self) { day in
                                DayCell(
                                    info: infos[day]!,
                                    inMonth: day.month == shownMonth.month,
                                    isToday: day == today,
                                    isSelected: day == selectedDay,
                                    dotColors: (events[day] ?? []).map(\.item.colorIndex)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { select(day, shownMonth: shownMonth) }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 24).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < -40 { shift(shownMonth, by: 1) }
                            if value.translation.width > 40 { shift(shownMonth, by: -1) }
                        }
                    )

                    DayDetail(
                        info: infos[selectedDay] ?? DayInfoProvider.info(for: selectedDay),
                        today: today,
                        events: events[selectedDay] ?? [],
                        onAdd: { editor = .new(nil, selectedDay) }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") {
                        withAnimation {
                            month = nil
                            selected = nil
                        }
                    }
                    .disabled(shownMonth == today.firstOfMonth && selectedDay == today)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editor = .new(nil, selectedDay) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("在选中日期新建提醒")
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                MonthPickerSheet(month: shownMonth) { picked in
                    month = picked
                    selected = picked == today.firstOfMonth ? today : picked
                }
                .presentationDetents([.height(320)])
            }
            .sheet(item: $editor) { ReminderEditorView(request: $0) }
            .navigationDestination(for: ReminderItem.self) { ReminderDetailView(item: $0) }
        }
    }

    private func monthHeader(_ shownMonth: CivilDate) -> some View {
        let lunar = LunarCalendar.lunarDate(for: shownMonth.adding(days: 14))
        return HStack(alignment: .center) {
            Button { showMonthPicker = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: "\(shownMonth.year)年\(shownMonth.month)月")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: "\(LunarCalendar.ganzhi(lunar.lunarYear))年 · \(LunarCalendar.zodiac(lunar.lunarYear))年")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择年月")

            Spacer()

            HStack(spacing: 4) {
                Button { shift(shownMonth, by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 40)
                }
                .disabled(shownMonth <= CivilDate.minSupported)
                .accessibilityLabel("上个月")
                Button { shift(shownMonth, by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 40, height: 40)
                }
                .disabled(shownMonth >= CivilDate.maxSupported.firstOfMonth)
                .accessibilityLabel("下个月")
            }
            .font(.body.weight(.semibold))
        }
        .padding(.top, 8)
    }

    private var weekdayHeader: some View {
        let names = weekStartsOnMonday ? ["一", "二", "三", "四", "五", "六", "日"] : ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 2) {
            ForEach(names.indices, id: \.self) { i in
                let isWeekend = weekStartsOnMonday ? i >= 5 : (i == 0 || i == 6)
                Text(names[i])
                    .font(.caption)
                    .foregroundStyle(isWeekend ? Color.secondary.opacity(0.7) : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func gridDays(for first: CivilDate) -> [CivilDate] {
        let firstWeekday = weekStartsOnMonday ? 2 : 1
        let offset = (first.weekday - firstWeekday + 7) % 7
        let start = first.adding(days: -offset)
        return (0..<42).map { start.adding(days: $0) }
    }

    private func occurrencesByDay(from start: CivilDate, through end: CivilDate) -> [CivilDate: [DayEvent]] {
        var result: [CivilDate: [DayEvent]] = [:]
        for item in items {
            let snapshot = item.snapshot(calendar: clock.calendar)
            guard snapshot.isActive else { continue }
            for occurrence in OccurrenceGenerator.occurrences(of: snapshot.rule, start: snapshot.startDate, from: start, through: end) {
                result[occurrence.date, default: []].append(DayEvent(item: item, snapshot: snapshot, occurrence: occurrence))
            }
        }
        return result
    }

    private func select(_ day: CivilDate, shownMonth: CivilDate) {
        withAnimation(.snappy(duration: 0.2)) {
            selected = day
            if day.firstOfMonth != shownMonth { month = day.firstOfMonth }
        }
    }

    private func shift(_ shownMonth: CivilDate, by months: Int) {
        let (y, m) = shownMonth.monthShifted(by: months)
        let target = CivilDate(y, m, 1)
        guard target >= CivilDate.minSupported, target <= CivilDate.maxSupported else { return }
        withAnimation(.snappy(duration: 0.25)) {
            month = target
            selected = target == clock.today.firstOfMonth ? clock.today : target
        }
    }
}

struct DayEvent: Identifiable {
    let item: ReminderItem
    let snapshot: ReminderSnapshot
    let occurrence: Occurrence

    var id: String { "\(snapshot.id)-\(occurrence.date)" }
}

private struct DayCell: View {
    let info: DayInfo
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let dotColors: [Int]

    var body: some View {
        let isWeekend = info.date.weekday == 1 || info.date.weekday == 7
        VStack(spacing: 1) {
            Text(verbatim: "\(info.date.day)")
                .font(.system(.body, design: .rounded).weight(isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : (isWeekend ? Color.secondary : Color.primary))
            Text(info.subtitle)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isToday ? Color.white.opacity(0.9) : (info.isHighlighted ? Theme.accent : Color.secondary))
            HStack(spacing: 3) {
                ForEach(Array(dotColors.prefix(3).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(isToday ? Color.white : Theme.color(color))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .opacity(inMonth ? 1 : 0.35)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityText: String {
        var text = "\(Formatting.fullDate(info.date))，农历\(info.lunar.shortDescription)"
        if let term = info.solarTerm { text += "，\(term)" }
        if !info.festivals.isEmpty { text += "，" + info.festivals.joined(separator: "、") }
        if !dotColors.isEmpty { text += "，\(dotColors.count) 个提醒" }
        return text
    }
}

private struct DayDetail: View {
    let info: DayInfo
    let today: CivilDate
    let events: [DayEvent]
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Formatting.fullDateWeekday(info.date)).font(.headline)
                    Spacer()
                    Text(relative).font(.footnote).foregroundStyle(.secondary)
                }
                Text(info.lunar.fullDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let tags = info.festivals + (info.solarTerm.map { [$0] } ?? [])
                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .foregroundStyle(Theme.accent)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .cardStyle()

            if events.isEmpty {
                Button(action: onAdd) {
                    Label("在这天新建提醒", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        NavigationLink(value: event.item) {
                            HStack(spacing: Theme.spacing) {
                                ReminderIcon(symbol: event.item.symbolName, colorIndex: event.item.colorIndex, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.snapshot.title).foregroundStyle(Color.primary)
                                    if let period = event.snapshot.periodLabel(event.occurrence) {
                                        Text(period).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let amount = event.snapshot.amount {
                                    Text(Formatting.money(amount, currency: event.snapshot.currencyCode))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.primary)
                                }
                                if event.snapshot.isSettled(event.occurrence) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if event.id != events.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
        }
    }

    private var relative: String {
        let days = today.days(until: info.date)
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        case 2...: return "\(days) 天后"
        default: return "\(-days) 天前"
        }
    }
}

private struct MonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var monthNumber: Int
    let onPick: (CivilDate) -> Void

    init(month: CivilDate, onPick: @escaping (CivilDate) -> Void) {
        _year = State(initialValue: month.year)
        _monthNumber = State(initialValue: month.month)
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    ForEach(1901...2099, id: \.self) { Text(verbatim: "\($0)年").tag($0) }
                }
                .frame(maxWidth: .infinity)
                .clipped()
                Picker("月", selection: $monthNumber) {
                    ForEach(1...12, id: \.self) { Text(verbatim: "\($0)月").tag($0) }
                }
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .pickerStyle(.wheel)
            .padding(.horizontal)
            .navigationTitle("跳转到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onPick(CivilDate(year, monthNumber, 1))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
