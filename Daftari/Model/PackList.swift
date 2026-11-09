import Foundation
import SwiftData

/// One thing to take («أغراضي»).
struct PackItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

/// A reusable packing list: البر، السفر، العزبة… Tick while packing, then «صفّر» for next time.
@Model
final class PackList {
    var uid: UUID = UUID()
    var name: String = ""
    var itemsData: Data = Data()
    var tripDate: Date? = nil
    var createdAt: Date = Date()

    init(name: String) {
        self.uid = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

extension PackList {
    var items: [PackItem] {
        get { (try? JSONDecoder().decode([PackItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var total: Int { items.count }
    var doneCount: Int { items.filter(\.done).count }
    var remaining: [PackItem] { items.filter { !$0.done } }
    var fraction: Double { total == 0 ? 0 : Double(doneCount) / Double(total) }
    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "قائمة بدون اسم" : t
    }

    /// One line per item; bullets and numbering from the Notes app are dropped.
    static func lines(from text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var t = raw.trimmingCharacters(in: .whitespaces)
            let bullets = ["-", "•", "*", "◦", "▪", "☐", "☑", "✓", "✔", "–", "—"]
            while let b = bullets.first(where: { t.hasPrefix($0) }) {
                t = String(t.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
            }
            if let r = t.range(of: "^[0-9٠-٩]+[.)\\-]\\s*", options: .regularExpression) {
                t.removeSubrange(r)
            }
            t = t.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
    }

    func add(_ text: String) {
        var list = items
        let existing = Set(list.map { $0.text })
        for line in PackList.lines(from: text) where !existing.contains(line) {
            list.append(PackItem(text: line))
        }
        items = list
    }

    func toggle(_ id: UUID) {
        var list = items
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].done.toggle() }
        items = list
    }

    func remove(_ id: UUID) {
        items = items.filter { $0.id != id }
    }

    func resetChecks() {
        items = items.map { var x = $0; x.done = false; return x }
    }
}
