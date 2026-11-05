import Foundation
import EventKit

/// Reads events from the iPhone Calendar so they show next to the user's own items.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()

    var authorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var canAsk: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func request() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard authorized, Prefs.useSystemCalendar, start < end else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
