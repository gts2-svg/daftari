import SwiftUI
import SwiftData

extension Period {
    /// The bar colour: red for «ضروري», orange for «مهم», the app's green otherwise.
    var barColor: Color { T.strong(importance) }
}

// MARK: - one row of bars under a calendar week

/// One lane under a week: the period's bar runs through its days without gaps, rounded only
/// where it really starts and ends (a week break stays square, so it reads as one thing).
/// Days the period doesn't take (outside its weekdays) are drawn lighter.
struct PeriodLane: View {
    let week: [Date?]
    let period: Period?
    var height: CGFloat = 17

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    piece(i).frame(maxWidth: .infinity)
                }
            }
            if let period, let first = labelIndex {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .leading) {
                                // Overflows into the next days without widening its own column.
                                if i == first {
                                    Text(period.displayTitle)
                                        .font(.dyn(10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 6)
                                }
                            }
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if let period { AppState.shared.open(.period(period.uid, start: nil, title: "")) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(period.map { "فترة \($0.displayTitle)، \($0.statusText())" } ?? "")
    }

    private var labelIndex: Int? {
        guard let period else { return nil }
        return week.firstIndex { d in d.map(period.contains) ?? false }
    }

    @ViewBuilder
    private func piece(_ i: Int) -> some View {
        if let period, let day = week[i], period.contains(day) {
            let color = period.barColor
            let isStart = DF.greg.isDate(day, inSameDayAs: period.startDay)
            let isEnd = DF.greg.isDate(day, inSameDayAs: period.endDay)
            let isStone = period.milestones.contains { DF.greg.isDate($0.day, inSameDayAs: day) } && !isStart
            ZStack {
                if isStart || isEnd {
                    RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(color)
                    // Square off the side that carries on, so the joined bar has no notch.
                    if !(isStart && isEnd) {
                        HStack(spacing: 0) {
                            if isStart { Color.clear; Rectangle().fill(color) }
                            else { Rectangle().fill(color); Color.clear }
                        }
                    }
                } else {
                    Rectangle().fill(color)
                }
                if isStone {
                    Circle().fill(.white).frame(width: 6, height: 6)
                }
            }
            // Fade the whole piece at once, so the overlapping shapes at an end don't show darker.
            .compositingGroup()
            .opacity(period.isBusy(day) ? 1 : 0.35)
        } else {
            Color.clear
        }
    }
}

// MARK: - a period in a list (day detail, home)

struct PeriodRow: View {
    let period: Period
    var now = Date()
    var compact = false

