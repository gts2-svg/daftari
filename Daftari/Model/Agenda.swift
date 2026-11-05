import Foundation
import EventKit

/// One line in a day: either an entry of ours or an event from the iPhone calendar.
struct DayItem: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let hasTime: Bool
    let importance: Importance
    let entry: Entry?

    var isSystem: Bool { entry == nil }
    var isDone: Bool { entry?.isDone ?? false }
    var isCancelled: Bool { entry?.isCancelled ?? false }
    var isAppointment: Bool { entry == nil || entry?.kind == .appointment }

    init(entry: Entry) {
        id = entry.uid.uuidString
        title = entry.title
        date = entry.date
        hasTime = entry.hasTime
        importance = entry.importance
        self.entry = entry
    }

    init(event: EKEvent) {
        id = "ek-" + (event.eventIdentifier ?? UUID().uuidString) + "-\(event.startDate.timeIntervalSince1970)"
        title = event.title ?? "موعد"
        date = event.startDate
        hasTime = !event.isAllDay
        importance = .normal
        entry = nil
    }
}

@MainActor
enum Agenda {
    static func sorted(_ items: [DayItem]) -> [DayItem] {
        items.sorted { a, b in
            switch (a.hasTime, b.hasTime) {
            case (true, true): return (a.date ?? .distantPast) < (b.date ?? .distantPast)
            case (true, false): return true
            case (false, true): return false
            default: return a.importance.rawValue > b.importance.rawValue
            }
        }
    }

    /// Everything on a given day (ours, done or not, plus iPhone calendar events).
    static func items(on day: Date, entries: [Entry], includeClosed: Bool = true) -> [DayItem] {
        let ours = entries.filter { e in
            guard e.isScheduledKind, let d = e.date else { return false }
            guard DF.greg.isDate(d, inSameDayAs: day) else { return false }
            return includeClosed ? !e.isCancelled : e.isOpen
        }.map(DayItem.init(entry:))
        let start = DF.startOfDay(day)
        let events = CalendarService.shared.events(from: start, to: DF.addDays(1, to: start)).map(DayItem.init(event:))
        return sorted(ours + events)
    }

    /// Open items whose day has passed.
    static func overdue(entries: [Entry], now: Date = Date()) -> [Entry] {
        let today = DF.startOfDay(now)
        return entries.filter { e in
            guard e.isScheduledKind, e.isOpen, let d = e.date else { return false }
            return d < today
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// The nearest upcoming timed item (within two weeks).
    static func next(after now: Date, entries: [Entry]) -> DayItem? {
        let horizon = DF.addDays(14, to: now)
        let ours = entries.filter { e in
            guard e.isScheduledKind, e.isOpen, e.hasTime, let d = e.date else { return false }
            return d > now && d < horizon
        }.map(DayItem.init(entry:))
        let events = CalendarService.shared.events(from: now, to: horizon)
            .filter { !$0.isAllDay && $0.startDate > now }
            .map(DayItem.init(event:))
        return (ours + events).min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Dot colour per day for a date range: strongest open importance wins; iPhone events show grey.
    static func marks(entries: [Entry], from: Date, to: Date) -> [String: Importance?] {
        var out: [String: Importance?] = [:]
        for e in entries where e.isScheduledKind && e.isOpen {
            guard let d = e.date, d >= from, d < to else { continue }
            let k = DF.dayKey(d)
            let current = out[k] ?? nil
            if current == nil || (current?.rawValue ?? -1) < e.importance.rawValue { out[k] = e.importance }
        }
        for ev in CalendarService.shared.events(from: from, to: to) {
            let k = DF.dayKey(ev.startDate)
            if out[k] == nil { out[k] = .some(nil) }
        }
        return out
    }
}
