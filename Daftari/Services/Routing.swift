import Foundation
import SwiftUI
import UserNotifications

enum VoiceMode: Equatable {
    case idea
    case journal
}

enum Route: Identifiable, Equatable {
    case add(prefill: String, date: Date?, kind: EntryKind?)
    case edit(UUID)
    case convert(UUID)
    case voice(VoiceMode)
    case evening
    case morning
    case settings
    case medicine(UUID?)
    case urgent(UUID)

    var id: String {
        switch self {
        case .medicine(let u): return "med-\(u?.uuidString ?? "new")"
        case .add: return "add"
        case .edit(let u): return "edit-\(u.uuidString)"
        case .convert(let u): return "convert-\(u.uuidString)"
        case .voice: return "voice"
        case .evening: return "evening"
        case .morning: return "morning"
        case .settings: return "settings"
        case .urgent(let u): return "urgent-\(u.uuidString)"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var tab = 0
    @Published var sheet: Route?
    @Published var cover: Route?

    func open(_ r: Route) {
        switch r {
        case .voice, .urgent:
            sheet = nil
            cover = r
        default:
            cover = nil
            sheet = r
        }
    }

    /// The full «ضروري» screen (from the alarm or its notification).
    func showUrgent(_ uid: UUID) {
        if cover == .urgent(uid) { return }
        open(.urgent(uid))
    }

    /// Opens a route after the current screen has had time to close.
    func openAfterDismiss(_ r: Route) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.open(r)
        }
    }
}

@MainActor
enum EntryActions {
    static func toggleDone(_ e: Entry) {
        e.isDone.toggle()
        e.isCancelled = false
        e.doneAt = e.isDone ? Date() : nil
        e.snoozeUntil = nil
        ReminderService.shared.writeBack(e)
        commit()
    }

    static func markDone(_ e: Entry) {
        e.isDone = true
        e.isCancelled = false
        e.doneAt = Date()
        e.snoozeUntil = nil
        ReminderService.shared.writeBack(e)
        commit()
    }

    static func markMissed(_ e: Entry) {
        e.isCancelled = true
        e.isDone = false
        e.snoozeUntil = nil
        commit()
    }

    /// Moves to tomorrow (keeping the time); an overdue item moves to tomorrow too.
    static func postpone(_ e: Entry) {
        let tomorrow = DF.addDays(1, to: DF.startOfDay(Date()))
        if let d = e.date {
            let target = d < tomorrow ? tomorrow : DF.addDays(1, to: DF.startOfDay(d))
            if e.hasTime {
                let c = DF.greg.dateComponents([.hour, .minute], from: d)
                e.date = DF.greg.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: target)
            } else {
                e.date = target
            }
        } else {
            e.date = tomorrow
        }
        e.isDone = false
        e.isCancelled = false
        e.snoozeUntil = nil
        commit()
    }

    static func delete(_ e: Entry) {
        Store.context.delete(e)
        commit()
    }

    static func addJournal(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Store.context.insert(Entry(title: t, kind: .journal))
        commit()
    }

    static func commit() {
        Store.save()
        Scheduler.shared.rebuildSoon()
    }
}

@MainActor
enum NotificationRouter {
    static func handle(action: String, category: String, uid: String?, text: String?,
                       med: String? = nil, slot: Int? = nil, day: String? = nil) {
        let entry = uid.flatMap(UUID.init(uuidString:)).flatMap { Store.entry(uid: $0) }
        let medicine = med.flatMap(UUID.init(uuidString:)).flatMap { Store.medicine(uid: $0) }
        switch action {
        case "TAKEN":
            if let medicine, let slot {
                medicine.setTaken(key: "\(day ?? DF.dayKey(Date()))|\(slot)", true)
                if medicine.snoozeSlot == slot { medicine.snoozeUntil = nil }
                MedActions.commit()
            }
        case "SNOOZE15":
            if let medicine, let slot {
                medicine.snoozeUntil = Date().addingTimeInterval(15 * 60)
                medicine.snoozeSlot = slot
                MedActions.commit()
            }
        case "DONE":
            if let entry { EntryActions.markDone(entry) }
        case "SNOOZE30":
            if let entry {
                entry.snoozeUntil = Date().addingTimeInterval(30 * 60)
                EntryActions.commit()
            }
        case "LOG":
            if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                EntryActions.addJournal(text)
                Prefs.markEveningLogged()
                Scheduler.shared.rebuildSoon()
            }
        case UNNotificationDefaultActionIdentifier, "OPEN":
            switch category {
            case "EVENING": AppState.shared.open(.evening)
            case "MORNING": AppState.shared.open(.morning)
            case "DOSE", "MED": AppState.shared.tab = 3
            default:
                AppState.shared.tab = 0
                if let entry {
                    if entry.importance == .urgent && entry.isOpen {
                        AppState.shared.showUrgent(entry.uid)
                    } else {
                        AppState.shared.open(.edit(entry.uid))
                    }
                }
            }
        default:
            break
        }
    }
}

@MainActor
enum Permissions {
    /// First launch: ask for notifications, alarms and the calendar, one after the other.
    static func firstRun() async {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Prefs.Key.askedPermissions) else {
            Scheduler.shared.rebuildSoon()
            return
        }
        d.set(true, forKey: Prefs.Key.askedPermissions)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await AlarmService.requestAuthorization()
        _ = await CalendarService.shared.request()
        Scheduler.shared.rebuildSoon()
    }
}