    var body: some View {
        Button {
            AppState.shared.open(.period(period.uid, start: nil, title: ""))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Capsule().fill(period.barColor).frame(width: 5, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.displayTitle)
                            .font(.dyn(15, weight: .bold)).foregroundStyle(T.ink).lineLimit(1)
                        Text(period.statusText(now))
                            .font(.dyn(12)).foregroundStyle(T.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if period.importance != .normal { ImportanceBadge(importance: period.importance) }
                }
                if case .running = period.status(now) {
                    ProgressView(value: period.progress(now))
                        .tint(period.barColor)
                }
                if !compact, let next = nextStone {
                    Text(verbatim: "التالي: \(next.title) · \(DF.relativeDay(next.day, now: now))")
                        .font(.dyn(12, weight: .semibold)).foregroundStyle(period.barColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nextStone: PeriodMilestone? {
        let today = DF.startOfDay(now)
        return period.milestones.first { $0.day >= today }
    }
}

// MARK: - add / edit

struct PeriodSheet: View {
    var editingUID: UUID? = nil
    var presetStart: Date? = nil
    var presetTitle: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @AppStorage(Prefs.Key.hijriPrimary) private var hijriPrimary = true

    @State private var title = ""
    @State private var start = DF.startOfDay(Date())
    @State private var end = DF.addDays(6, to: DF.startOfDay(Date()))
    @State private var importance: Importance = .normal
    @State private var someDays = false
    @State private var mask = 0b0011111   // الأحد … الخميس
    @State private var stones: [PeriodMilestone] = []
    @State private var isWork = false
    @State private var newStoneTitle = ""
    @State private var newStoneDay = DF.startOfDay(Date())
    @State private var addingStone = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Period? {
        editingUID.flatMap { id in Store.allPeriods().first { $0.uid == id } }
    }
    private var cal: Calendar { hijriPrimary ? DF.hijri : DF.greg }
    private var length: Int { max(1, DF.daysBetween(start, end) + 1) }
    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let p = editing, case .running = p.status() {
                        PeriodRow(period: p, compact: true).card(radius: 18)
                    }

                    TextField("اسمها: دورة، سفرة، إجازة، تكليف…", text: $title)
                        .font(.dyn(17))
                        .padding(14)
                        .background(T.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.accent, lineWidth: 1.5))

                    section("أهميتها") {
                        HStack(spacing: 8) {
                            ForEach(Importance.allCases, id: \.self) { i in
                                let on = importance == i
                                Button { importance = i } label: {
                                    Text(i.label)
                                        .font(.dyn(15, weight: .bold))
                                        .foregroundStyle(on ? .white : T.ink(i))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(on ? T.strong(i) : T.soft(i),
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("لونها في الجدول: \(importance == .urgent ? "أحمر" : importance == .important ? "برتقالي" : "أخضر")")
                            .font(.dyn(12)).foregroundStyle(T.muted)
                    }

                    section("من … إلى") {
                        dateRow("تبدأ", $start)
                        dateRow("تنتهي", $end)
                        Text(verbatim: "\(DF.daysText(length)) · \(DF.weekday(start)) ← \(DF.weekday(end))")
                            .font(.dyn(13, weight: .semibold)).foregroundStyle(T.accent)
                    }

                    section("أيام الارتباط") {
                        HStack(spacing: 8) {
                            choice("كل الأيام", on: !someDays) { someDays = false }
                            choice("أيام محددة", on: someDays) { someDays = true }
                        }
                        if someDays {
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { d in
                                    let on = mask & (1 << d) != 0
                                    Button { mask ^= (1 << d) } label: {
                                        Text(DF.shortWeekdays[d])
                                            .font(.dyn(12, weight: .bold))
                                            .foregroundStyle(on ? .white : T.ink)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(on ? T.accent : T.field,
                                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(DF.weekdays[d])
                                    .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                            Text("الأيام الثانية تظهر في الشريط بلون أفتح، وما ينبهك دفتري لو حطيت فيها موعد.")
                                .font(.dyn(12)).foregroundStyle(T.muted)
                        } else {
                            Text("كل أيام الفترة تُعتبر مشغولة.")
                                .font(.dyn(12)).foregroundStyle(T.muted)
                        }
                    }

                    section("محطات داخلها (اختياري)") {
                        ForEach(stones) { s in
                            HStack(spacing: 10) {
                                Circle().fill(T.strong(importance)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.dyn(15, weight: .semibold)).foregroundStyle(T.ink)
                                    Text(verbatim: "\(DF.weekday(s.day)) \(DF.dayMonth(s.day, cal: cal))")
                                        .font(.dyn(12)).foregroundStyle(T.muted)
                                }
                                Spacer()
                                Button {
                                    stones.removeAll { $0.id == s.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.dyn(20)).foregroundStyle(T.outline)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("احذف \(s.title)")
                            }
                        }
                        if addingStone {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("مثل: بداية الحضوري، الاختبار، الرجعة", text: $newStoneTitle)
                                    .font(.dyn(15))
                                    .padding(12)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                DayField(label: "يومها", date: $newStoneDay, from: start, to: end, calendar: cal)
                                HStack {
                                    Button("أضف المحطة") {
                                        let typed = newStoneTitle.trimmingCharacters(in: .whitespaces)
                                        let t = typed.isEmpty ? "محطة" : typed
                                        stones.append(PeriodMilestone(title: t, day: newStoneDay))
                                        stones.sort { $0.day < $1.day }
                                        newStoneTitle = ""
                                        addingStone = false
                                    }
                                    .font(.dyn(15, weight: .bold))
                                    .foregroundStyle(T.accent)
                                    .frame(minHeight: 44)
                                    Spacer()
                                    Button("إلغاء") { addingStone = false; newStoneTitle = "" }
                                        .font(.dyn(14)).foregroundStyle(T.muted)
                                }
                            }
                            .padding(12)
                            .background(T.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Button {
                                newStoneDay = min(max(newStoneDay, start), end)
                                addingStone = true
                            } label: {
                                Label("أضف محطة", systemImage: "plus")
                                    .font(.dyn(15, weight: .semibold)).foregroundStyle(T.accent)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("كل محطة لها تذكير في صباح يومها\(importance == .normal ? "" : "، وليلة قبلها").")
                            .font(.dyn(12)).foregroundStyle(T.muted)
                    }

                    section("تتبع") {
                        HStack(spacing: 8) {
                            choice("البيت", on: !isWork) { isWork = false }
                            choice("الشغل", on: isWork) { isWork = true }
                        }
                    }

                    if editing != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("احذف الفترة", systemImage: "trash")
                                .font(.dyn(16, weight: .semibold))
                                .foregroundStyle(T.urgentInk)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .keyboardDone()
            .background(Color.white)
            .navigationTitle(editing == nil ? "فترة جديدة" : "الفترة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .fontWeight(.bold)
                        .disabled(trimmed.isEmpty)
                }
            }
            .confirmationDialog("تحذف الفترة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف", role: .destructive) {
                    if let p = editing { PeriodActions.delete(p) }
                    dismiss()
                }
                Button("إلغاء", role: .cancel) {}
            }
            .onChange(of: start) { _, s in
                if end < s { end = s }
                newStoneDay = min(max(newStoneDay, s), max(s, end))
            }
            .onChange(of: end) { _, e in
                if e < start { start = e }
            }
        }
        .onAppear(perform: load)
    }

    private func section<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.dyn(13, weight: .semibold)).foregroundStyle(T.muted)
            content()
        }
    }

    private func choice(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dyn(15, weight: .bold))
                .foregroundStyle(on ? .white : T.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? T.accent : T.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dateRow(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            DayField(label: label, date: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = DF.startOfDay($0) }
            ), calendar: cal)
            Text(verbatim: "\(DF.weekday(value.wrappedValue)) · \(DF.hijriText(value.wrappedValue)) · \(DF.gregText(value.wrappedValue))")
                .font(.dyn(12)).foregroundStyle(T.muted)
        }
        .padding(12)
        .background(T.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let p = editing {
            title = p.title
            start = p.startDay
            end = p.endDay
            importance = p.importance
            someDays = p.busyMask != 0
            if p.busyMask != 0 { mask = p.busyMask }
            stones = p.milestones
            isWork = p.isWork
        } else {
            title = presetTitle
            if let s = presetStart {
                start = DF.startOfDay(s)
                end = DF.addDays(6, to: start)
            }
            isWork = ArabicDateParser.looksLikeWork(presetTitle)
        }
        newStoneDay = start
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        let p: Period
        if let e = editing {
            p = e
        } else {
            p = Period(title: trimmed, start: start, end: end)
            ctx.insert(p)
        }
        p.title = trimmed
        p.start = DF.startOfDay(min(start, end))
        p.end = DF.startOfDay(max(start, end))
        p.importance = importance
        p.busyMask = someDays && mask != 0 ? mask : 0
        p.milestones = stones.filter { p.contains($0.day) }
        p.isWork = isWork
        try? ctx.save()
        Scheduler.shared.rebuildSoon()
        dismiss()
    }
}
