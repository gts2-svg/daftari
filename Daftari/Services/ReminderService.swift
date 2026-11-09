import Foundation
import EventKit

/// Brings in the iPhone Reminders (including what Siri adds there) as دفتري items,
/// and keeps «تم» in step both ways.
@MainActor
final class ReminderService {
    static let shared = ReminderService()
    private let store = EKEventStore()

    var authorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    var canAsk: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .notDetermined
    }

    func request() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    /// A plain copy of a reminder, so nothing from EventKit crosses threads.
    private struct Item {
        let id: String
        let title: String
        let due: DateComponents?
        let priority: Int
    }

    private func incomplete() async -> [Item] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map {
                    Item(id: $0.calendarItemIdentifier,
                         title: $0.title ?? "",
                         due: $0.dueDateComponents,
                         priority: $0.priority)
                }
                cont.resume(returning: items)
            }
        }
    }

    /// Returns how many new items came in.
    @discardableResult
    func sync() async -> Int {
        guard Prefs.importReminders, authorized else { return 0 }
        store.refreshSourcesIfNecessary()
        let items = await incomplete()
        let entries = Store.allEntries()
        let imported = Dictionary(entries.compactMap { e in e.externalID.map { ($0, e) } },
                                  uniquingKeysWith: { a, _ in a })
        let openIDs = Set(items.map(\.id))
        var added = 0

        for item in items where imported[item.id] == nil {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var date: Date?
            var hasTime = false
            if let due = item.due {
                hasTime = due.hour != nil
                var c = due
                if c.calendar == nil { c.calendar = DF.greg }
                date = c.date ?? DF.greg.date(from: c)
                if !hasTime, let d = date { date = DF.startOfDay(d) }
            }
            // Skip a reminder that was already typed into دفتري by hand (same title and day).
            let duplicate = entries.contains { e in
                e.externalID == nil && e.isOpen && e.title == title &&
                    ((e.date == nil && date == nil) ||
                     (e.date != nil && date != nil && DF.greg.isDate(e.date!, inSameDayAs: date!)))
            }
            if duplicate { continue }

            let kind = ArabicDateParser.parse(title).kind
            let importance: Importance = (1...4).contains(item.priority) ? .important : .normal
            let e = Entry(title: title, kind: kind, date: date, hasTime: hasTime,
                          importance: importance, alarmLeadMinutes: Prefs.defaultLead)
            e.externalID = item.id
            Store.context.insert(e)
            added += 1
        }

        // Finished in Reminders → finished here too.
        for (id, e) in imported where e.isOpen && !openIDs.contains(id) {
            if let r = store.calendarItem(withIdentifier: id) as? EKReminder, r.isCompleted {
                e.isDone = true
                e.doneAt = r.completionDate ?? Date()
                e.snoozeUntil = nil
            }
        }

        Store.save()
        return added
    }

    /// Finished here → tick it in Reminders as well (and untick if reopened).
    func writeBack(_ e: Entry) {
        guard Prefs.importReminders, authorized, let id = e.externalID,
              let r = store.calendarItem(withIdentifier: id) as? EKReminder,
              r.isCompleted != e.isDone else { return }
        r.isCompleted = e.isDone
        try? store.save(r, commit: true)
    }
}
