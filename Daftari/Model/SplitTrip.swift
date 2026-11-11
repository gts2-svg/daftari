import Foundation
import SwiftData

// MARK: - القطة: shared trip expenses

enum SplitCurrency: String, Codable, CaseIterable, Identifiable {
    case sar = "SAR", usd = "USD", eur = "EUR", gbp = "GBP"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .sar: return "ر.س"
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }

    var name: String {
        switch self {
        case .sar: return "ريال"
        case .usd: return "دولار"
        case .eur: return "يورو"
        case .gbp: return "باوند"
        }
    }

    /// Starting rate to the riyal; editable per trip.
    var defaultRate: Double {
        switch self {
        case .sar: return 1
        case .usd: return 3.75
        case .eur: return 4.35
        case .gbp: return 5.0
        }
    }

    /// Words in a typed line that pick this currency.
    var words: [String] {
        switch self {
        case .sar: return ["ريال", "ر.س", "SAR"]
        case .usd: return ["دولار", "$", "USD"]
        case .eur: return ["يورو", "€", "EUR"]
        case .gbp: return ["باوند", "جنيه", "£", "GBP"]
        }
    }
}

enum SplitCategory: String, Codable, CaseIterable, Identifiable {
    case fuel, food, coffee, stay, grocery, transport, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fuel: return "وقود"
        case .food: return "أكل"
        case .coffee: return "قهوة"
        case .stay: return "سكن"
        case .grocery: return "بقالة"
        case .transport: return "مشاوير"
        case .other: return "أخرى"
        }
    }

    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .stay: return "bed.double.fill"
        case .grocery: return "cart.fill"
        case .transport: return "car.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var hex: UInt32 {
        switch self {
        case .fuel: return 0xC2410C
        case .food: return 0x1D6A63
        case .coffee: return 0x8A5A12
        case .stay: return 0x55407A
        case .grocery: return 0x22633A
        case .transport: return 0x2F5D8A
        case .other: return 0x6B7C8C
        }
    }

    private var keywords: [String] {
        switch self {
        case .fuel: return ["بنزين", "بانزين", "ديزل", "وقود", "محطة", "تعبئة", "تفويل"]
        case .food: return ["عشاء", "عشا", "غداء", "غدا", "فطور", "ريوق", "مطعم", "أكل", "اكل", "وجبة", "شاورما", "برجر", "مندي", "كبسة", "بيتزا", "مشويات"]
        case .coffee: return ["قهوة", "قهوه", "كوفي", "كافيه", "شاهي", "شاي", "كرك", "لاتيه", "عصير", "ستاربكس"]
        case .stay: return ["سكن", "فندق", "شقة", "شقه", "شاليه", "استراحة", "استراحه", "غرفة", "غرفه", "نزل", "منتجع", "مخيم"]
        case .grocery: return ["بقالة", "بقاله", "سوبرماركت", "ماركت", "ماء", "مويه", "موية", "ثلج", "فحم", "حطب", "خبز", "تموين"]
        case .transport: return ["تاكسي", "أوبر", "اوبر", "كريم", "تذكرة", "تذاكر", "طيران", "قطار", "باص", "موقف", "مواقف", "تأجير", "ايجار سيارة", "إيجار سيارة", "مغسلة", "بنشر"]
        case .other: return []
        }
    }

    static func guess(_ text: String) -> SplitCategory {
        let t = text.lowercased()
        for c in allCases where c != .other {
            if c.keywords.contains(where: { t.contains($0) }) { return c }
        }
        return .other
    }
}

struct SplitPerson: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String = ""
    /// «أنا أدفع»: this person has sent their share.
    var settled = false

    init(name: String = "") { self.name = name }

    static let fallbackMe: SplitPerson = {
        var p = SplitPerson()
        p.id = UUID(uuidString: "00000000-0000-0000-0000-00000000A0A0")!
        return p
    }()

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        settled = (try? c.decode(Bool.self, forKey: .settled)) ?? false
    }
}

struct SplitExpense: Codable, Hashable, Identifiable {
    var id = UUID()
    var amount: Double
    var currency: SplitCurrency = .sar
    var note: String
    var category: SplitCategory
    var stop: String = ""
    /// Who paid; nil means the first person («أنا»).
    var payer: UUID? = nil
    var createdAt = Date()

