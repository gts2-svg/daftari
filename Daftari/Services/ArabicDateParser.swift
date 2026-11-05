import Foundation

struct ParsedInput {
    var title: String
    var date: Date?
    var hasTime: Bool
    var kind: EntryKind
}

/// Understands everyday Saudi phrasing such as
/// «موعد الأسنان الثلاثاء الجاي 4 العصر» or «بكرة الساعة 9 ونص» or «15 جمادى الآخرة».
enum ArabicDateParser {
    private static let B = "(?<![\\p{L}\\p{N}])"
    private static let E = "(?![\\p{L}\\p{N}])"

    /// Converts Arabic-Indic digits and drops tashkeel / tatweel. Output length can differ from input.
    static func clean(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0660...0x0669).contains(v) { out.append(String(v - 0x0660)); continue }
            if (0x06F0...0x06F9).contains(v) { out.append(String(v - 0x06F0)); continue }
            if (0x064B...0x0652).contains(v) || v == 0x0640 { continue }
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// One-to-one letter folding (keeps UTF-16 offsets identical).
    static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x0623, 0x0625, 0x0622: out.append(Unicode.Scalar(0x0627)!) // أ إ آ → ا
            case 0x0629: out.append(Unicode.Scalar(0x0647)!)                 // ة → ه
            case 0x0649: out.append(Unicode.Scalar(0x064A)!)                 // ى → ي
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    private final class Scan {
        let norm: NSString
        var taken: [NSRange] = []
        init(_ s: String) { norm = s as NSString }

        func find(_ pattern: String, accept: (NSTextCheckingResult) -> Bool = { _ in true }) -> NSTextCheckingResult? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            let all = re.matches(in: norm as String, range: NSRange(location: 0, length: norm.length))
            for m in all where m.range.length > 0 {
                if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                if accept(m) { return m }
            }
            return nil
        }

        func g(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            guard i < m.numberOfRanges else { return nil }
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : norm.substring(with: r)
        }

