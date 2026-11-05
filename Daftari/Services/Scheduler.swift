import Foundation
import UserNotifications

/// Builds every reminder from scratch whenever something changes:
/// - عادي: one notification at the time
/// - مهم: the day before, then at the time, repeating every 30 minutes until «تم»
/// - ضروري: a week before, the day before, at the time (repeating), plus a real alarm
/// - every day: the 8:00 morning brief and the 8:00 pm «وش صار اليوم؟» with a follow-up
@MainActor
final class Scheduler {
    static let shared = Scheduler()
    private var pending: Task<Void, Never>?

    /// iOS keeps at most 64 pending notifications per app.
    private let limit = 62

    func rebuildSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await self.rebuild()
        }
    }

    func rebuild() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let entries = Store.allEntries()
        let open = entries.filter { $0.isScheduledKind && $0.isOpen && $0.date != nil }

        var itemRequests: [(Date, UNNotificationRequest)] = []
        for e in open { itemRequests += requests(for: e, now: now) }
        itemRequests.sort { $0.0 < $1.0 }

        let daily = dailyRequests(entries: entries, now: now)
        let budget = max(0, limit - daily.count)
        for (_, r) in itemRequests.prefix(budget) { try? await center.add(r) }
        for (_, r) in daily { try? await center.add(r) }

        await AlarmService.rebuild(entries: open, now: now)
    }

    // MARK: - per item

    private func requests(for e: Entry, now: Date) -> [(Date, UNNotificationRequest)] {
        guard let anchor = e.anchorDate else { return [] }
        var out: [(Date, UNNotificationRequest)] = []
        let uid = e.uid.uuidString
        let when = e.hasTime ? DF.time(anchor) : "اليوم"

        func add(_ key: String, _ at: Date, _ title: String, _ body: String, sensitive: Bool) {
            guard at > now else { return }
            out.append((at, NotificationFactory.request(id: "\(uid)-\(key)", at: at, title: title, body: body,
                                                        sensitive: sensitive, category: "ITEM", uid: uid)))
        }

        let dayBefore = DF.greg.date(bySettingHour: 20, minute: 0, second: 0, of: DF.addDays(-1, to: anchor))
        let weekBefore = DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: DF.addDays(-7, to: anchor))

        switch e.importance {
        case .normal:
            if e.hasTime { add("at", anchor, e.title, "الآن · \(when)", sensitive: false) }
        case .important:
            if let dayBefore { add("eve", dayBefore, "بكرة: \(e.title)", "مهم · \(when)", sensitive: true) }
            for k in 0..<5 {
                let at = anchor.addingTimeInterval(TimeInterval(k * 30 * 60))
                let body = k == 0 ? "مهم · \(when)" : "التذكير \(k + 1) — اضغط «تم» إذا خلصت"
                add("r\(k)", at, e.title, body, sensitive: true)
            }
        case .urgent:
            if let weekBefore, DF.daysBetween(now, anchor) > 7 {
                add("week", weekBefore, "بعد أسبوع: \(e.title)", "ضروري · \(DF.relativeDay(anchor, now: now))", sensitive: false)
            }
            if let dayBefore { add("eve", dayBefore, "بكرة: \(e.title)", "ضروري · \(when)", sensitive: true) }
            for k in 0..<4 {
                let at = anchor.addingTimeInterval(TimeInterval(k * 15 * 60))
                let body = k == 0 ? "ضروري · الآن" : "ما زال مفتوحاً — اضغط «تم» إذا خلصت"
                add("r\(k)", at, e.title, body, sensitive: true)
            }
        }

        if let snooze = e.snoozeUntil, snooze > now {
            add("snooze", snooze, e.title, "ذكّرتك بعد 30 دقيقة كما طلبت", sensitive: e.importance != .normal)
        }
        return out
    }

    // MARK: - morning and evening

    private func dailyRequests(entries: [Entry], now: Date) -> [(Date, UNNotificationRequest)] {
        var out: [(Date, UNNotificationRequest)] = []
        let today = DF.startOfDay(now)
        let morning = Prefs.morningMinutes
        let evening = Prefs.eveningMinutes
        let loggedToday = Prefs.lastEveningLog == DF.dayKey(now)

        for i in 0..<7 {
            let day = DF.addDays(i, to: today)
            let m = day.addingTimeInterval(TimeInterval(morning * 60))
            if m > now {
                out.append((m, NotificationFactory.request(
                    id: "morning-\(i)", at: m,
                    title: "\(DF.greeting(m)) · \(DF.weekday(m))",
                    body: morningBody(day: day, entries: entries),
                    sensitive: true, category: "MORNING", uid: nil)))
            }
            let ev = day.addingTimeInterval(TimeInterval(evening * 60))
            if ev > now && !(i == 0 && loggedToday) {
                out.append((ev, NotificationFactory.request(
                    id: "evening-\(i)", at: ev, title: "وش صار اليوم؟",
                    body: "علّم على اللي صار، أو اكتب هنا مباشرة.",
                    sensitive: true, category: "EVENING", uid: nil)))
            }
            let follow = ev.addingTimeInterval(90 * 60)
            if follow > now && !(i == 0 && loggedToday) {
                out.append((follow, NotificationFactory.request(
                    id: "evening-follow-\(i)", at: follow, title: "ما سجّلت يومك",
                    body: "دقيقة وحدة: وش صار اليوم؟",
                    sensitive: true, category: "EVENING", uid: nil)))
            }
        }
        return out
    }

    private func morningBody(day: Date, entries: [Entry]) -> String {
        let items = Agenda.items(on: day, entries: entries, includeClosed: false)
        let overdue = DF.daysBetween(Date(), day) == 0 ? Agenda.overdue(entries: entries).count : 0
        guard !items.isEmpty else {
            return overdue > 0 ? "يومك فاضي من المواعيد، وعندك \(overdue) متأخرة." : "يومك فاضي من المواعيد. أضف أي شيء ببالك."
        }
        let urgent = items.filter { $0.importance == .urgent }.count
        let important = items.filter { $0.importance == .important }.count
        var head: [String] = []
        if urgent > 0 { head.append("\(urgent) ضروري") }
        if important > 0 { head.append("\(important) مهم") }
        let list = items.prefix(3).map { i -> String in
            if let d = i.date, i.hasTime { return "\(i.title) \(DF.time(d))" }
            return i.title
        }.joined(separator: "، ")
        let prefix = head.isEmpty ? "عندك \(items.count): " : "عندك \(head.joined(separator: " و")): "
        let tail = overdue > 0 ? " · \(overdue) متأخرة" : ""
        return prefix + list + tail
    }
}

