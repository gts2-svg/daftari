import Foundation
import SwiftData

@MainActor
enum Store {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Entry.self)
        } catch {
            fatalError("تعذر فتح قاعدة البيانات: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    static func allEntries() -> [Entry] {
        (try? context.fetch(FetchDescriptor<Entry>())) ?? []
    }

    static func entry(uid: UUID) -> Entry? {
        allEntries().first { $0.uid == uid }
    }

    static func save() {
        try? context.save()
    }
}

enum Prefs {
    enum Key {
        static let morning = "morningMinutes"
        static let evening = "eveningMinutes"
        static let hijriPrimary = "hijriPrimary"
        static let useSystemCalendar = "useSystemCalendar"
        static let defaultLead = "defaultAlarmLead"
        static let lastEveningLog = "lastEveningLog"
        static let askedPermissions = "askedPermissions"
    }

    private static var d: UserDefaults { .standard }

    static var morningMinutes: Int { d.object(forKey: Key.morning) as? Int ?? 8 * 60 }
    static var eveningMinutes: Int { d.object(forKey: Key.evening) as? Int ?? 20 * 60 }
    static var hijriPrimary: Bool { d.object(forKey: Key.hijriPrimary) as? Bool ?? true }
    static var useSystemCalendar: Bool { d.object(forKey: Key.useSystemCalendar) as? Bool ?? true }
    static var defaultLead: Int { d.object(forKey: Key.defaultLead) as? Int ?? 60 }

    static var lastEveningLog: String { d.string(forKey: Key.lastEveningLog) ?? "" }
    static func markEveningLogged(_ day: Date = Date()) {
        d.set(DF.dayKey(day), forKey: Key.lastEveningLog)
    }
}