        func take(_ m: NSTextCheckingResult) { taken.append(m.range) }
    }

    private static let weekdayStems: [(String, Int)] = [
        ("احد", 1), ("اثنين", 2), ("ثلاثاء", 3), ("ثلاثا", 3), ("اربعاء", 4), ("اربعا", 4),
        ("خميس", 5), ("جمعه", 6), ("سبت", 7)
    ]

    private static let hijriNames: [(String, Int)] = [
        ("محرم", 1), ("صفر", 2), ("ربيع الاول", 3), ("ربيع الاخر", 4), ("ربيع الثاني", 4),
        ("جمادي الاولي", 5), ("جمادي الاول", 5), ("جمادي الاخره", 6), ("جمادي الاخر", 6), ("جمادي الثانيه", 6),
        ("رجب", 7), ("شعبان", 8), ("رمضان", 9), ("شوال", 10),
        ("ذو القعده", 11), ("ذي القعده", 11), ("ذو الحجه", 12), ("ذي الحجه", 12)
    ]

    private static let gregNames: [(String, Int)] = [
        ("يناير", 1), ("فبراير", 2), ("مارس", 3), ("ابريل", 4), ("مايو", 5), ("يونيو", 6),
        ("يوليو", 7), ("اغسطس", 8), ("سبتمبر", 9), ("اكتوبر", 10), ("نوفمبر", 11), ("ديسمبر", 12)
    ]

    private static let amWords: Set<String> = ["الصبح", "صباحا", "الصباح", "الفجر", "ص"]
    private static let pmWords: Set<String> = ["العصر", "عصرا", "المغرب", "العشا", "العشاء", "المسا", "المساء",
                                               "مساء", "مساءا", "بالليل", "الليل", "ليلا", "م"]
    private static let noonWords: Set<String> = ["الظهر", "ظهرا"]

    static func parse(_ raw: String, now: Date = Date()) -> ParsedInput {
        let cleaned = clean(raw)
        let scan = Scan(fold(cleaned))
        let cal = DF.greg
        let today = cal.startOfDay(for: now)

        var day: Date?
        var hm: (Int, Int)?
        var absolute: Date?

        // 1) «بعد ساعتين» / «بعد 20 دقيقه»
        if let m = scan.find(B + "بعد\\s+(\\d+)?\\s*(دقيقه|دقايق|دقائق|ساعه|ساعات|ساعتين|نص ساعه)" + E) {
            let n = Int(scan.g(m, 1) ?? "") ?? 1
            let unit = scan.g(m, 2) ?? ""
            var minutes = n
            if unit == "ساعتين" { minutes = 120 }
            else if unit == "نص ساعه" { minutes = 30 }
            else if unit.hasPrefix("ساع") { minutes = n * 60 }
            absolute = now.addingTimeInterval(TimeInterval(minutes * 60))
            scan.take(m)
        }

        // 2) the day
        if absolute == nil {
            if let m = scan.find(B + "بعد\\s+بكره" + E) {
                day = DF.addDays(2, to: today); scan.take(m)
            } else if let m = scan.find(B + "(بكره|غدا|باكر)" + E) {
                day = DF.addDays(1, to: today); scan.take(m)
            } else if let m = scan.find(B + "بعد\\s+(\\d+)\\s*(يوم|ايام)" + E) {
                day = DF.addDays(Int(scan.g(m, 1) ?? "") ?? 1, to: today); scan.take(m)
            } else if let m = scan.find(B + "اليوم" + E) {
                day = today; scan.take(m)
            }

            if day == nil {
                let stems = weekdayStems.map { $0.0 }.joined(separator: "|")
                let pattern = B + "(?:يوم\\s+)?(?:ال)?(" + stems + ")" + E + "(?:\\s+(?:الجاي|الجايه|القادم|القادمه))?"
                if let m = scan.find(pattern), let stem = scan.g(m, 1),
                   let target = weekdayStems.first(where: { $0.0 == stem })?.1 {
                    let wd = cal.component(.weekday, from: today)
                    var diff = (target - wd + 7) % 7
                    if diff == 0 { diff = 7 }
                    day = DF.addDays(diff, to: today)
                    scan.take(m)
                }
            }

            if day == nil {
                for (names, calendar) in [(hijriNames, DF.hijri), (gregNames, DF.greg)] {
                    let alt = names.map { $0.0.replacingOccurrences(of: " ", with: "\\s+") }.joined(separator: "|")
                    let pattern = B + "(\\d{1,2})\\s+(?:من\\s+)?(" + alt + ")" + E
                    if let m = scan.find(pattern), let dStr = scan.g(m, 1), let dNum = Int(dStr), let name = scan.g(m, 2) {
                        let flat = name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        if let month = names.first(where: { $0.0 == flat })?.1,
                           let found = calendar.nextDate(after: today.addingTimeInterval(-1),
                                                          matching: DateComponents(month: month, day: dNum),
                                                          matchingPolicy: .nextTime) {
                            day = cal.startOfDay(for: found)
                            scan.take(m)
                            break
                        }
                    }
                }
            }

            // 3) the time
            let periods = (amWords.union(pmWords).union(noonWords)).sorted { $0.count > $1.count }.joined(separator: "|")
            let timePattern = B + "(الساعه\\s*)?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(ونص|و\\s*نص|وربع|الا\\s*ربع|وثلث|الا\\s*ثلث)?\\s*(" + periods + ")?" + E
            let dayFound = day != nil
            if let m = scan.find(timePattern, accept: { m in
                let r = m.range(at: 2)
                let n = Int((scan.norm.substring(with: r))) ?? 99
                guard n >= 0 && n <= 23 else { return false }
                let hasPrefix = m.range(at: 1).location != NSNotFound
                let hasMin = m.range(at: 3).location != NSNotFound
                let hasFrac = m.range(at: 4).location != NSNotFound
                let hasPeriod = m.range(at: 5).location != NSNotFound
                return hasPrefix || hasMin || hasFrac || hasPeriod || (dayFound && n >= 1 && n <= 12)
            }) {
                var h = Int(scan.g(m, 2) ?? "") ?? 9
                var minute = Int(scan.g(m, 3) ?? "") ?? 0
                let frac = (scan.g(m, 4) ?? "").replacingOccurrences(of: " ", with: "")
                switch frac {
                case "ونص", "ونص ": minute = 30
                case "وربع": minute = 15
                case "وثلث": minute = 20
                case "الاربع": minute = 45; h -= 1
                case "الاثلث": minute = 40; h -= 1
                default: break
                }
                if h < 0 { h += 12 }
                let period = scan.g(m, 5) ?? ""
                if amWords.contains(period) {
                    if h == 12 { h = 0 }
                } else if pmWords.contains(period) {
                    if h < 12 { h += 12 }
                } else if noonWords.contains(period) {
                    if h <= 4 { h += 12 }
                } else if h <= 23 && h < 13 {
                    if h >= 1 && h <= 6 { h += 12 }
                }
                hm = (min(h, 23), min(minute, 59))
                scan.take(m)
            } else if let m = scan.find(B + "(الصبح|الظهر|العصر|المغرب|العشا|العشاء|بالليل|الليل)" + E) {
                switch scan.g(m, 1) ?? "" {
                case "الصبح": hm = (8, 0)
                case "الظهر": hm = (12, 30)
                case "العصر": hm = (16, 0)
                case "المغرب": hm = (18, 0)
                case "العشا", "العشاء": hm = (20, 0)
                default: hm = (21, 0)
                }
                scan.take(m)
            }
        }

        var date: Date?
        var hasTime = false
        if let absolute {
            date = absolute
            hasTime = true
        } else if let hm {
            let (h, mi) = hm
            let base = day ?? today
            var dt = cal.date(bySettingHour: h, minute: mi, second: 0, of: base) ?? base
            if day == nil && dt <= now { dt = DF.addDays(1, to: dt) }
            date = dt
            hasTime = true
        } else if let day {
            date = day
        }

        // title = the text without the date words
        // fold() keeps UTF-16 offsets, so ranges found in the folded text apply to the cleaned text.
        let title = NSMutableString(string: cleaned)
        for r in scan.taken.sorted(by: { $0.location > $1.location }) {
            title.replaceCharacters(in: r, with: " ")
        }
        var t = (title as String)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "،,.")))
        for tail in [" في", " يوم", " الساعة", " الساعه"] where t.hasSuffix(tail) {
            t = String(t.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
        }
        if t.isEmpty { t = raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        let folded = fold(cleaned)
        let appointmentWords = ["موعد", "اجتماع", "جلسه", "مقابله", "زياره", "عزيمه", "مناسبه", "حفله", "دكتور", "مستشفي", "رحله", "سفر", "عرس", "زواج"]
        let kind: EntryKind = appointmentWords.contains(where: { folded.contains($0) }) ? .appointment : .task

        return ParsedInput(title: t, date: date, hasTime: hasTime, kind: kind)
    }
}
