import Foundation

/// Arabic date formatting with explicit calendars, so Hijri and Gregorian always print the same way
/// whatever the phone's region settings are.
enum DF {
    static let greg: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "ar")
        return c
    }()

    static let hijri: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.timeZone = .current
        c.locale = Locale(identifier: "ar")
        return c
    }()

    static let locale = Locale(identifier: "ar_SA@numbers=latn;calendar=gregorian")

    static let gregMonths = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                             "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    static let hijriMonths = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة",
                              "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    static let weekdays = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    static let shortWeekdays = ["أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]

    static var primary: Calendar { Prefs.hijriPrimary ? hijri : greg }
    static var secondary: Calendar { Prefs.hijriPrimary ? greg : hijri }

    static func isHijri(_ cal: Calendar) -> Bool { cal.identifier == .islamicUmmAlQura }

    static func monthName(_ month: Int, cal: Calendar) -> String {
        let names = isHijri(cal) ? hijriMonths : gregMonths
        return names[max(0, min(11, month - 1))]
    }

    static func weekday(_ d: Date) -> String {
        weekdays[greg.component(.weekday, from: d) - 1]
    }

    static func dayMonth(_ d: Date, cal: Calendar, year: Bool = true) -> String {
        let c = cal.dateComponents([.day, .month, .year], from: d)
        let base = "\(c.day ?? 1) \(monthName(c.month ?? 1, cal: cal))"
        return year ? "\(base) \(c.year ?? 0)" : base
    }

    static func hijriText(_ d: Date, year: Bool = true) -> String { dayMonth(d, cal: hijri, year: year) }
    static func gregText(_ d: Date, year: Bool = true) -> String { dayMonth(d, cal: greg, year: year) }

    /// "25 جمادى الأولى 1448 · 5 نوفمبر 2026" (primary calendar first)
    static func fullDate(_ d: Date, year: Bool = true) -> String {
        "\(dayMonth(d, cal: primary, year: year)) · \(dayMonth(d, cal: secondary, year: year))"
    }

    static func time(_ d: Date) -> String {
        let c = greg.dateComponents([.hour, .minute], from: d)
        let h24 = c.hour ?? 0
        let m = c.minute ?? 0
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d %@", h12, m, h24 < 12 ? "ص" : "م")
    }

    static func greeting(_ d: Date) -> String {
        let h = greg.component(.hour, from: d)
        return h < 12 ? "صباح الخير" : "مساء الخير"
    }

    static func dayKey(_ d: Date) -> String {
        let c = greg.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func startOfDay(_ d: Date) -> Date { greg.startOfDay(for: d) }

    static func addDays(_ n: Int, to d: Date) -> Date {
        greg.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        greg.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }

    static func daysText(_ n: Int) -> String {
        switch n {
        case 1: return "يوم"
        case 2: return "يومان"
        case 3...10: return "\(n) أيام"
        default: return "\(n) يوماً"
        }
    }

    /// "اليوم" / "بكرة" / "أمس" / "الخميس 25 جمادى الأولى"
    static func relativeDay(_ d: Date, now: Date = Date()) -> String {
        switch daysBetween(now, d) {
        case 0: return "اليوم"
        case 1: return "بكرة"
        case -1: return "أمس"
        default: return "\(weekday(d)) \(dayMonth(d, cal: primary, year: false))"
        }
    }

    static func whenText(_ d: Date, hasTime: Bool, now: Date = Date()) -> String {
        let day = relativeDay(d, now: now)
        return hasTime ? "\(day) · \(time(d))" : day
    }

    /// Big number and small unit for the countdown on the "next" card.
    static func countdown(to d: Date, now: Date = Date()) -> (big: String, small: String) {
        let s = Int(d.timeIntervalSince(now))
        if s <= 0 { return ("الآن", "") }
        let m = Int((Double(s) / 60).rounded(.up))
        if m < 60 { return ("\(m)", "دقيقة باقية") }
        if m < 24 * 60 { return (String(format: "%d:%02d", m / 60, m % 60), "ساعة باقية") }
        let days = daysBetween(now, d)
        if days <= 1 { return ("بكرة", "") }
        return ("\(days)", days <= 10 ? "أيام" : "يوماً")
    }
}
