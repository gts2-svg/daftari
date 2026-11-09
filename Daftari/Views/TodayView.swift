import SwiftUI
import SwiftData

/// «اليوم — هادئ مع بطاقات»: header, the big "next" card, four cards, then the day's list.
struct TodayView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query(sort: \Medicine.createdAt) private var meds: [Medicine]
    @ObservedObject private var app = AppState.shared
    @State private var showTasks = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        content(now: context.date)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 130)
                }
                .background(T.bg.ignoresSafeArea())

                addButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showTasks) { TasksListView() }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let todayItems = Agenda.items(on: now, entries: entries)
        let overdue = Agenda.overdue(entries: entries, now: now)
        VStack(alignment: .leading, spacing: 16) {
            header(now: now)
            NextCard(item: Agenda.next(after: now, entries: entries), now: now)
            if meds.contains(where: { !$0.courseFinished }) {
                MedsTodayCard(meds: meds.filter { !$0.courseFinished }, now: now)
            }
            cards(now: now, todayItems: todayItems, overdue: overdue)

            if !overdue.isEmpty {
                SectionTitle(title: "متأخر", trailing: "\(overdue.count)", color: T.urgentInk)
                    .padding(.top, 4)
                ItemList(items: overdue.map(DayItem.init(entry:)), showDay: true)
            }

            SectionTitle(title: "يومك", trailing: todayItems.isEmpty ? nil : "\(todayItems.filter { !$0.isDone }.count) باقي")
                .padding(.top, 4)
            if todayItems.isEmpty {
                Text("ما عندك شيء اليوم. اضغط + وأضف أي شيء ببالك، أو قله بصوتك من زر المايك.")
                    .font(.system(size: 14))
                    .foregroundStyle(T.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(T.track, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            } else {
                ItemList(items: todayItems)
            }
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DF.greeting(now)).font(.system(size: 15)).foregroundStyle(T.muted)
                Text(DF.weekday(now)).font(.system(size: 32, weight: .bold)).foregroundStyle(T.ink)
                Text(DF.fullDate(now)).font(.system(size: 15)).foregroundStyle(T.muted)
            }
            Spacer()
            Button {
                app.open(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(T.ink)
                    .frame(width: 46, height: 46)
                    .card(radius: 15)
            }
            .accessibilityLabel("الإعدادات")
        }
    }

    private func cards(now: Date, todayItems: [DayItem], overdue: [Entry]) -> some View {
        let appointments = todayItems.filter { $0.isAppointment && !$0.isDone }
        let tasks = entries.filter { e in
            guard e.kind == .task, e.isOpen else { return false }
            guard let d = e.date else { return false }
            return d < DF.addDays(1, to: DF.startOfDay(now))
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let ideas = entries.filter { $0.kind == .idea }.sorted { $0.createdAt > $1.createdAt }

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            Button { app.tab = 1 } label: {
                HomeCard(title: "مواعيد", icon: "calendar", ink: T.accentDeep, soft: T.accentSoft,
                         lines: appointments.prefix(2).map { i in
                             if let d = i.date, i.hasTime { return "\(i.title)\n\(DF.time(d))" }
                             return i.title
                         },
                         empty: "ما عندك مواعيد اليوم")
            }
            .buttonStyle(.plain)

            Button { showTasks = true } label: {
                HomeCard(title: tasks.isEmpty ? "مهام" : "مهام · \(tasks.count)", icon: "checklist", ink: T.taskInk, soft: T.taskSoft,
                         lines: tasks.prefix(2).map { $0.title }, empty: "ما عليك مهام اليوم")
            }
            .buttonStyle(.plain)

            Button { app.tab = 2 } label: {
                HomeCard(title: ideas.isEmpty ? "الأفكار" : "الأفكار · \(ideas.count)", icon: "lightbulb", ink: T.ideaInk, soft: T.ideaSoft,
                         lines: ideas.prefix(1).map { $0.title }, empty: "قل فكرتك بصوتك")
            }
            .buttonStyle(.plain)

            Button { app.tab = 3 } label: {
                HomeCard(title: "أشيائي", icon: "shippingbox", ink: T.ideaInk, soft: T.ideaSoft,
                         lines: [], empty: "التجديدات والضمانات والصيانة — المرحلة الثانية")
            }
            .buttonStyle(.plain)
        }
    }

    private var addButtons: some View {
        VStack(spacing: 12) {
            Button {
                app.open(.voice(.idea))
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .frame(width: 52, height: 52)
                    .background(T.card, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
            .accessibilityLabel("سجّل فكرة بصوتك")

            Button {
                app.open(.add(prefill: "", date: nil, kind: nil))
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(T.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .accessibilityLabel("إضافة")
        }
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
                            Text("التالي").font(.system(size: 13, weight: .semibold)).opacity(0.9)
                            if item.importance != .normal {
                                Text(item.importance.label)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(T.ink(item.importance))
                                    .padding(.horizontal, 10).padding(.vertical, 3)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(item.title)
                            .font(.system(size: 19, weight: .bold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DF.whenText(d, hasTime: item.hasTime, now: now))
                            .font(.system(size: 14)).opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text(cd.big).font(.system(size: 34, weight: .bold)).monospacedDigit()
                        if !cd.small.isEmpty { Text(cd.small).font(.system(size: 12)).opacity(0.9) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("التالي").font(.system(size: 13, weight: .semibold)).opacity(0.9)
                    Text("ما عندك مواعيد قادمة").font(.system(size: 19, weight: .bold))
                    Text("أي موعد تضيفه يظهر هنا مع العدّ التنازلي.").font(.system(size: 14)).opacity(0.9)
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
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 40, height: 40)
                .background(soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
            if lines.isEmpty {
                Text(empty).font(.system(size: 13)).foregroundStyle(T.muted).lineLimit(3)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 13)).foregroundStyle(T.ink.opacity(0.85)).lineLimit(2)
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
                        .font(.system(size: 14)).foregroundStyle(T.muted)
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
