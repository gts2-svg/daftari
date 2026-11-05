#if DEBUG
import Foundation

/// Sample data and screen routing used only for screenshots on the build machine (debug builds).
@MainActor
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-screen"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static let transcript = "بكرة بعد الدوام أمرّ المغسلة وآخذ الثياب، وأحجز موعد صيانة السيارة"

    static func run() async {
        seedIfNeeded()
        try? await Task.sleep(nanoseconds: 700_000_000)
        let app = AppState.shared
        switch screen {
        case "calendar": app.tab = 1
        case "ideas": app.tab = 2
        case "things": app.tab = 3
        case "add": app.open(.add(prefill: "موعد الأسنان الثلاثاء الجاي 4 العصر", date: nil, kind: nil))
        case "voice": app.open(.voice(.idea))
        case "evening": app.open(.evening)
        case "morning": app.open(.morning)
        case "settings": app.open(.settings)
        default: app.tab = 0
        }
    }

    private static func seedIfNeeded() {
        guard Store.allEntries().isEmpty else { return }
        let ctx = Store.context
        let now = Date()
        func at(_ minutes: Int) -> Date {
            let d = now.addingTimeInterval(TimeInterval(minutes * 60))
            let c = DF.greg.dateComponents([.minute], from: d)
            return d.addingTimeInterval(TimeInterval(-((c.minute ?? 0) % 15) * 60))
        }
        let today = DF.startOfDay(now)

        ctx.insert(Entry(title: "جلسة مرئية — الدائرة المرورية العاشرة", kind: .appointment,
                         date: at(135), hasTime: true, importance: .urgent))
        ctx.insert(Entry(title: "مراجعة مسودة الحكم", kind: .task,
                         date: at(200), hasTime: true, importance: .important))
        ctx.insert(Entry(title: "موعد الأسنان", kind: .appointment,
                         date: at(330), hasTime: true, importance: .urgent))
        ctx.insert(Entry(title: "اتصال لتأكيد الحجز", kind: .task, date: today, hasTime: false))
        ctx.insert(Entry(title: "تجديد الاستمارة", kind: .task, date: DF.addDays(-1, to: today),
                         hasTime: false, importance: .important))
        ctx.insert(Entry(title: "اجتماع الدائرة الأسبوعي", kind: .appointment,
                         date: DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: DF.addDays(3, to: today)),
                         hasTime: true, importance: .important))
        ctx.insert(Entry(title: "عزيمة الأهل", kind: .appointment,
                         date: DF.greg.date(bySettingHour: 20, minute: 30, second: 0, of: DF.addDays(9, to: today)),
                         hasTime: true))

        let i1 = Entry(title: "فكرة لبحث خولان: فصل عن المساكن القديمة مع خرائط", kind: .idea)
        i1.createdAt = now.addingTimeInterval(-3600)
        let i2 = Entry(title: "أسأل عن عروض صيانة المكيفات قبل الصيف", kind: .idea)
        i2.createdAt = now.addingTimeInterval(-26 * 3600)
        let j1 = Entry(title: "خلصت الجلسات بدري، وراجعت ملفين، والعصر مشوار مع العيال", kind: .journal)
        j1.createdAt = now.addingTimeInterval(-25 * 3600)
        [i1, i2, j1].forEach { ctx.insert($0) }
        try? ctx.save()
    }
}
#endif
