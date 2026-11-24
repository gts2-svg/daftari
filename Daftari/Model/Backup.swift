import Foundation
import SwiftData

/// A full copy of everything دفتري keeps, as one JSON file the user can save in «الملفات»
/// and bring back after reinstalling (for example when moving from SideStore to TestFlight).
struct DaftariBackup: Codable {
    var format = "daftari-backup"
    var version = 1
    var exportedAt = Date()
    var entries: [EntryCopy] = []
    var medicines: [MedicineCopy] = []
    var packs: [PackCopy] = []
    var trips: [TripCopy] = []
    /// Missing in copies made before «الفترات» existed.
    var periods: [PeriodCopy]? = nil
    var prefsInt: [String: Int] = [:]
    var prefsBool: [String: Bool] = [:]
    var prefsString: [String: String] = [:]

    struct EntryCopy: Codable {
        var uid: UUID
        var title: String
        var kindRaw: Int
        var date: Date?
        var hasTime: Bool
        var importanceRaw: Int
        var isDone: Bool
        var isCancelled: Bool
        var doneAt: Date?
        var createdAt: Date
        var alarmLeadMinutes: Int
        var snoozeUntil: Date?
        var externalID: String?
        var nagDays: Int
        var nagNext: Date?
        var work: Bool?
    }

    struct MedicineCopy: Codable {
        var uid: UUID
        var name: String
        var doseNote: String
        var shelfDays: Int
        var openedAt: Date?
        var doseMinutes: [Int]
        var courseEnd: Date?
        var createdAt: Date
        var takenKeys: [String]
        var snoozeUntil: Date?
        var snoozeSlot: Int
    }

    struct PackCopy: Codable {
        var uid: UUID
        var name: String
        var itemsData: Data
        var tripDate: Date?
        var createdAt: Date
    }

    struct TripCopy: Codable {
        var uid: UUID
        var name: String
        var tripDate: Date
        var createdAt: Date
        var modeRaw: Int
        var peopleData: Data
        var expensesData: Data
        var ratesData: Data
        var currentStop: String
    }

    struct PeriodCopy: Codable {
        var uid: UUID
        var title: String
        var start: Date
        var end: Date
        var importanceRaw: Int
        var busyMask: Int
        var milestonesData: Data
        var isWork: Bool
        var createdAt: Date
    }

    var counts: (entries: Int, medicines: Int, packs: Int, trips: Int) {
        (entries.count, medicines.count, packs.count, trips.count)
    }

    var summary: String {
        "\(entries.count) عنصر · \(medicines.count) دواء · \(packs.count) قائمة · \(trips.count) قطة · \(periods?.count ?? 0) فترة"
    }
}

enum BackupError: LocalizedError {
    case notABackup
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notABackup: return "هذا الملف مو نسخة احتياطية من دفتري."
        case .unreadable: return "ما قدرت أقرأ الملف."
        }
    }
}

@MainActor
enum BackupService {
    private static let intKeys = [Prefs.Key.morning, Prefs.Key.evening, Prefs.Key.nag, Prefs.Key.defaultLead]
    private static let boolKeys = [Prefs.Key.hijriPrimary, Prefs.Key.useSystemCalendar, Prefs.Key.importReminders,
                                   Prefs.Key.askedPermissions]
    private static let stringKeys = [Prefs.Key.lastEveningLog]

    // MARK: Build

    static func makeBackup() -> DaftariBackup {
        var b = DaftariBackup()
        b.entries = Store.allEntries().map {
            .init(uid: $0.uid, title: $0.title, kindRaw: $0.kindRaw, date: $0.date, hasTime: $0.hasTime,
                  importanceRaw: $0.importanceRaw, isDone: $0.isDone, isCancelled: $0.isCancelled,
                  doneAt: $0.doneAt, createdAt: $0.createdAt, alarmLeadMinutes: $0.alarmLeadMinutes,
                  snoozeUntil: $0.snoozeUntil, externalID: $0.externalID, nagDays: $0.nagDays, nagNext: $0.nagNext, work: $0.isWork)
        }
        b.medicines = Store.allMedicines().map {
            .init(uid: $0.uid, name: $0.name, doseNote: $0.doseNote, shelfDays: $0.shelfDays, openedAt: $0.openedAt,
                  doseMinutes: $0.doseMinutes, courseEnd: $0.courseEnd, createdAt: $0.createdAt,
                  takenKeys: $0.takenKeys, snoozeUntil: $0.snoozeUntil, snoozeSlot: $0.snoozeSlot)
        }
        b.packs = Store.allPackLists().map {
            .init(uid: $0.uid, name: $0.name, itemsData: $0.itemsData, tripDate: $0.tripDate, createdAt: $0.createdAt)
        }
        b.trips = Store.allTrips().map {
            .init(uid: $0.uid, name: $0.name, tripDate: $0.tripDate, createdAt: $0.createdAt, modeRaw: $0.modeRaw,
                  peopleData: $0.peopleData, expensesData: $0.expensesData, ratesData: $0.ratesData,
                  currentStop: $0.currentStop)
        }
        b.periods = Store.allPeriods().map {
            .init(uid: $0.uid, title: $0.title, start: $0.start, end: $0.end, importanceRaw: $0.importanceRaw,
                  busyMask: $0.busyMask, milestonesData: $0.milestonesData, isWork: $0.isWork, createdAt: $0.createdAt)
        }
        let d = UserDefaults.standard
        for k in intKeys { if let v = d.object(forKey: k) as? Int { b.prefsInt[k] = v } }
        for k in boolKeys { if let v = d.object(forKey: k) as? Bool { b.prefsBool[k] = v } }
        for k in stringKeys { if let v = d.string(forKey: k) { b.prefsString[k] = v } }
        return b
    }

