import Foundation
import SwiftData

enum EntryKind: Int, CaseIterable, Hashable {
    case appointment = 0
    case task = 1
    case idea = 2
    case journal = 3

    var label: String {
        switch self {
        case .appointment: return "موعد"
        case .task: return "مهمة"
        case .idea: return "فكرة"
        case .journal: return "يومية"
        }
    }
}

enum Importance: Int, CaseIterable, Hashable {
    case normal = 0
    case important = 1
    case urgent = 2

    var label: String {
        switch self {
        case .normal: return "عادي"
        case .important: return "مهم"
        case .urgent: return "ضروري"
        }
    }

    var hint: String {
        switch self {
        case .normal: return "إشعار"
        case .important: return "يتكرر لين «تم»"
        case .urgent: return "منبّه حقيقي"
        }
    }
}

@Model
final class Entry {
    var uid: UUID = UUID()
    var title: String = ""
    var kindRaw: Int = 1
    var date: Date? = nil
    var hasTime: Bool = false
    var importanceRaw: Int = 0
    var isDone: Bool = false
    var isCancelled: Bool = false
    var doneAt: Date? = nil
    var createdAt: Date = Date()
    var alarmLeadMinutes: Int = 60
    var snoozeUntil: Date? = nil
    /// The iPhone Reminders item this came from (when imported).
    var externalID: String? = nil

    init(title: String, kind: EntryKind, date: Date? = nil, hasTime: Bool = false,
         importance: Importance = .normal, alarmLeadMinutes: Int = 60) {
        self.uid = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.date = date
        self.hasTime = hasTime
        self.importanceRaw = importance.rawValue
        self.alarmLeadMinutes = alarmLeadMinutes
        self.createdAt = Date()
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .task }
        set { kindRaw = newValue.rawValue }
    }

    var importance: Importance {
        get { Importance(rawValue: importanceRaw) ?? .normal }
        set { importanceRaw = newValue.rawValue }
    }

    var isOpen: Bool { !isDone && !isCancelled }
    var isScheduledKind: Bool { kind == .appointment || kind == .task }

    /// The moment reminders are built around: the exact time, or 9:00 for an all-day item.
    var anchorDate: Date? {
        guard let date else { return nil }
        if hasTime { return date }
        return DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: date)
    }
}
