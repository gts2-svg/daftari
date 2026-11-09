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
            let when = e.hasTime ? DF.time(anchor) : DF.relativeDay(anchor, now: now)
            // One alarm ahead of time (the chosen lead) and one at the time itself,
            // so a «ضروري» item set for soon still rings even when the lead has passed.
            var fires: [(Date, String)] = []
            if e.alarmLeadMinutes > 0 {
                let early = anchor.addingTimeInterval(TimeInterval(-60 * e.alarmLeadMinutes))
                fires.append((early, "\(e.title) · \(when)"))
            }
            fires.append((anchor, "\(e.title) · الآن"))
            if let snooze = e.snoozeUntil {
                fires.append((snooze, "\(e.title) · \(when)"))
            }
            for (fire, title) in fires where fire > now && fire < horizon {
                await schedule(id: UUID(), at: fire, title: title, entry: e.uid)
            }
        }
    }

    /// The alarm screen is drawn by iOS: we set the title, the stop button and one extra button.
    /// Stopping opens دفتري on the «ضروري» screen; «أجّلني 10 د» rings again in ten minutes.
    static func schedule(id: UUID, at date: Date, title: String, entry: UUID?) async {
        let stop = AlarmButton(text: "إيقاف وافتح", textColor: .white, systemImageName: "stop.circle.fill")
        let later = AlarmButton(text: "أجّلني 10 د", textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stop,
            secondaryButton: later,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<DaftariAlarmData>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: T.urgentInk
        )
        let key = entry?.uuidString ?? ""
        let configuration = AlarmManager.AlarmConfiguration<DaftariAlarmData>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: OpenUrgentIntent(entryID: key),
            secondaryIntent: SnoozeUrgentIntent(entryID: key, title: title)
        )
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func scheduleTest() async -> Bool {
        if canAsk { await requestAuthorization() }
        guard isAuthorized else { return false }
        await schedule(id: UUID(), at: Date().addingTimeInterval(60), title: "تجربة المنبّه — دفتري", entry: nil)
        return true
    }
}
