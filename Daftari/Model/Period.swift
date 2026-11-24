import Foundation
import SwiftData

/// A point inside a period that needs its own reminder («بداية الحضوري»).
struct PeriodMilestone: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var day: Date

    init(title: String, day: Date) {
        self.title = title
        self.day = DF.startOfDay(day)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        day = (try? c.decode(Date.self, forKey: .day)) ?? Date()
    }
}

/// «فترة»: something that runs over many days — a course, a trip, a leave, an assignment.
/// Drawn in the calendar as one joined bar in the colour of its importance.
@Model
final class Period {
    var uid: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var importanceRaw: Int = 0
    /// The weekdays it actually takes (bit 0 = Sunday … bit 6 = Saturday). 0 = every day.
    var busyMask: Int = 0
    var milestonesData: Data = Data()
    var isWork: Bool = false
    var createdAt: Date = Date()

    init(title: String, start: Date, end: Date) {
        self.uid = UUID()
        self.title = title
        self.start = DF.startOfDay(start)
        self.end = DF.startOfDay(max(start, end))
        self.createdAt = Date()
    }
}

enum PeriodStatus: Equatable {
    case upcoming(daysLeft: Int)
    case running(day: Int, of: Int)
    case finished
}

extension Period {
    var importance: Importance {
        get { Importance(rawValue: importanceRaw) ?? .normal }
        set { importanceRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "فترة" : t
    }

    var milestones: [PeriodMilestone] {
        get {
            ((try? JSONDecoder().decode([PeriodMilestone].self, from: milestonesData)) ?? [])
                .sorted { $0.day < $1.day }
        }
        set { milestonesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var startDay: Date { DF.startOfDay(start) }
    var endDay: Date { DF.startOfDay(end) }

    /// Days from the first to the last, both counted.
    var length: Int { max(1, DF.daysBetween(startDay, endDay) + 1) }

    func contains(_ day: Date) -> Bool {
        let d = DF.startOfDay(day)
        return d >= startDay && d <= endDay
    }

    static func weekdayIndex(_ day: Date) -> Int { DF.greg.component(.weekday, from: day) - 1 }

    /// Inside the period and on one of its weekdays.
    func isBusy(_ day: Date) -> Bool {
        guard contains(day) else { return false }
        return busyMask == 0 || busyMask & (1 << Self.weekdayIndex(day)) != 0
    }

    func overlaps(from: Date, to: Date) -> Bool {
        startDay < to && endDay >= DF.startOfDay(from)
    }

    func status(_ now: Date = Date()) -> PeriodStatus {
        let today = DF.startOfDay(now)
        if today < startDay { return .upcoming(daysLeft: DF.daysBetween(today, startDay)) }
        if today > endDay { return .finished }
        return .running(day: DF.daysBetween(startDay, today) + 1, of: length)
    }

    /// 0…1 of the way through.
    func progress(_ now: Date = Date()) -> Double {
        switch status(now) {
        case .upcoming: return 0
        case .finished: return 1
        case .running(let day, let of): return Double(day) / Double(max(of, 1))
        }
    }

    func statusText(_ now: Date = Date()) -> String {
        switch status(now) {
        case .upcoming(let n):
            return n == 1 ? "تبدأ بكرة" : "تبدأ بعد \(DF.daysText(n))"
        case .running(let day, let of):
            let left = of - day
            return left == 0 ? "اليوم آخر يوم · \(day) من \(of)" : "اليوم \(day) من \(of) · باقي \(DF.daysText(left))"
        case .finished:
            return "انتهت"
        }
    }

    var spanText: String {
        "\(DF.dayMonth(startDay, cal: DF.primary)) ← \(DF.dayMonth(endDay, cal: DF.primary)) · \(DF.daysText(length))"
    }

    var busyText: String? {
        guard busyMask != 0 else { return nil }
        let names = (0..<7).filter { busyMask & (1 << $0) != 0 }.map { DF.weekdays[$0] }
        return names.joined(separator: "، ")
    }
}

@MainActor
enum PeriodActions {
    static func delete(_ p: Period) {
        Store.context.delete(p)
        Store.save()
        Scheduler.shared.rebuildSoon()
    }

    static func commit() {
        Store.save()
        Scheduler.shared.rebuildSoon()
    }

    /// Up to `lanes` bars per row, each period keeping one lane through the whole month.
    static func lanes(_ periods: [Period], limit: Int = 2) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        let sorted = periods.sorted { a, b in
            a.importanceRaw != b.importanceRaw ? a.importanceRaw > b.importanceRaw : a.startDay < b.startDay
        }
        // Importance first, so a «ضروري» bar always gets a lane; then fit by dates.
        var placed: [(Period, Int)] = []
        for p in sorted {
            var lane: Int?
            for i in 0..<limit {
                let clash = placed.contains { $0.1 == i && $0.0.startDay <= p.endDay && p.startDay <= $0.0.endDay }
                if !clash { lane = i; break }
            }
            if let lane { out[p.uid] = lane; placed.append((p, lane)) }
        }
        return out
    }
}
