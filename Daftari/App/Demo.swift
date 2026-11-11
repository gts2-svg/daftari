#if DEBUG
import Foundation
import SwiftData

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
        case "things", "meds": app.tab = 3
        case "medadd": app.tab = 3; app.open(.medicine(nil))
        case "add": app.open(.add(prefill: "موعد الأسنان الثلاثاء الجاي 4 العصر", date: nil, kind: nil))
        case "voice": app.open(.voice(.idea))
        case "evening": app.open(.evening)
        case "morning": app.open(.morning)
        case "settings": app.open(.settings)
        case "packs": app.thingsSection = 1; app.tab = 3
        case "pack":
            app.thingsSection = 1; app.tab = 3
            try? await Task.sleep(nanoseconds: 500_000_000)
            app.openPack = Store.allPackLists().first?.uid
        case "nag": app.open(.add(prefill: "تغيير زيت السيارة", date: nil, kind: .task))
        case "splits":
            UserDefaults.standard.set(1, forKey: "packSub")
            app.thingsSection = 1; app.tab = 3
        case "split", "splitpdf", "split2", "split-nodash", "split-nolist", "split-noentry":
            UserDefaults.standard.set(1, forKey: "packSub")
            app.thingsSection = 1; app.tab = 3
            try? await Task.sleep(nanoseconds: 500_000_000)
            let trips = (try? Store.context.fetch(FetchDescriptor<SplitTrip>())) ?? []
            let name = screen == "split2" ? "مدريد" : "سفرة الشمال"
            app.openSplit = trips.first { $0.name == name }?.uid
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

        let m1 = Medicine(name: "قطرة العين")
        m1.openedAt = DF.addDays(-27, to: today)
        m1.shelfDays = 30
        m1.doseMinutes = [8 * 60, 14 * 60, 22 * 60]
        m1.doseNote = "قطرة وحدة في كل عين"
        m1.setTaken(key: Medicine.key(now, 8 * 60), true)
        let m2 = Medicine(name: "قطرة ثانية")
        m2.openedAt = DF.addDays(-7, to: today)
        m2.shelfDays = 30
        m2.doseMinutes = [9 * 60, 21 * 60]
        m2.setTaken(key: Medicine.key(now, 9 * 60), true)
        ctx.insert(m1)
        ctx.insert(m2)

        let oil = Entry(title: "تغيير زيت السيارة", kind: .task)
        oil.nagDays = 3
        oil.nagNext = DF.addDays(1, to: today)
        oil.createdAt = DF.addDays(-4, to: now)
        ctx.insert(oil)
        let gift = Entry(title: "أشتري هدية لأبو إبراهيم", kind: .task)
        gift.nagDays = 7
        ctx.insert(gift)

        let trip = PackList(name: "البر")
        trip.add("عزبة الطبخ أبو راجح والوجار\nعزبة القهوة والشاهي\nأكياس النوم\nشاخوف\nعلاجك عندي\nكشاف\nلمبة\nشاحني\nملابسي (ثيرمل، قبوع، قفاز، شراب، فروة)\nآيباد")
        trip.toggle(trip.items[0].id)
        trip.toggle(trip.items[2].id)
        trip.toggle(trip.items[5].id)
        trip.tripDate = DF.addDays(3, to: today)
        ctx.insert(trip)
        let travel = PackList(name: "السفر")
        travel.add("الجواز\nالشاحن\nأدويتي")
        ctx.insert(travel)

        let north = SplitTrip(name: "سفرة الشمال")
        north.setCount(4)
        let np = north.people
        north.rename(np[1].id, "سعد")
        north.rename(np[2].id, "فهد")
        north.rename(np[3].id, "ناصر")
        north.toggleSettled(np[1].id)
        north.addLines("مكة:\nبقالة 44\nبنزين 128\n\nأملج:\n84 عشاء\n141 بنزين\n44 بقالة\n35 قهوة\n\nضباء\n276 سكن\n6 ماء",
                       currency: .sar, payer: nil)
        ctx.insert(north)

        let madrid = SplitTrip(name: "مدريد")
        madrid.mode = .everyone
        madrid.setCount(3)
        let mp = madrid.people
        madrid.rename(mp[1].id, "سعد")
        madrid.rename(mp[2].id, "فهد")
        madrid.addLines("1450 فندق", currency: .sar, payer: mp[0].id)
        madrid.addLines("85 يورو عشاء\nتاكسي 30 €", currency: .sar, payer: mp[1].id)
        madrid.addLines("قهوة 12", currency: .eur, payer: mp[2].id)
        ctx.insert(madrid)
        try? ctx.save()
    }
}
#endif
