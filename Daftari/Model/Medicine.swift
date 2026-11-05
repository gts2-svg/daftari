import Foundation
import SwiftData

/// A medicine (e.g. eye drops): when the current pack was opened, how long it lasts once open,
/// and the times of day to take it.
@Model
final class Medicine {
    var uid: UUID = UUID()
    var name: String = ""
    var doseNote: String = ""
    var shelfDays: Int = 30
    var openedAt: Date? = nil
    var doseMinutes: [Int] = []
    var courseEnd: Date? = nil
    var createdAt: Date = Date()
    var takenKeys: [String] = []
    var snoozeUntil: Date? = nil
    var snoozeSlot: Int = -1

    init(name: String) {
        self.uid = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

enum DoseState {
    case taken
    case late
    case upcoming
}

extension Medicine {
    /// Dose times as minutes after midnight, sorted, without duplicates.
    var slots: [Int] { Array(Set(doseMinutes)).sorted() }

    /// The day the open pack should be thrown away.
    var expiry: Date? {
        guard let openedAt else { return nil }
        return DF.addDays(shelfDays, to: DF.startOfDay(openedAt))
    }

    func daysLeft(now: Date = Date()) -> Int? {
        guard let expiry else { return nil }
        return DF.daysBetween(now, expiry)
    }

    /// 1 = just opened, 0 = expired.
    func fractionLeft(now: Date = Date()) -> Double {
        guard let left = daysLeft(now: now), shelfDays > 0 else { return 0 }
        return max(0, min(1, Double(left) / Double(shelfDays)))
    }

    func isActive(on day: Date) -> Bool {
        guard let courseEnd else { return true }
        return DF.startOfDay(day) <= DF.startOfDay(courseEnd)
    }

    var courseFinished: Bool { !isActive(on: Date()) }

    static func key(_ day: Date, _ slot: Int) -> String { "\(DF.dayKey(day))|\(slot)" }

    func slotDate(_ day: Date, _ slot: Int) -> Date {
        DF.greg.date(bySettingHour: slot / 60, minute: slot % 60, second: 0, of: day) ?? day
    }

    func taken(_ day: Date, _ slot: Int) -> Bool {
        takenKeys.contains(Self.key(day, slot))
    }

    func setTaken(key: String, _ value: Bool) {
        if value {
            if !takenKeys.contains(key) { takenKeys.append(key) }
        } else {
            takenKeys.removeAll { $0 == key }
        }
        if takenKeys.count > 120 { takenKeys.removeFirst(takenKeys.count - 120) }
    }

    func state(_ day: Date, _ slot: Int, now: Date = Date()) -> DoseState {
        if taken(day, slot) { return .taken }
        return slotDate(day, slot) < now ? .late : .upcoming
    }

    func takenCount(on day: Date) -> Int { slots.filter { taken(day, $0) }.count }

    /// The next dose today that hasn't been taken.
    func nextDose(now: Date = Date()) -> Int? {
        slots.first { !taken(now, $0) && slotDate(now, $0) >= now.addingTimeInterval(-60 * 60) }
            ?? slots.first { !taken(now, $0) }
    }

    /// Which dose «أخذت جرعة الآن» should mark: the latest one already due, else the next one.
    func slotToMarkNow(now: Date = Date()) -> Int? {
        let open = slots.filter { !taken(now, $0) }
        if let due = open.last(where: { slotDate(now, $0) <= now.addingTimeInterval(45 * 60) }) { return due }
        return open.first
    }

    var openedText: String {
        guard let openedAt else { return "ما فتحت العلبة بعد" }
        let ago = DF.daysBetween(openedAt, Date())
        let when = ago == 0 ? "اليوم" : (ago == 1 ? "أمس" : "قبل \(DF.daysText(ago))")
        return "فتحتها \(DF.dayMonth(openedAt, cal: DF.primary, year: false)) · \(when)"
    }

    func expiryText(now: Date = Date()) -> String {
        guard let expiry, let left = daysLeft(now: now) else { return "اضغط «فتحتها» لما تفتح العلبة" }
        if left < 0 { return "انتهت صلاحيتها — ارمها وافتح جديدة" }
        if left == 0 { return "تنتهي اليوم — ارمها وافتح جديدة" }
        if left <= 3 { return "تنتهي بعد \(DF.daysText(left)) — جهّز علبة جديدة" }
        return "تنتهي \(DF.dayMonth(expiry, cal: DF.primary, year: false))"
    }

    static func slotText(_ slot: Int) -> String {
        let h24 = slot / 60, m = slot % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d %@", h12, m, h24 < 12 ? "ص" : "م")
    }
}

@MainActor
enum MedActions {
    static func toggle(_ m: Medicine, slot: Int, day: Date = Date()) {
        m.setTaken(key: Medicine.key(day, slot), !m.taken(day, slot))
        if m.snoozeSlot == slot { m.snoozeUntil = nil }
        commit()
    }

    static func takeNow(_ m: Medicine) {
        guard let slot = m.slotToMarkNow() else { return }
        m.setTaken(key: Medicine.key(Date(), slot), true)
        if m.snoozeSlot == slot { m.snoozeUntil = nil }
        commit()
    }

    static func openNewPack(_ m: Medicine, on day: Date = Date()) {
        m.openedAt = day
        commit()
    }

    static func delete(_ m: Medicine) {
        Store.context.delete(m)
        commit()
    }

    static func commit() {
        Store.save()
        Scheduler.shared.rebuildSoon()
    }
}
