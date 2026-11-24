import SwiftUI
import SwiftData

/// Which part of life the home screen shows.
enum HomeFilter: Int, CaseIterable {
    case all = 0, work = 1, home = 2
    var label: String {
        switch self {
        case .all: return "الكل"
        case .work: return "الشغل"
        case .home: return "البيت"
        }
    }
}

/// «اليوم» — calm: the important appointment in a small red box, anything that can't
/// wait pinned on top, and everything else folded into sections you open when you want.
struct TodayView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query(sort: \Medicine.createdAt) private var meds: [Medicine]
    @Query(sort: \Period.start) private var periods: [Period]
    @ObservedObject private var app = AppState.shared
    @State private var showTasks = false
    @State private var showSearch = false
    @AppStorage(Prefs.Key.evening) private var eveningMinutes = 20 * 60
    @AppStorage(Prefs.Key.lastEveningLog) private var lastEveningLog = ""
    @AppStorage("homeFilter") private var filterRaw = 0
    @AppStorage("homeOpen") private var openID = "appts"

    private var filter: HomeFilter { HomeFilter(rawValue: filterRaw) ?? .all }

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(now: context.date)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(T.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showTasks) { TasksListView() }
            .navigationDestination(isPresented: $showSearch) { SearchAllView() }
        }
    }

    private func shows(_ e: Entry) -> Bool {
        switch filter {
        case .all: return true
        case .work: return e.isWork
        case .home: return !e.isWork
        }
    }

    /// Running now, or starting within two weeks.
    private func homePeriods(now: Date) -> [Period] {
        periods.filter { p in
            switch filter {
            case .all: break
            case .work: if !p.isWork { return false }
            case .home: if p.isWork { return false }
            }
            switch p.status(now) {
            case .running: return true
            case .upcoming(let n): return n <= 14
            case .finished: return false
            }
        }
        .sorted { a, b in
            a.importanceRaw != b.importanceRaw ? a.importanceRaw > b.importanceRaw : a.startDay < b.startDay
        }
    }

    private func shows(_ item: DayItem) -> Bool {
        if let e = item.entry { return shows(e) }
        switch filter {
        case .all: return true
        case .work: return ArabicDateParser.looksLikeWork(item.title)
        case .home: return !ArabicDateParser.looksLikeWork(item.title)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let mine = entries.filter(shows)
        let todayAll = Agenda.items(on: now, entries: mine).filter(shows)
        let todayOpen = todayAll.filter { !$0.isDone }
        let doneToday = todayAll.filter(\.isDone)
        let overdue = Agenda.overdue(entries: mine, now: now)
        // Never folded: anything «ضروري» that is due today or late — shown once, on top, and not again below.
        let pinned = (overdue.map(DayItem.init(entry:)) + todayOpen).filter { $0.importance == .urgent }
        let pinnedIDs = Set(pinned.map(\.id))
        let appts = todayOpen.filter { $0.isAppointment && !pinnedIDs.contains($0.id) }
        let tasks = (overdue.map(DayItem.init(entry:)) + todayOpen.filter { !$0.isAppointment })
            .filter { !pinnedIDs.contains($0.id) }
        let overdueLeft = overdue.filter { !pinnedIDs.contains($0.uid.uuidString) }
        let pending = mine.filter(\.isPending)
        let activeMeds = filter == .work ? [] : meds.filter { !$0.courseFinished && $0.isActive(on: now) && !$0.slots.isEmpty }
        let dosesLeft = activeMeds.reduce(0) { $0 + $1.slots.count - $1.takenCount(on: now) }
        // And a dose that is late by under 3 hours.
        let lateDoses = meds.filter { !$0.courseFinished }.flatMap { m in
            m.slots.filter { m.state(now, $0, now: now) == .late && now.timeIntervalSince(m.slotDate(now, $0)) < 3 * 3600 }
                .map { (m, $0) }
        }
        let needsAlarm = entries.contains { $0.isScheduledKind && $0.isOpen && $0.date != nil && $0.importance != .normal }

        VStack(alignment: .leading, spacing: 14) {
            header(now: now)
            filterBar
            let nowPeriods = homePeriods(now: now)
            if !nowPeriods.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(nowPeriods.enumerated()), id: \.element.uid) { idx, p in
                        if idx > 0 { Divider().overlay(T.line).padding(.leading, 16) }
                        PeriodRow(period: p, now: now)
                    }
                }
                .padding(.vertical, 2)
                .card()
            }
            if needsAlarm && !AlarmService.isAuthorized { AlarmOffBanner() }
            if showEveningPrompt(now: now) { eveningPrompt }
            if let big = importantNext(after: now, entries: mine.filter { !pinnedIDs.contains($0.uid.uuidString) }) {
                ImportantBox(item: big, now: now)
            }

            if !pinned.isEmpty || !lateDoses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("لا تفوّتها").font(.dyn(15, weight: .bold)).foregroundStyle(T.urgentInk)
                    VStack(spacing: 0) {
                        ForEach(Array(pinned.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { Divider().overlay(T.line).padding(.leading, 60) }
                            ItemRow(item: item, showDay: true)
                        }
                        ForEach(Array(lateDoses.enumerated()), id: \.offset) { idx, pair in
                            if idx > 0 || !pinned.isEmpty { Divider().overlay(T.line).padding(.leading, 16) }
                            LateDoseRow(med: pair.0, slot: pair.1, now: now)
                        }
                    }
                    .padding(.vertical, 4)
                    .card()
                }
            }

            if !appts.isEmpty {
                FoldSection(id: "appts", title: "المواعيد اليوم", count: appts.count, openID: $openID) {
                    rows(appts)
                }
            }
            if !activeMeds.isEmpty {
                FoldSection(id: "meds", title: "الأدوية", count: dosesLeft, countLabel: dosesLeft == 0 ? "تمّت" : nil, openID: $openID) {
                    MedsDoseList(meds: activeMeds, now: now)
                }
            }
            if !tasks.isEmpty {
                FoldSection(id: "tasks", title: "المهام", count: tasks.count,
                            alert: !overdueLeft.isEmpty, openID: $openID) {
                    rows(tasks, showDay: !overdueLeft.isEmpty)
                    linkLine("كل المهام") { showTasks = true }
                }
            }
            if !pending.isEmpty {
                FoldSection(id: "pending", title: "معلّقة بدون وقت", count: pending.count, openID: $openID) {
                    rows(pending.map(DayItem.init(entry:)))
                }
            }
            if !doneToday.isEmpty {
                FoldSection(id: "done", title: "تمّت اليوم", count: doneToday.count, quiet: true, openID: $openID) {
                    rows(doneToday)
                }
            }
            if appts.isEmpty && tasks.isEmpty {
                Text(pinned.isEmpty ? "ما عندك مواعيد ولا مهام اليوم." : "ما عندك غيرها اليوم.")
                    .font(.dyn(14)).foregroundStyle(T.muted)
                    .padding(.top, 4)
            }
        }
    }

    /// The nearest open «مهم» or «ضروري» item ahead (two months), shown in the small box.
    private func importantNext(after now: Date, entries: [Entry]) -> DayItem? {
        let horizon = DF.addDays(60, to: now)
        return entries.filter { e in
            guard e.isScheduledKind, e.isOpen, e.importance != .normal, let d = e.anchorDate else { return false }
            return d > now && d < horizon
        }
        .min { ($0.anchorDate ?? .distantFuture) < ($1.anchorDate ?? .distantFuture) }
        .map(DayItem.init(entry:))
    }

    private func rows(_ items: [DayItem], showDay: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Divider().overlay(T.line).padding(.leading, 60) }
                ItemRow(item: item, showDay: showDay)
            }
        }
        .padding(.vertical, 4)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(.dyn(14)).foregroundStyle(T.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func linkLine(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text).font(.dyn(14, weight: .bold)).foregroundStyle(T.accent)
                Spacer()
                Image(systemName: "chevron.left").font(.dyn(12, weight: .bold)).foregroundStyle(T.accent)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DF.weekday(now)).font(.dyn(28, weight: .bold)).foregroundStyle(T.ink)
                Text(DF.fullDate(now, year: false)).font(.dyn(14)).foregroundStyle(T.muted)
            }
            Spacer()
            iconButton("magnifyingglass", label: "ابحث") { showSearch = true }
            iconButton("gearshape", label: "الإعدادات") { app.open(.settings) }
        }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.dyn(19, weight: .medium))
                .foregroundStyle(T.ink)
                .frame(width: 46, height: 46)
                .card(radius: 15)
        }
        .accessibilityLabel(label)
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(HomeFilter.allCases, id: \.self) { f in
                let on = f == filter
                Button {
                    withAnimation(.snappy(duration: 0.2)) { filterRaw = f.rawValue }
                } label: {
                    Text(f.label)
                        .font(.dyn(14, weight: on ? .bold : .regular))
                        .foregroundStyle(on ? T.ink : T.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(hex: 0xE9EBF0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// After the evening time, until today is logged: a slim «وش صار اليوم؟» line.
    private func showEveningPrompt(now: Date) -> Bool {
        let minutes = DF.greg.component(.hour, from: now) * 60 + DF.greg.component(.minute, from: now)
        return minutes >= eveningMinutes && lastEveningLog != DF.dayKey(now)
    }

    private var eveningPrompt: some View {
        Button { app.open(.evening) } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").font(.dyn(17, weight: .semibold))
                Text("وش صار اليوم؟ دقيقة وحدة").font(.dyn(15, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.dyn(13, weight: .bold))
            }
            .foregroundStyle(T.nightText)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.nightBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Fixed at the bottom above the tabs, so it never covers anything.
    private var addBar: some View {
        HStack(spacing: 10) {
            Button {
                app.open(.add(prefill: "", date: nil, kind: nil))
            } label: {
                Label("أضف أي شي", systemImage: "plus")
                    .font(.dyn(17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(T.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                app.open(.voice(.idea))
            } label: {
                Image(systemName: "mic.fill")
                    .font(.dyn(20, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .frame(width: 54, height: 54)
                    .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("قلها بصوتك")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(T.bg.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(T.track).frame(height: 1) }
    }
}

/// One section on the home screen: a title and a count; tap to open or fold it.
struct FoldSection<Content: View>: View {
    let id: String
    let title: String
    let count: Int
    var countLabel: String? = nil
    var alert = false
    var quiet = false
    @Binding var openID: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        let open = openID == id
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { openID = open ? "" : id }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.dyn(16, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(quiet ? T.muted : T.ink)
                    Spacer()
                    Text(countLabel ?? "\(count)")
                        .font(.dyn(14, weight: .bold))
                        .foregroundStyle(alert ? T.urgentInk : T.normalInk)
                        .frame(minWidth: 26)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(alert ? T.urgentSoft : T.normalSoft, in: Capsule())
                    Image(systemName: "chevron.down")
                        .font(.dyn(13, weight: .bold))
                        .foregroundStyle(T.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "اضغط للطي" : "اضغط للفتح")
            if open {
                Divider().overlay(T.line)
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .card(radius: 20)
    }
}

/// The nearest «مهم» or «ضروري» appointment: a small box, red for ضروري, amber for مهم.
struct ImportantBox: View {
    let item: DayItem
    let now: Date

    var body: some View {
        let urgent = item.importance == .urgent
        let ink = urgent ? T.urgentInk : T.taskInk
        let d = item.date ?? item.entry?.anchorDate ?? now
        let days = DF.daysBetween(now, d)
        Button {
            if let e = item.entry { AppState.shared.open(.edit(e.uid)) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.dyn(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(urgent ? T.urgent : Color(hex: 0xD97706), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(urgent ? "الموعد الضروري الجاي" : "الموعد المهم الجاي")
                        .font(.dyn(13, weight: .bold)).foregroundStyle(ink)
                    Text(item.title)
                        .font(.dyn(15, weight: .bold)).foregroundStyle(T.ink).lineLimit(2)
                    Text(DF.whenText(d, hasTime: item.hasTime, now: now))
                        .font(.dyn(13)).foregroundStyle(T.muted)
                }
                Spacer(minLength: 4)
                VStack(spacing: 0) {
                    if days <= 0 {
                        Text("اليوم").font(.dyn(16, weight: .heavy)).foregroundStyle(ink)
                    } else if days == 1 {
                        Text("بكرة").font(.dyn(16, weight: .heavy)).foregroundStyle(ink)
                    } else {
                        Text("\(days)").font(.dyn(21, weight: .heavy)).foregroundStyle(ink).monospacedDigit()
                        Text(days <= 10 ? "أيام" : "يوم").font(.dyn(11, weight: .bold)).foregroundStyle(ink)
                    }
                }
                .frame(minWidth: 48)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(urgent ? T.urgentSoft : T.taskSoft, lineWidth: 1))
            }
            .padding(12)
            .background(urgent ? Color(hex: 0xFEF2F2) : Color(hex: 0xFFFBEB), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(urgent ? T.urgentLine : Color(hex: 0xFCD34D), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// A dose whose time passed (under 3 hours ago) and isn't marked: pinned on top.
struct LateDoseRow: View {
    let med: Medicine
    let slot: Int
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.dyn(16)).foregroundStyle(T.urgentInk)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).font(.dyn(15, weight: .bold)).foregroundStyle(T.ink).lineLimit(2)
                Text("جرعة \(Medicine.slotText(slot)) ما تعلّمت").font(.dyn(12)).foregroundStyle(T.urgentInk)
            }
            Spacer(minLength: 4)
            Button { MedActions.toggle(med, slot: slot, day: now) } label: {
                Text("أخذتها").font(.dyn(14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(T.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 4)
    }
}

/// Inside the «الأدوية» section: each medicine's name on its own line, then one button per dose.
struct MedsDoseList: View {
    let meds: [Medicine]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(meds, id: \.uid) { m in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(m.name).font(.dyn(16, weight: .bold)).foregroundStyle(T.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(verbatim: "\(m.takenCount(on: now)) من \(m.slots.count)")
                            .font(.dyn(13)).foregroundStyle(T.muted)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, max(1, m.slots.count))), spacing: 8) {
                        ForEach(m.slots, id: \.self) { slot in
                            let st = m.state(now, slot, now: now)
                            Button { MedActions.toggle(m, slot: slot, day: now) } label: {
                                HStack(spacing: 4) {
                                    if st == .taken { Image(systemName: "checkmark").font(.dyn(12, weight: .bold)) }
                                    Text(Medicine.slotText(slot)).font(.dyn(14, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(st == .taken ? .white : (st == .late ? T.urgentInk : T.ink))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(st == .taken ? T.accent : .white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .strokeBorder(st == .taken ? .clear : (st == .late ? T.urgentLine : T.track), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("جرعة \(Medicine.slotText(slot))")
                            .accessibilityValue(st == .taken ? "أخذتها" : "ما أخذتها")
                        }
                    }
                    if let left = m.daysLeft(now: now), left <= 3 {
                        Label(m.expiryText(now: now), systemImage: "clock")
                            .font(.dyn(13)).foregroundStyle(T.urgentInk)
                    }
                }
            }
            Button { AppState.shared.thingsSection = 0; AppState.shared.tab = 3 } label: {
                HStack {
                    Text("صفحة الأدوية").font(.dyn(14, weight: .bold)).foregroundStyle(T.accent)
                    Spacer()
                    Image(systemName: "chevron.left").font(.dyn(12, weight: .bold)).foregroundStyle(T.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

struct NextCard: View {
    let item: DayItem?
    let now: Date

    var body: some View {
        Group {
            if let item, let d = item.date {
                let cd = DF.countdown(to: d, now: now)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("التالي").font(.dyn(13, weight: .semibold)).opacity(0.9)
                            if item.importance != .normal {
                                Text(item.importance.label)
                                    .font(.dyn(12, weight: .bold))
                                    .foregroundStyle(T.ink(item.importance))
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(item.title)
                            .font(.dyn(19, weight: .bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DF.whenText(d, hasTime: item.hasTime, now: now))
                            .font(.dyn(14)).opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text(cd.big).font(.dyn(34, weight: .bold)).monospacedDigit()
                        if !cd.small.isEmpty { Text(cd.small).font(.dyn(12)).opacity(0.9) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("التالي").font(.dyn(13, weight: .semibold)).opacity(0.9)
                    Text("ما عندك مواعيد قادمة").font(.dyn(19, weight: .bold))
                    Text("أي موعد تضيفه يظهر هنا مع العدّ التنازلي.").font(.dyn(14)).opacity(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if let e = item?.entry { AppState.shared.open(.edit(e.uid)) }
        }
    }
}

struct HomeCard: View {
    let title: String
    let icon: String
    let ink: Color
    let soft: Color
    let lines: [String]
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.dyn(19, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 40, height: 40)
                .background(soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.dyn(15, weight: .bold)).foregroundStyle(ink)
            if lines.isEmpty {
                Text(empty).font(.dyn(13)).foregroundStyle(T.muted).lineLimit(3)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.dyn(13)).foregroundStyle(T.ink.opacity(0.85)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card(radius: 22)
    }
}

struct TasksListView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]

    var body: some View {
        let now = Date()
        let today = DF.startOfDay(now)
        let tomorrow = DF.addDays(1, to: today)
        let tasks = entries.filter { $0.kind == .task }
        let open = tasks.filter { $0.isOpen }
        let overdue = open.filter { ($0.date ?? .distantFuture) < today }
        let todays = open.filter { if let d = $0.date { return d >= today && d < tomorrow }; return false }
        let later = open.filter { ($0.date ?? .distantPast) >= tomorrow }.sorted { ($0.date ?? now) < ($1.date ?? now) }
        let undated = open.filter { $0.date == nil }
        let done = tasks.filter { $0.isDone && ($0.doneAt ?? .distantPast) > DF.addDays(-7, to: now) }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                group("متأخر", overdue, color: T.urgentInk)
                group("اليوم", todays)
                group("الجاي", later)
                group("بدون تاريخ", undated)
                group("أنجزتها هذا الأسبوع", done, color: T.accent)
                if open.isEmpty && done.isEmpty {
                    Text("ما عندك مهام. أضف مهمة من زر + في الرئيسية.")
                        .font(.dyn(14)).foregroundStyle(T.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg.ignoresSafeArea())
        .navigationTitle("المهام")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Entry], color: Color = T.ink) -> some View {
        if !items.isEmpty {
            SectionTitle(title: title, trailing: "\(items.count)", color: color)
            ItemList(items: items.map(DayItem.init(entry:)), showDay: true)
        }
    }
}
