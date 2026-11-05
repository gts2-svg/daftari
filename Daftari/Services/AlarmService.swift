import Foundation
import SwiftUI
import AlarmKit

struct DaftariAlarmData: AlarmMetadata {}

/// Real, full-screen alarms (they ring even in silent mode) for items marked «ضروري».
@MainActor
enum AlarmService {
    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    static var canAsk: Bool {
        AlarmManager.shared.authorizationState == .notDetermined
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch {
            return false
        }
    }

    /// Cancels every alarm we set and schedules one for each open «ضروري» item in the next 30 days.
    static func rebuild(entries: [Entry], now: Date = Date()) async {
        let manager = AlarmManager.shared
        if let existing = try? manager.alarms {
            for alarm in existing { try? manager.cancel(id: alarm.id) }
        }
        guard isAuthorized else { return }
        let horizon = DF.addDays(30, to: now)
        for e in entries where e.isScheduledKind && e.isOpen && e.importance == .urgent {
            guard let anchor = e.anchorDate else { continue }
            let fire = anchor.addingTimeInterval(TimeInterval(-60 * e.alarmLeadMinutes))
            guard fire > now, fire < horizon else { continue }
            let when = e.hasTime ? DF.time(anchor) : DF.relativeDay(anchor, now: now)
            await schedule(id: e.uid, at: fire, title: "\(e.title) · \(when)")
        }
    }

    static func schedule(id: UUID, at date: Date, title: String) async {
        let stop = AlarmButton(text: "تم، شفته", textColor: .white, systemImageName: "checkmark.circle.fill")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop)
        let attributes = AlarmAttributes<DaftariAlarmData>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: T.urgentInk
        )
        let configuration = AlarmManager.AlarmConfiguration<DaftariAlarmData>.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func scheduleTest() async -> Bool {
        if canAsk { await requestAuthorization() }
        guard isAuthorized else { return false }
        await schedule(id: UUID(), at: Date().addingTimeInterval(60), title: "تجربة المنبّه — دفتري")
        return true
    }
}
