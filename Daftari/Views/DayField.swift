import SwiftUI

/// A day row whose calendar closes by itself as soon as a day is tapped.
/// (The system's compact date picker stays open until you tap outside it.)
struct DayField: View {
    let label: String
    @Binding var date: Date
    var from: Date? = nil
    var to: Date? = nil
    var calendar: Calendar? = nil

    @State private var open = false

    private var cal: Calendar { calendar ?? DF.primary }

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.dyn(15, weight: .semibold)).foregroundStyle(T.ink)
            Spacer(minLength: 8)
            Button { open = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.dyn(14, weight: .semibold))
                    Text(verbatim: DF.dayMonth(date, cal: cal))
                        .font(.dyn(16, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(T.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(T.track.opacity(0.55), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label): \(DF.weekday(date)) \(DF.dayMonth(date, cal: cal))")
            .accessibilityHint("يفتح التقويم")
        }
        .sheet(isPresented: $open) {
            DayPickerSheet(title: label, date: $date, from: from, to: to, calendar: cal)
        }
    }
}

struct DayPickerSheet: View {
    let title: String
    @Binding var date: Date
    var from: Date?
    var to: Date?
    var calendar: Calendar

    @Environment(\.dismiss) private var dismiss
    @State private var closing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, calendar)
                    .tint(T.accent)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }.fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.height(500), .large])
    }

    /// Picking a day closes the sheet; paging months doesn't.
    private var pick: Binding<Date> {
        Binding(
            get: { date },
            set: { new in
                let changedDay = !DF.greg.isDate(new, inSameDayAs: date)
                date = new
                guard changedDay, !closing else { return }
                closing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dismiss() }
            }
        )
    }

    @ViewBuilder
    private var picker: some View {
        if let from, let to {
            DatePicker(title, selection: pick, in: from...max(from, to), displayedComponents: .date)
        } else if let from {
            DatePicker(title, selection: pick, in: from..., displayedComponents: .date)
        } else if let to {
            DatePicker(title, selection: pick, in: ...to, displayedComponents: .date)
        } else {
            DatePicker(title, selection: pick, displayedComponents: .date)
        }
    }
}