    static func encode(_ b: DaftariBackup) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(b)
    }

    static func decode(_ data: Data) throws -> DaftariBackup {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let b = try? d.decode(DaftariBackup.self, from: data) else { throw BackupError.unreadable }
        guard b.format == "daftari-backup" else { throw BackupError.notABackup }
        return b
    }

    /// Writes a backup file to a temporary folder and returns its address (for the share sheet).
    static func exportFile() throws -> URL {
        let data = try encode(makeBackup())
        let name = "دفتري-نسخة-\(fileStamp(Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(url: URL) throws -> DaftariBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try decode(try Data(contentsOf: url))
    }

    // MARK: Restore

    /// `replace` deletes everything first; otherwise only items not already here are added.
    /// Returns how many items were added.
    @discardableResult
    static func restore(_ b: DaftariBackup, replace: Bool) -> Int {
        let ctx = Store.context
        if replace {
            Store.allEntries().forEach { ctx.delete($0) }
            Store.allMedicines().forEach { ctx.delete($0) }
            Store.allPackLists().forEach { ctx.delete($0) }
            Store.allTrips().forEach { ctx.delete($0) }
            Store.allPeriods().forEach { ctx.delete($0) }
        }
        let haveE = replace ? [] : Set(Store.allEntries().map(\.uid))
        let haveM = replace ? [] : Set(Store.allMedicines().map(\.uid))
        let haveP = replace ? [] : Set(Store.allPackLists().map(\.uid))
        let haveT = replace ? [] : Set(Store.allTrips().map(\.uid))
        let haveR = replace ? [] : Set(Store.allPeriods().map(\.uid))
        var added = 0

        for c in b.entries where !haveE.contains(c.uid) {
            let e = Entry(title: c.title, kind: EntryKind(rawValue: c.kindRaw) ?? .task)
            e.uid = c.uid; e.kindRaw = c.kindRaw; e.date = c.date; e.hasTime = c.hasTime
            e.importanceRaw = c.importanceRaw; e.isDone = c.isDone; e.isCancelled = c.isCancelled
            e.doneAt = c.doneAt; e.createdAt = c.createdAt; e.alarmLeadMinutes = c.alarmLeadMinutes
            e.snoozeUntil = c.snoozeUntil; e.externalID = c.externalID; e.nagDays = c.nagDays; e.nagNext = c.nagNext; e.isWork = c.work ?? false
            ctx.insert(e); added += 1
        }
        for c in b.medicines where !haveM.contains(c.uid) {
            let m = Medicine(name: c.name)
            m.uid = c.uid; m.doseNote = c.doseNote; m.shelfDays = c.shelfDays; m.openedAt = c.openedAt
            m.doseMinutes = c.doseMinutes; m.courseEnd = c.courseEnd; m.createdAt = c.createdAt
            m.takenKeys = c.takenKeys; m.snoozeUntil = c.snoozeUntil; m.snoozeSlot = c.snoozeSlot
            ctx.insert(m); added += 1
        }
        for c in b.packs where !haveP.contains(c.uid) {
            let p = PackList(name: c.name)
            p.uid = c.uid; p.itemsData = c.itemsData; p.tripDate = c.tripDate; p.createdAt = c.createdAt
            ctx.insert(p); added += 1
        }
        for c in b.trips where !haveT.contains(c.uid) {
            let t = SplitTrip(name: c.name)
            t.uid = c.uid; t.tripDate = c.tripDate; t.createdAt = c.createdAt; t.modeRaw = c.modeRaw
            t.peopleData = c.peopleData; t.expensesData = c.expensesData; t.ratesData = c.ratesData
            t.currentStop = c.currentStop
            ctx.insert(t); added += 1
        }
        for c in b.periods ?? [] where !haveR.contains(c.uid) {
            let r = Period(title: c.title, start: c.start, end: c.end)
            r.uid = c.uid; r.importanceRaw = c.importanceRaw; r.busyMask = c.busyMask
            r.milestonesData = c.milestonesData; r.isWork = c.isWork; r.createdAt = c.createdAt
            ctx.insert(r); added += 1
        }
        let d = UserDefaults.standard
        if replace {
            for (k, v) in b.prefsInt { d.set(v, forKey: k) }
            for (k, v) in b.prefsBool { d.set(v, forKey: k) }
            for (k, v) in b.prefsString { d.set(v, forKey: k) }
        }
        Store.save()
        Scheduler.shared.rebuildSoon()
        return added
    }

    // MARK: Automatic weekly copy (visible in «الملفات» › «على الـ iPhone» › «دفتري»)

    static var autoFolder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("نسخ احتياطية", isDirectory: true)
    }

    private static let lastAutoKey = "lastAutoBackup"

    static var lastAutoBackup: Date? {
        UserDefaults.standard.object(forKey: lastAutoKey) as? Date
    }

    /// Keeps the last four weekly copies. Cheap; called when the app comes to the front.
    static func autoBackupIfDue() {
        guard Store.openError == nil else { return }
        if let last = lastAutoBackup, Date().timeIntervalSince(last) < 7 * 24 * 3600 { return }
        guard let folder = autoFolder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try encode(makeBackup())
            let url = folder.appendingPathComponent("دفتري-\(fileStamp(Date())).json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            UserDefaults.standard.set(Date(), forKey: lastAutoKey)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
            for old in files.dropFirst(4) { try? FileManager.default.removeItem(at: old) }
        } catch {
            // Best effort: the manual export in Settings is the real safety net.
        }
    }

    private static func fileStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: d)
    }
}
