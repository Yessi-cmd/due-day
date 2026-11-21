import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppClock.self) private var clock
    @Query(sort: \ReminderItem.createdAt) private var items: [ReminderItem]

    @AppStorage(AppSettings.defaultHourKey) private var defaultHour = 9
    @AppStorage(AppSettings.defaultMinuteKey) private var defaultMinute = 0
    @AppStorage(AppSettings.defaultAdvanceKey) private var defaultAdvance = 3
    @AppStorage(AppSettings.timeSensitiveKey) private var timeSensitive = true
    @AppStorage(AppSettings.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    @AppStorage(AppSettings.defaultAlarmKey) private var defaultAlarm = true
    @AppStorage(AppSettings.defaultNagKey) private var defaultNag = true
    @AppStorage(AppSettings.defaultNagIntervalKey) private var defaultNagInterval = 30
    @AppStorage(AppSettings.defaultNagCountKey) private var defaultNagCount = 4

    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var alarmPermission: AlarmSupport.Permission = .unavailable
    @State private var pendingCount = 0
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var showImportChoice = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("通知权限", value: authorizationText)
                    if authorization == .denied {
                        Button("去系统设置开启通知") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else if authorization == .notDetermined {
                        Button("允许通知") {
                            Task {
                                await NotificationScheduler.requestAuthorizationIfNeeded()
                                await refreshStatus()
                            }
                        }
                    }
                    LabeledContent("已安排的通知", value: "\(pendingCount) 条")
                } header: {
                    Text("通知")
                } footer: {
                    Text("系统最多为每个 App 保留 64 条待发通知，App 会自动滚动安排最近的提醒。")
                }

                Section {
                    LabeledContent("闹钟权限", value: alarmPermissionText)
                    if alarmPermission == .notDetermined {
                        Button("允许闹钟响铃") {
                            Task {
                                _ = await AlarmSupport.requestPermission()
                                await refreshStatus()
                                NotificationScheduler.setNeedsReschedule()
                            }
                        }
                    } else if alarmPermission == .denied {
                        Button("去系统设置开启闹钟") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    Toggle("新提醒默认开启闹钟", isOn: $defaultAlarm)
                        .disabled(alarmPermission == .unavailable)
                    Toggle("新提醒默认开启重复提醒", isOn: $defaultNag)
                    if defaultNag {
                        Picker("重复间隔", selection: $defaultNagInterval) {
                            ForEach(AppSettings.nagIntervalOptions, id: \.self) { Text(Formatting.minutes($0)).tag($0) }
                        }
                        Stepper("最多再提醒 \(defaultNagCount) 次", value: $defaultNagCount, in: 1...12)
                    }
                } header: {
                    Text("强提醒")
                } footer: {
                    Text("闹钟在到期当天的提醒时间整屏响铃，静音和专注模式下也会响（iOS 26 起）。重复提醒会在当天持续通知，直到你标记已付。每个提醒也可以单独设置。")
                }

                Section("新建提醒的默认值") {
                    DatePicker("提醒时间", selection: defaultTime, displayedComponents: .hourAndMinute)
                    Picker("提前提醒", selection: $defaultAdvance) {
                        ForEach(AppSettings.advanceOptions.filter { $0 > 0 }, id: \.self) { Text("\($0) 天").tag($0) }
                    }
                    Toggle("到期当天使用「时效性通知」", isOn: $timeSensitive)
                        .onChange(of: timeSensitive) { NotificationScheduler.setNeedsReschedule() }
                }

                Section("日历") {
                    Picker("每周开始于", selection: $weekStartsOnMonday) {
                        Text("周一").tag(true)
                        Text("周日").tag(false)
                    }
                }

                Section {
                    Button("导出备份") { export() }
                        .disabled(items.isEmpty)
                    Button("从备份恢复") { showImporter = true }
                } header: {
                    Text("数据")
                } footer: {
                    Text("备份是一个 JSON 文件，可以存到「文件」App。证书失效或换手机前，记得先导出。")
                }

                Section("关于") {
                    LabeledContent("版本", value: AppInfo.version)
                    LabeledContent("构建号", value: AppInfo.build)
                    if let expiry = AppInfo.signingExpiry {
                        LabeledContent("证书有效期至", value: Formatting.fullDate(expiry))
                    }
                }
            }
            .navigationTitle("设置")
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await refreshStatus() } } }
            .fileExporter(
                isPresented: $showExporter, document: exportDocument, contentType: .json,
                defaultFilename: "续费日历备份-\(clock.today)"
            ) { result in
                if case .failure(let error) = result { message = "导出失败：\(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        pendingImport = try Data(contentsOf: url)
                        showImportChoice = true
                    } catch {
                        message = "读取失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = "读取失败：\(error.localizedDescription)"
                }
            }
            .confirmationDialog("如何恢复备份？", isPresented: $showImportChoice, titleVisibility: .visible) {
                Button("合并（同一提醒以备份为准）") { runImport(replace: false) }
                Button("覆盖（先删除现有全部提醒）", role: .destructive) { runImport(replace: true) }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            }
        }
    }

    private var authorizationText: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: "已开启"
        case .denied: "已关闭"
        case .notDetermined: "未设置"
        @unknown default: "未知"
        }
    }

    private var alarmPermissionText: String {
        switch alarmPermission {
        case .unavailable: "需要 iOS 26"
        case .notDetermined: "未设置"
        case .denied: "已关闭"
        case .authorized: "已开启"
        }
    }

    private var defaultTime: Binding<Date> {
        Binding(
            get: { clock.today.date(in: clock.calendar, hour: defaultHour, minute: defaultMinute) ?? .now },
            set: {
                let c = clock.calendar.dateComponents([.hour, .minute], from: $0)
                defaultHour = c.hour ?? 9
                defaultMinute = c.minute ?? 0
            }
        )
    }

    private func refreshStatus() async {
        authorization = await NotificationScheduler.authorizationStatus()
        alarmPermission = AlarmSupport.permission()
        pendingCount = await NotificationScheduler.pendingIdentifiers().count
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try BackupService.export(items))
            showExporter = true
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func runImport(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            let count = try BackupService.importData(data, replace: replace, context: context)
            message = "已恢复 \(count) 条提醒"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }
}
