import Foundation
import UserNotifications

/// Builds every reminder from scratch whenever something changes:
/// - عادي: one notification at the time
/// - مهم: the day before, then at the time, repeated 5 times every 30 minutes
/// - ضروري: a week before, the day before, at the time (repeated 4 times every 15 minutes), plus a real alarm
/// - every day: the morning brief and «وش صار اليوم؟» with a follow-up
///
/// iOS keeps at most 64 pending notifications per app, and only runs our code when the app is
/// opened, a notification button is pressed, or a background refresh is granted. So the budget is
/// filled by priority (each dated item's own alert first), and the last slot always holds a note
/// asking to open the app before the scheduled window runs out.
@MainActor
final class Scheduler {
    static let shared = Scheduler()
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?

    /// iOS keeps at most 64 pending notifications per app; one is kept for the «افتح دفتري» note.
    private let limit = 63

    /// What the last rebuild could and couldn't fit (shown in Settings › فحص التنبيهات).
    private(set) var lastScheduled = 0
    private(set) var lastDropped = 0
    private(set) var lastHorizon: Date?

    func rebuildSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await self.rebuild()
        }
    }

    /// Runs one rebuild at a time, so two quick rebuilds can't interleave and double the alarms.
    func rebuild() async {
        let previous = running
        let task = Task { @MainActor in
            await previous?.value
            await self.rebuildNow()
        }
        running = task
        await task.value
    }

    private enum Tier: Int { case own = 0, soon = 1, rest = 2 }

    private func rebuildNow() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let entries = Store.allEntries()
        let open = entries.filter { $0.isScheduledKind && $0.isOpen && $0.date != nil }
        let meds = Store.allMedicines()

        var all: [(Date, Tier, UNNotificationRequest)] = []
        for e in open { all += requests(for: e, now: now) }
        all += nagRequests(entries: entries, now: now).map { ($0.0, Tier.rest, $0.1) }
        all += packRequests(Store.allPackLists(), now: now).map { ($0.0, Tier.soon, $0.1) }
        all += medicineRequests(meds, now: now)
        all += dailyRequests(entries: entries, now: now)

        // Priority first, then time: every item's own alert and the next 24 hours never get crowded out.
        all.sort { a, b in a.1 != b.1 ? a.1.rawValue < b.1.rawValue : a.0 < b.0 }
        let kept = Array(all.prefix(limit))
        let dropped = all.dropFirst(limit)
        for (_, _, r) in kept { try? await center.add(r) }

        // The window ends at the first thing we couldn't fit, or at the last thing scheduled.
        let firstDropped = dropped.map { $0.0 }.min()
        let lastKept = kept.map { $0.0 }.max()
        var horizon = firstDropped ?? lastKept ?? DF.addDays(3, to: now)
        horizon = min(horizon, DF.addDays(7, to: now))
        lastScheduled = kept.count
        lastDropped = dropped.count
        lastHorizon = horizon
        if let note = DF.greg.date(bySettingHour: 21, minute: 0, second: 0, of: DF.addDays(-1, to: horizon)), note > now {
            try? await center.add(NotificationFactory.request(
                id: "keepalive", at: note, title: "افتح دفتري دقيقة",
                body: "عشان تستمر تذكيراتك وأدويتك في الأيام الجاية.",
                sensitive: true, category: "MORNING", uid: nil))
        }

        await clearStaleDelivered(entries: entries, meds: meds)
        await AlarmService.rebuild(entries: open, now: now)
        BackgroundRefresh.schedule()
    }

    /// Removes delivered notifications that no longer matter: done items, taken doses.
    private func clearStaleDelivered(entries: [Entry], meds: [Medicine]) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let openIDs = Set(entries.filter { $0.isOpen }.map { $0.uid.uuidString })
        let medByID = Dictionary(meds.map { ($0.uid.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var stale: [String] = []
        for n in delivered {
            let info = n.request.content.userInfo
            if let uid = info["uid"] as? String, !openIDs.contains(uid) {
                stale.append(n.request.identifier)
            } else if let med = info["med"] as? String, let slot = info["slot"] as? Int, let day = info["day"] as? String {
                if let m = medByID[med], m.takenKeys.contains("\(day)|\(slot)") { stale.append(n.request.identifier) }
                if medByID[med] == nil { stale.append(n.request.identifier) }
            }
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    /// For Settings › «فحص التنبيهات»: the next few alerts actually waiting in iOS.
    func upcoming(_ n: Int = 5) async -> [(Date, String)] {
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let list: [(Date, String)] = reqs.compactMap { r in
            guard let t = r.trigger as? UNCalendarNotificationTrigger, let d = t.nextTriggerDate() else { return nil }
            return (d, r.content.title)
        }
        return Array(list.sorted { $0.0 < $1.0 }.prefix(n))
    }

    func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    // MARK: - per item

    private func requests(for e: Entry, now: Date) -> [(Date, Tier, UNNotificationRequest)] {
        guard let anchor = e.anchorDate else { return [] }
        var out: [(Date, Tier, UNNotificationRequest)] = []
        let uid = e.uid.uuidString
        let when = e.hasTime ? DF.time(anchor) : "اليوم"

        func add(_ key: String, _ at: Date, _ title: String, _ body: String, sensitive: Bool) {
            guard at > now else { return }
            // The alert at the time (and a snooze) always fits; the extras come after.
            let tier: Tier = (key == "at" || key == "r0" || key == "snooze") ? .own
                : (at.timeIntervalSince(now) < 24 * 3600 ? .soon : .rest)
            out.append((at, tier, NotificationFactory.request(id: "\(uid)-\(key)", at: at, title: title, body: body,
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
                let body = k == 0 ? "مهم · \(when)" : "التذكير \(k + 1) من 5 — اضغط «تم» إذا خلصت"
                add("r\(k)", at, e.title, body, sensitive: true)
            }
        case .urgent:
            if let weekBefore, DF.daysBetween(now, anchor) > 7 {
                add("week", weekBefore, "بعد أسبوع: \(e.title)", "ضروري · \(DF.relativeDay(anchor, now: now))", sensitive: false)
            }
            if let dayBefore { add("eve", dayBefore, "بكرة: \(e.title)", "ضروري · \(when)", sensitive: true) }
            for k in 0..<4 {
                let at = anchor.addingTimeInterval(TimeInterval(k * 15 * 60))
                let body = k == 0 ? "ضروري · الآن" : "ما زال مفتوحاً (\(k + 1) من 4) — اضغط «تم» إذا خلصت"
                add("r\(k)", at, e.title, body, sensitive: true)
            }
        }

        if let snooze = e.snoozeUntil, snooze > now {
            add("snooze", snooze, e.title, "ذكّرتك مثل ما طلبت", sensitive: e.importance != .normal)
        }
        return out
    }

    // MARK: - medicines

    /// Dose alerts for up to 7 days (with one reminder 15 minutes later during the next 24 hours),
    /// plus a warning 3 days before the open pack expires and on the day itself.
    private func medicineRequests(_ meds: [Medicine], now: Date) -> [(Date, Tier, UNNotificationRequest)] {
        var out: [(Date, Tier, UNNotificationRequest)] = []
        let today = DF.startOfDay(now)

        func add(_ id: String, _ at: Date, _ title: String, _ body: String, info: [String: Any], category: String) {
            guard at > now else { return }
            let tier: Tier = at.timeIntervalSince(now) < 24 * 3600 ? .soon : .rest
            out.append((at, tier, NotificationFactory.request(id: id, at: at, title: title, body: body, sensitive: true,
                                                              category: category, uid: nil, extra: info)))
        }

        for m in meds {
            let uid = m.uid.uuidString
            let slots = m.slots
            for offset in 0..<7 {
                let day = DF.addDays(offset, to: today)
                guard m.isActive(on: day) else { continue }
                for (idx, slot) in slots.enumerated() where !m.taken(day, slot) {
                    let at = m.slotDate(day, slot)
                    let info: [String: Any] = ["med": uid, "slot": slot, "day": DF.dayKey(day)]
                    let note = m.doseNote.isEmpty ? "" : "\(m.doseNote) · "
                    add("dose-\(uid)-\(DF.dayKey(day))-\(slot)-0", at, "\(m.name) — وقت الجرعة",
                        "\(note)الجرعة \(idx + 1) من \(slots.count)", info: info, category: "DOSE")
                    if at.timeIntervalSince(now) < 24 * 3600 {
                        for k in 1...1 {
                            add("dose-\(uid)-\(DF.dayKey(day))-\(slot)-\(k)", at.addingTimeInterval(TimeInterval(k * 15 * 60)),
                                "\(m.name) — ما سجّلت الجرعة", "اضغط «أخذتها» إذا أخذتها", info: info, category: "DOSE")
                        }
                    }
                }
            }
            if let snooze = m.snoozeUntil, snooze > now, m.snoozeSlot >= 0 {
                add("dose-\(uid)-snooze", snooze, "\(m.name) — وقت الجرعة", "ذكّرتك بعد 15 دقيقة كما طلبت",
                    info: ["med": uid, "slot": m.snoozeSlot, "day": DF.dayKey(snooze)], category: "DOSE")
            }
            if let expiry = m.expiry, !m.courseFinished {
                let info: [String: Any] = ["med": uid]
                if let warn = DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: DF.addDays(-3, to: expiry)) {
                    add("exp-\(uid)-warn", warn, "\(m.name) تنتهي بعد 3 أيام", "جهّز علبة جديدة.", info: info, category: "MED")
                }
                if let end = DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: expiry) {
                    add("exp-\(uid)-end", end, "\(m.name) انتهت صلاحيتها اليوم", "ارمها وافتح علبة جديدة، واضغط «فتحت علبة جديدة».",
                        info: info, category: "MED")
                }
            }
        }
        return out
    }

    // MARK: - undated items («معلّقة»)

    /// The next three nudges for each undated item, at the nudge time, every N days until «تم».
    private func nagRequests(entries: [Entry], now: Date) -> [(Date, UNNotificationRequest)] {
        var out: [(Date, UNNotificationRequest)] = []
        for e in entries where e.isNagging {
            guard let first = e.nextNag(after: now) else { continue }
            let age = DF.daysBetween(e.createdAt, now)
            let since = age >= 2 ? "معلّقة من \(age == 2 ? "يومين" : DF.daysText(age)) · " : ""
            for k in 0..<3 {
                let at = DF.addDays(k * e.nagDays, to: first)
                out.append((at, NotificationFactory.request(
                    id: "nag-\(e.uid.uuidString)-\(k)", at: at, title: e.title,
                    body: "\(since)اضغط «تم» إذا خلصتها، أو «مو اليوم»",
                    sensitive: e.importance != .normal, category: "NAG", uid: e.uid.uuidString)))
            }
        }
        return out
    }

    // MARK: - packing lists («أغراضي»)

    /// The night before the trip (8:00 pm) and the trip morning, only while something is unticked.
    private func packRequests(_ lists: [PackList], now: Date) -> [(Date, UNNotificationRequest)] {
        var out: [(Date, UNNotificationRequest)] = []
        for l in lists {
            guard let trip = l.tripDate else { continue }
            let left = l.remaining
            guard !left.isEmpty else { continue }
            let day = DF.startOfDay(trip)
            let names = left.prefix(4).map(\.text).joined(separator: "، ")
            let more = left.count > 4 ? "…" : ""
            let info: [String: Any] = ["pack": l.uid.uuidString]
            if let eve = DF.greg.date(bySettingHour: 20, minute: 0, second: 0, of: DF.addDays(-1, to: day)), eve > now {
                out.append((eve, NotificationFactory.request(
                    id: "pack-\(l.uid.uuidString)-eve", at: eve, title: "بكرة طلعتك: \(l.displayName)",
                    body: "باقي \(left.count) من \(l.total): \(names)\(more)",
                    sensitive: true, category: "PACK", uid: nil, extra: info)))
            }
            let morning = day.addingTimeInterval(TimeInterval(Prefs.morningMinutes * 60))
            if morning > now {
                out.append((morning, NotificationFactory.request(
                    id: "pack-\(l.uid.uuidString)-day", at: morning, title: "اليوم طلعتك: \(l.displayName)",
                    body: "لا تنسى: \(names)\(more)",
                    sensitive: true, category: "PACK", uid: nil, extra: info)))
            }
        }
        return out
    }

    // MARK: - morning and evening

    private func dailyRequests(entries: [Entry], now: Date) -> [(Date, Tier, UNNotificationRequest)] {
        var out: [(Date, Tier, UNNotificationRequest)] = []
        func tier(_ d: Date) -> Tier { d.timeIntervalSince(now) < 36 * 3600 ? .soon : .rest }
        let today = DF.startOfDay(now)
        let morning = Prefs.morningMinutes
        let evening = Prefs.eveningMinutes
        let loggedToday = Prefs.lastEveningLog == DF.dayKey(now)

        for i in 0..<7 {
            let day = DF.addDays(i, to: today)
            let m = day.addingTimeInterval(TimeInterval(morning * 60))
            if m > now {
                out.append((m, tier(m), NotificationFactory.request(
                    id: "morning-\(i)", at: m,
                    title: "\(DF.greeting(m)) · \(DF.weekday(m))",
                    body: morningBody(day: day, entries: entries),
                    sensitive: true, category: "MORNING", uid: nil)))
            }
            let ev = day.addingTimeInterval(TimeInterval(evening * 60))
            if ev > now && !(i == 0 && loggedToday) {
                out.append((ev, tier(ev), NotificationFactory.request(
                    id: "evening-\(i)", at: ev, title: "وش صار اليوم؟",
                    body: "علّم على اللي صار، أو اكتب هنا مباشرة.",
                    sensitive: true, category: "EVENING", uid: nil)))
            }
            let follow = ev.addingTimeInterval(90 * 60)
            if follow > now && !(i == 0 && loggedToday) {
                out.append((follow, tier(follow), NotificationFactory.request(
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
        let doses = Store.allMedicines().filter { $0.isActive(on: day) }.reduce(0) { $0 + $1.slots.count }
        let pending = entries.filter(\.isPending).count
        let medsTail = (doses > 0 ? " · أدويتك: \(doses) جرعات" : "") + (pending > 0 ? " · معلّقة: \(pending)" : "")
        guard !items.isEmpty else {
            return (overdue > 0 ? "يومك فاضي من المواعيد، وعندك \(overdue) متأخرة." : "يومك فاضي من المواعيد.") + medsTail
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
        return prefix + list + tail + medsTail
    }
}

enum NotificationFactory {
    static func request(id: String, at: Date, title: String, body: String,
                        sensitive: Bool, category: String, uid: String?,
                        extra: [String: Any] = [:]) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        c.threadIdentifier = category
        if sensitive { c.interruptionLevel = .timeSensitive }
        var info = extra
        if let uid { info["uid"] = uid }
        if !info.isEmpty { c.userInfo = info }
        let comps = DF.greg.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        return UNNotificationRequest(identifier: id, content: c,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: "DONE", title: "تم", options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: "SNOOZE30", title: "ذكّرني بعد 30 دقيقة", options: [])
        let item = UNNotificationCategory(identifier: "ITEM", actions: [done, snooze], intentIdentifiers: [], options: [])
        let log = UNTextInputNotificationAction(identifier: "LOG", title: "اكتب وش صار", options: [],
                                                textInputButtonTitle: "حفظ", textInputPlaceholder: "وش صار اليوم؟")
        let open = UNNotificationAction(identifier: "OPEN", title: "افتح المراجعة", options: [.foreground])
        let evening = UNNotificationCategory(identifier: "EVENING", actions: [log, open], intentIdentifiers: [], options: [])
        let morning = UNNotificationCategory(identifier: "MORNING", actions: [], intentIdentifiers: [], options: [])
        let taken = UNNotificationAction(identifier: "TAKEN", title: "أخذتها", options: [.authenticationRequired])
        let snooze15 = UNNotificationAction(identifier: "SNOOZE15", title: "بعد 15 دقيقة", options: [])
        let dose = UNNotificationCategory(identifier: "DOSE", actions: [taken, snooze15], intentIdentifiers: [], options: [])
        let med = UNNotificationCategory(identifier: "MED", actions: [], intentIdentifiers: [], options: [])
        let notToday = UNNotificationAction(identifier: "NOTTODAY", title: "مو اليوم", options: [.authenticationRequired])
        let nag = UNNotificationCategory(identifier: "NAG", actions: [done, notToday], intentIdentifiers: [], options: [])
        let pack = UNNotificationCategory(identifier: "PACK", actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([item, evening, morning, dose, med, nag, pack])
    }

    static func sendTest(sensitive: Bool) async {
        let at = Date().addingTimeInterval(60)
        let r = request(id: "test-\(UUID().uuidString)", at: at, title: "تجربة التنبيه المهم",
                        body: "هكذا يوصلك «مهم»: يبقى على شاشة القفل، ويتجاوز وضع التركيز.",
                        sensitive: sensitive, category: "MORNING", uid: nil)
        try? await UNUserNotificationCenter.current().add(r)
    }
}