enum NotificationFactory {
    static func request(id: String, at: Date, title: String, body: String,
                        sensitive: Bool, category: String, uid: String?) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        c.threadIdentifier = category
        if sensitive { c.interruptionLevel = .timeSensitive }
        if let uid { c.userInfo = ["uid": uid] }
        let comps = DF.greg.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        return UNNotificationRequest(identifier: id, content: c,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: "تم", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE30", title: "ذكّرني بعد 30 دقيقة", options: [])
        let item = UNNotificationCategory(identifier: "ITEM", actions: [done, snooze], intentIdentifiers: [], options: [])
        let log = UNTextInputNotificationAction(identifier: "LOG", title: "اكتب وش صار", options: [],
                                                textInputButtonTitle: "حفظ", textInputPlaceholder: "وش صار اليوم؟")
        let open = UNNotificationAction(identifier: "OPEN", title: "افتح المراجعة", options: [.foreground])
        let evening = UNNotificationCategory(identifier: "EVENING", actions: [log, open], intentIdentifiers: [], options: [])
        let morning = UNNotificationCategory(identifier: "MORNING", actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([item, evening, morning])
    }

    static func sendTest(sensitive: Bool) async {
        let at = Date().addingTimeInterval(60)
        let r = request(id: "test-\(UUID().uuidString)", at: at, title: "تجربة التنبيه المهم",
                        body: "هكذا يوصلك «مهم»: يبقى على شاشة القفل، ويتجاوز وضع التركيز.",
                        sensitive: sensitive, category: "MORNING", uid: nil)
        try? await UNUserNotificationCenter.current().add(r)
    }
}
