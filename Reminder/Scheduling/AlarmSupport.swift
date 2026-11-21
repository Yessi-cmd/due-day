import Foundation
import SwiftUI
#if canImport(AlarmKit)
@preconcurrency import AlarmKit
#endif

/// Thin, availability-safe wrapper around AlarmKit (iOS 26+). Everything else in the app talks
/// to this type only, so the iOS 17 deployment target keeps compiling and running.
///
/// Deliberately nonisolated: AlarmManager isn't Sendable, so it's only touched off the main actor
/// and only Sendable values (PlannedAlarm, Permission) cross in or out.
enum AlarmSupport {
    enum Permission: Sendable {
        case unavailable, notDetermined, denied, authorized
    }

    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func permission() -> Permission {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return map(AlarmManager.shared.authorizationState) }
        #endif
        return .unavailable
    }

    static func requestPermission() async -> Permission {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            guard manager.authorizationState == .notDetermined else { return map(manager.authorizationState) }
            if let state = try? await manager.requestAuthorization() { return map(state) }
            return map(manager.authorizationState)
        }
        #endif
        return .unavailable
    }

    /// Replaces all of this app's alarms with `planned`.
    static func sync(_ planned: [PlannedAlarm]) async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            await AlarmKitScheduler.sync(planned)
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func map(_ state: AlarmManager.AuthorizationState) -> Permission {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
    #endif
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct DueAlarmMetadata: AlarmMetadata {
    var reminderID: String
    var occurrence: String
}

@available(iOS 26.0, *)
private enum AlarmKitScheduler {
    static func sync(_ planned: [PlannedAlarm]) async {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return }

        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }

        for item in planned {
            let attributes = AlarmAttributes<DueAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert(title: item.title)),
                metadata: DueAlarmMetadata(reminderID: item.reminderID.uuidString, occurrence: item.occurrence.description),
                tintColor: Theme.accent
            )
            let configuration = AlarmManager.AlarmConfiguration<DueAlarmMetadata>.alarm(
                schedule: .fixed(item.fireDate),
                attributes: attributes
            )
            do {
                _ = try await manager.schedule(id: UUID(), configuration: configuration)
            } catch {
                break // most likely maximumLimitReached; the earliest alarms are already in
            }
        }
    }

    private static func alert(title: String) -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: LocalizedStringResource("\(title)"))
        }
        return AlarmPresentation.Alert(
            title: LocalizedStringResource("\(title)"),
            stopButton: AlarmButton(text: "知道了", textColor: .white, systemImageName: "checkmark")
        )
    }
}
#endif
