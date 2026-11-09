import AppIntents
import Foundation

/// Runs when the user stops a «ضروري» alarm: opens دفتري on the full «ضروري» screen
/// (the design with «تم، شفته» and «ذكّرني بعد 10 دقائق»).
struct OpenUrgentIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "افتح الموعد الضروري"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "المعرّف")
    var entryID: String

    init() { entryID = "" }
    init(entryID: String) { self.entryID = entryID }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let uid = UUID(uuidString: entryID), Store.entry(uid: uid) != nil {
            AppState.shared.tab = 0
            AppState.shared.showUrgent(uid)
        }
        return .result()
    }
}

/// «أجّلني 10 د» on the alarm screen: rings again in ten minutes without opening the app.
struct SnoozeUrgentIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "أجّل المنبّه 10 دقائق"
    static var isDiscoverable: Bool = false

    @Parameter(title: "المعرّف")
    var entryID: String

    @Parameter(title: "العنوان")
    var alarmTitle: String

    init() {
        entryID = ""
        alarmTitle = ""
    }

    init(entryID: String, title: String) {
        self.entryID = entryID
        self.alarmTitle = title
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await UrgentActions.snooze(entryID: entryID, title: alarmTitle)
        return .result()
    }
}

@MainActor
enum UrgentActions {
    static let snoozeMinutes = 10

    /// Sets the item to ring again in ten minutes (and keeps the reminders going).
    static func snooze(entryID: String, title: String) async {
        let at = Date().addingTimeInterval(TimeInterval(snoozeMinutes * 60))
        if let uid = UUID(uuidString: entryID), let e = Store.entry(uid: uid) {
            e.snoozeUntil = at
            Store.save()
            await Scheduler.shared.rebuild()
        } else {
            await AlarmService.schedule(id: UUID(), at: at, title: title, entry: nil)
        }
    }
}