    init(amount: Double, currency: SplitCurrency = .sar, note: String, category: SplitCategory? = nil,
         stop: String = "", payer: UUID? = nil) {
        self.amount = amount
        self.currency = currency
        self.note = note
        self.category = category ?? SplitCategory.guess(note)
        self.stop = stop
        self.payer = payer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        currency = (try? c.decode(SplitCurrency.self, forKey: .currency)) ?? .sar
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        category = (try? c.decode(SplitCategory.self, forKey: .category)) ?? .other
        stop = (try? c.decode(String.self, forKey: .stop)) ?? ""
        payer = try? c.decode(UUID.self, forKey: .payer)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

struct SplitCategorySum: Identifiable {
    let category: SplitCategory
    let amount: Double
    var id: SplitCategory { category }
}

struct SplitStopGroup: Identifiable {
    let stop: String
    let items: [SplitExpense]
    let amount: Double
    var id: String { stop }
}

enum SplitMode: Int, CaseIterable {
    /// One person pays everything, then collects the shares.
    case iPay = 0
    /// Several people pay along the way; settle at the end.
    case everyone = 1
}

/// One trip's «قطة».
@Model
final class SplitTrip {
    var uid: UUID = UUID()
    var name: String = ""
    var tripDate: Date = Date()
    var createdAt: Date = Date()
    var modeRaw: Int = 0
    var peopleData: Data = Data()
    var expensesData: Data = Data()
    var ratesData: Data = Data()
    var currentStop: String = ""

    init(name: String) {
        self.uid = UUID()
        self.name = name
        self.tripDate = DF.startOfDay(Date())
        self.createdAt = Date()
        self.peopleData = (try? JSONEncoder().encode([SplitPerson(), SplitPerson()])) ?? Data()
    }
}

extension SplitTrip {
    var mode: SplitMode {
        get { SplitMode(rawValue: modeRaw) ?? .iPay }
        set { modeRaw = newValue.rawValue }
    }

    /// Always at least one person; the first is «أنا».
    var people: [SplitPerson] {
        get {
            let list = (try? JSONDecoder().decode([SplitPerson].self, from: peopleData)) ?? []
            return list.isEmpty ? [SplitPerson.fallbackMe] : list
        }
        set { peopleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var expenses: [SplitExpense] {
        get { (try? JSONDecoder().decode([SplitExpense].self, from: expensesData)) ?? [] }
        set { expensesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var rates: [String: Double] {
        get { (try? JSONDecoder().decode([String: Double].self, from: ratesData)) ?? [:] }
        set { ratesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func rate(_ c: SplitCurrency) -> Double {
        if c == .sar { return 1 }
        if let r = rates[c.rawValue], r > 0 { return r }
        return c.defaultRate
    }

    func riyals(_ e: SplitExpense) -> Double { e.amount * rate(e.currency) }

    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "قطة بدون اسم" : t
    }

    var count: Int { max(people.count, 1) }
    var me: SplitPerson { people[0] }

    func personName(_ p: SplitPerson) -> String {
        let t = p.name.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        guard let i = people.firstIndex(where: { $0.id == p.id }) else { return "—" }
        return i == 0 ? "أنا" : "شخص \(i + 1)"
    }

    func person(_ id: UUID?) -> SplitPerson {
        people.first { $0.id == id } ?? me
    }

    var total: Double { expenses.reduce(0) { $0 + riyals($1) } }
    var share: Double { total / Double(count) }

    var usesForeign: Bool { expenses.contains { $0.currency != .sar } }

    var byCategory: [SplitCategorySum] {
        var sums: [SplitCategory: Double] = [:]
        for e in expenses { sums[e.category, default: 0] += riyals(e) }
        return sums.filter { $0.value > 0 }
            .map { SplitCategorySum(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Stops in the order they were first used ("" = no stop).
    var stops: [String] {
        var seen: [String] = []
        for e in expenses where !seen.contains(e.stop) { seen.append(e.stop) }
        return seen
    }

    var namedStops: [String] { stops.filter { !$0.isEmpty } }

    var byStop: [SplitStopGroup] {
        let all = expenses
        return stops.map { s in
            let items = all.filter { $0.stop == s }
            return SplitStopGroup(stop: s, items: items, amount: items.reduce(0) { $0 + riyals($1) })
        }
    }

    func paid(by id: UUID) -> Double {
        expenses.filter { ($0.payer ?? me.id) == id }.reduce(0) { $0 + riyals($1) }
    }

    /// «كل واحد يدفع»: the fewest transfers that settle everyone.
    var transfers: [(from: SplitPerson, to: SplitPerson, amount: Double)] {
        let s = share
        var debtors: [(SplitPerson, Double)] = []
        var creditors: [(SplitPerson, Double)] = []
        for p in people {
            let bal = paid(by: p.id) - s
            if bal < -0.5 { debtors.append((p, -bal)) } else if bal > 0.5 { creditors.append((p, bal)) }
        }
        debtors.sort { $0.1 > $1.1 }
        creditors.sort { $0.1 > $1.1 }
        var out: [(from: SplitPerson, to: SplitPerson, amount: Double)] = []
        var i = 0, j = 0
        while i < debtors.count, j < creditors.count {
            let amount = min(debtors[i].1, creditors[j].1)
            if amount >= 0.5 { out.append((from: debtors[i].0, to: creditors[j].0, amount: amount)) }
            debtors[i].1 -= amount
            creditors[j].1 -= amount
            if debtors[i].1 < 0.5 { i += 1 }
            if creditors[j].1 < 0.5 { j += 1 }
        }
        return out
    }

    // MARK: editing

    func setCount(_ n: Int) {
        var list = people
        let target = max(1, min(n, 40))
        while list.count < target { list.append(SplitPerson()) }
        while list.count > target {
            let gone = list.removeLast()
            var ex = expenses
            for k in ex.indices where ex[k].payer == gone.id { ex[k].payer = nil }
            expenses = ex
        }
        people = list
    }

    func rename(_ id: UUID, _ name: String) {
        var list = people
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = name }
        people = list
    }

    func toggleSettled(_ id: UUID) {
        var list = people
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].settled.toggle() }
        people = list
    }

    /// Adds typed or pasted lines. A line without an amount («أملج:») starts a stop.
    /// Returns how many expenses were added.
    @discardableResult
    func addLines(_ text: String, currency: SplitCurrency, payer: UUID?) -> Int {
        var list = expenses
        var added = 0
        for line in SplitParser.parse(text) {
            switch line {
            case .stop(let s):
                currentStop = s
            case .expense(let amount, let cur, let note):
                list.append(SplitExpense(amount: amount, currency: cur ?? currency, note: note,
                                         stop: currentStop, payer: payer))
                added += 1
            }
        }
        expenses = list
        return added
    }

    func update(_ e: SplitExpense) {
        var list = expenses
        if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e }
        expenses = list
    }

    func remove(_ id: UUID) {
        expenses = expenses.filter { $0.id != id }
    }

    // MARK: sharing

    var summaryText: String {
        var lines = ["قطة «\(displayName)»",
                     "المجموع: \(SplitFormat.money(total)) ر.س",
                     "على كل واحد: \(SplitFormat.money(share.rounded())) ر.س (\(count) أشخاص)"]
        let cats = byCategory
        if !cats.isEmpty {
            lines.append("")
            lines.append("في إيش انصرف:")
            for c in cats { lines.append("• \(c.category.label): \(SplitFormat.money(c.amount))") }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - parsing typed lines

enum SplitParser {
    enum Line: Equatable {
        case stop(String)
        case expense(Double, SplitCurrency?, String)
    }

    static func normalize(_ s: String) -> String {
        var out = ""
        for ch in s {
            if let v = ch.wholeNumberValue, !ch.isASCII {
                out.append(Character(String(v)))
            } else if ch == "٫" {
                out.append(".")
            } else {
                out.append(ch)
            }
        }
        // 1,200 → 1200
        return out.replacingOccurrences(of: "(?<=\\d)[,٬](?=\\d{3}\\b)", with: "", options: .regularExpression)
    }

    static func parse(_ text: String) -> [Line] {
        text.components(separatedBy: .newlines).compactMap(parseLine)
    }

    static func parseLine(_ raw: String) -> Line? {
        var t = normalize(raw).trimmingCharacters(in: .whitespaces)
        let bullets = ["-", "•", "*", "◦", "▪", "–", "—"]
        while let b = bullets.first(where: { t.hasPrefix($0) }) {
            t = String(t.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !t.isEmpty else { return nil }

        guard let r = t.range(of: "\\d+(?:\\.\\d+)?", options: .regularExpression),
              let amount = Double(t[r]), amount > 0 else {
            let stop = t.trimmingCharacters(in: CharacterSet(charactersIn: ":：،,.- ").union(.whitespaces))
            return stop.isEmpty || stop.count > 40 ? nil : .stop(stop)
        }

        var rest = t
        rest.removeSubrange(r)
        var currency: SplitCurrency?
        for c in SplitCurrency.allCases {
            for w in c.words.sorted(by: { $0.count > $1.count }) where rest.contains(w) {
                if c != .sar || currency == nil { currency = c }
                rest = rest.replacingOccurrences(of: w, with: " ")
            }
        }
        let note = rest
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：،,.-=+ "))
        return .expense(amount, currency, note.isEmpty ? "مصروف" : note)
    }
}

enum SplitFormat {
    private static let f: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()

    static func money(_ v: Double) -> String {
        f.string(from: NSNumber(value: (v * 100).rounded() / 100)) ?? "\(v)"
    }

    static func amount(_ e: SplitExpense) -> String {
        e.currency == .sar ? money(e.amount) : "\(money(e.amount)) \(e.currency.symbol)"
    }
}
