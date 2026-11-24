import Foundation
import SwiftData

@MainActor
enum Store {
    /// Set when the saved data could not be opened. The app then runs on an empty temporary
    /// store and shows a recovery screen, instead of crashing on every launch.
    static private(set) var openError: String?

    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Entry.self, Medicine.self, PackList.self, SplitTrip.self, Period.self)
        } catch {
            openError = "\(error)"
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            // An in-memory container with the same models cannot fail for schema reasons.
            return try! ModelContainer(for: Entry.self, Medicine.self, PackList.self, SplitTrip.self, Period.self,
                                       configurations: memory)
        }
    }()

    /// The files of the saved database (to hand them over when it can't be opened).
    static var storeFiles: [URL] {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let all = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return all.filter { $0.lastPathComponent.hasPrefix("default.store") }
    }

    static var context: ModelContext { container.mainContext }

    static func allEntries() -> [Entry] {
        (try? context.fetch(FetchDescriptor<Entry>())) ?? []
    }

    static func entry(uid: UUID) -> Entry? {
        allEntries().first { $0.uid == uid }
    }

    static func allMedicines() -> [Medicine] {
        (try? context.fetch(FetchDescriptor<Medicine>())) ?? []
    }

    static func medicine(uid: UUID) -> Medicine? {
        allMedicines().first { $0.uid == uid }
    }

    static func allPackLists() -> [PackList] {
        (try? context.fetch(FetchDescriptor<PackList>())) ?? []
    }

    static func packList(uid: UUID) -> PackList? {
        allPackLists().first { $0.uid == uid }
    }

    static func allTrips() -> [SplitTrip] {
        (try? context.fetch(FetchDescriptor<SplitTrip>())) ?? []
    }

    static func allPeriods() -> [Period] {
        (try? context.fetch(FetchDescriptor<Period>())) ?? []
    }

    /// Last save failure, shown in Settings so a silent failure doesn't go unnoticed.
    static private(set) var lastSaveError: String?

    /// Once, after the «شغل / بيت» filter arrived: guess it for everything saved before.
    static func guessWorkOnce() {
        let key = "workGuessed"
        guard openError == nil, !UserDefaults.standard.bool(forKey: key) else { return }
        for e in allEntries() where !e.isWork {
            e.isWork = ArabicDateParser.looksLikeWork(e.title)
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    static func save() {
        do {
            try context.save()
            lastSaveError = nil
        } catch {
            lastSaveError = "\(error.localizedDescription)"
        }
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
        static let importReminders = "importReminders"
        static let nag = "nagMinutes"
    }

    private static var d: UserDefaults { .standard }

    static var morningMinutes: Int { d.object(forKey: Key.morning) as? Int ?? 8 * 60 }
    static var eveningMinutes: Int { d.object(forKey: Key.evening) as? Int ?? 20 * 60 }
    static var hijriPrimary: Bool { d.object(forKey: Key.hijriPrimary) as? Bool ?? true }
    static var useSystemCalendar: Bool { d.object(forKey: Key.useSystemCalendar) as? Bool ?? true }
    static var nagMinutes: Int { d.object(forKey: Key.nag) as? Int ?? 17 * 60 }
    static var importReminders: Bool { d.bool(forKey: Key.importReminders) }
    static var defaultLead: Int { d.object(forKey: Key.defaultLead) as? Int ?? 60 }

    static var lastEveningLog: String { d.string(forKey: Key.lastEveningLog) ?? "" }
    static func markEveningLogged(_ day: Date = Date()) {
        d.set(DF.dayKey(day), forKey: Key.lastEveningLog)
    }
}
