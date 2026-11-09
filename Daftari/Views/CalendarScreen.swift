import SwiftUI
import SwiftData

/// «التقويم — شهر» in the calm style: month grid with the primary calendar big
/// and the other calendar small, coloured dots, and the chosen day underneath.
struct CalendarScreen: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @AppStorage(Prefs.Key.hijriPrimary) private var hijriPrimary = true
    @State private var anchor = Date()
    @State private var selected = Date()

    private var cal: Calendar { hijriPrimary ? DF.hijri : DF.greg }
    private var other: Calendar { hijriPrimary ? DF.greg : DF.hijri }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    monthGrid
                    dayDetail
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(T.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(monthTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(T.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                navButton("chevron.backward", label: "الشهر السابق", by: -1)
                navButton("chevron.forward", label: "الشهر التالي", by: 1)
            }
            HStack {
                Text(otherSpan).font(.system(size: 13)).foregroundStyle(T.muted)
                Spacer()
                Button("ارجع لليوم") {
                    anchor = Date()
                    selected = Date()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.accent)
                .frame(minHeight: 32)
            }
        }
    }

    private func navButton(_ icon: String, label: String, by step: Int) -> some View {
        Button {
            moveMonth(by: step)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(T.ink)
                .frame(width: 44, height: 44)
                .card(radius: 14)
        }
        .accessibilityLabel(label)
    }

    /// Moves the shown month and takes the chosen day along with it: today when
    /// the new month holds today, otherwise the month's first day — so the day
    /// details under the grid never belong to a month that is off screen.
    private func moveMonth(by step: Int) {
        guard let d = cal.date(byAdding: .month, value: step, to: anchor) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            anchor = d
            if cal.isDate(Date(), equalTo: d, toGranularity: .month) {
                selected = Date()
            } else if let start = cal.dateInterval(of: .month, for: d)?.start {
                selected = start
            }
        }
    }

    /// Horizontal swipe on the month card. Measured in screen space so the
    /// right-to-left layout can't flip it: the «التالي» arrow sits on the left,
    /// so the next month comes in from the left — finger moves right → next.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                moveMonth(by: dx > 0 ? 1 : -1)
            }
    }

    private var monthTitle: String {
        let c = cal.dateComponents([.month, .year], from: anchor)
        return "\(DF.monthName(c.month ?? 1, cal: cal)) \(c.year ?? 0)"
    }

    private var otherSpan: String {
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return "" }
        let first = other.dateComponents([.month, .year], from: interval.start)
        let last = other.dateComponents([.month, .year], from: interval.end.addingTimeInterval(-1))
        let a = DF.monthName(first.month ?? 1, cal: other)
        let b = DF.monthName(last.month ?? 1, cal: other)
        if first.month == last.month { return "\(a) \(last.year ?? 0)" }
        if first.year == last.year { return "\(a) – \(b) \(last.year ?? 0)" }
        return "\(a) \(first.year ?? 0) – \(b) \(last.year ?? 0)"
    }

    // MARK: grid

    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let count = cal.range(of: .day, in: .month, for: anchor)?.count ?? 30
        let offset = DF.greg.component(.weekday, from: first) - 1
        var days: [Date?] = Array(repeating: nil, count: offset)
        for i in 0..<count { days.append(DF.addDays(i, to: first)) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private var monthGrid: some View {
        let days = monthDays
        let interval = cal.dateInterval(of: .month, for: anchor)
        let marks = Agenda.marks(entries: entries, from: interval?.start ?? anchor, to: interval?.end ?? anchor)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(DF.shortWeekdays, id: \.self) { name in
                    Text(name).font(.system(size: 12)).foregroundStyle(T.muted).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, mark: marks[DF.dayKey(day)])
                    } else {
                        Color.clear.frame(height: 54)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .card(radius: 22)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
    }

    private func dayCell(_ day: Date, mark: Importance??) -> some View {
        let isSelected = DF.greg.isDate(day, inSameDayAs: selected)
        let isToday = DF.greg.isDate(day, inSameDayAs: Date())
        let main = cal.component(.day, from: day)
        let sub = other.component(.day, from: day)
        let dotColor: Color? = {
            guard let mark else { return nil }
            if let importance = mark { return importance == .normal ? T.normalInk : T.ink(importance) }
            return T.systemDot
        }()

        return Button {
            selected = day
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: "\(main)")
                    .font(.system(size: 16, weight: isSelected || isToday ? .bold : .semibold))
                    .monospacedDigit()
                Text(verbatim: "\(sub)")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : T.muted)
                Circle()
                    .fill(dotColor.map { isSelected ? Color.white : $0 } ?? Color.clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(isSelected ? Color.white : T.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.accent)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.accent, lineWidth: 1.5)
                }
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DF.weekday(day)) \(DF.fullDate(day))")
    }

    // MARK: day

    private var dayDetail: some View {
        let items = Agenda.items(on: selected, entries: entries)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(DF.weekday(selected)) \(DF.dayMonth(selected, cal: cal, year: false))")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(T.ink)
                    Text(DF.dayMonth(selected, cal: other)).font(.system(size: 12)).foregroundStyle(T.muted)
                }
                Spacer()
                Button {
                    AppState.shared.open(.add(prefill: "", date: DF.startOfDay(selected), kind: nil))
                } label: {
                    Label("أضف", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.accent)
                        .frame(height: 44)
                        .padding(.horizontal, 14)
                        .card(T.accentSoft, radius: 14)
                }
            }
            if items.isEmpty {
                Text("ما فيه شيء في هذا اليوم.")
                    .font(.system(size: 14)).foregroundStyle(T.muted)
                    .padding(.vertical, 8)
            } else {
                ItemList(items: items)
            }
        }
    }
}
