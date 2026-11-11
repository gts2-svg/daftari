import SwiftUI
import SwiftData
import Charts
import UIKit
import PDFKit

enum SplitColors {
    static let ink = Color(hex: 0x1D6A63)
    static let deep = Color(hex: 0x14524C)
    static let soft = Color(hex: 0xDCEBE7)
}

extension SplitCategory {
    var color: Color { Color(hex: hex) }
}

// MARK: - list inside أغراضي

struct SplitTripsSection: View {
    @Query(sort: \SplitTrip.createdAt, order: .reverse) private var trips: [SplitTrip]
    var onOpen: (UUID) -> Void

    var body: some View {
        if trips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("قطة السفرة").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                Text("سجّل مصروف الطلعة أول بأول مثل ما تكتبه في الملاحظات: «141 بنزين». يجمعها ويقسمها على عددكم، ويوريك وين راحت الفلوس، وتشاركها PDF أو رسالة.")
                    .font(.system(size: 14)).foregroundStyle(T.muted).lineSpacing(3)
                Button {
                    onOpen(SplitActions.create())
                } label: {
                    Text("قطة جديدة")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(SplitColors.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .card(radius: 22)
        } else {
            VStack(spacing: 12) {
                ForEach(trips, id: \.uid) { trip in
                    Button { onOpen(trip.uid) } label: { SplitCard(trip: trip) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SplitCard: View {
    let trip: SplitTrip

    var body: some View {
        let cats = trip.byCategory
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(trip.displayName).font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                Text(verbatim: trip.expenses.isEmpty ? "ما فيها مصروف بعد"
                     : "\(SplitFormat.money(trip.total)) ر.س · على كل واحد \(SplitFormat.money(trip.share.rounded()))")
                    .font(.system(size: 13)).foregroundStyle(T.muted)
                if !cats.isEmpty {
                    SplitStripe(parts: cats.map { ($0.category.color, $0.amount) })
                        .frame(height: 6)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.muted)
        }
        .padding(16)
        .card(radius: 22)
    }
}

/// A thin bar split by share — the category mix at a glance.
struct SplitStripe: View {
    let parts: [(Color, Double)]

    var body: some View {
        let sum = max(parts.reduce(0) { $0 + $1.1 }, 0.0001)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    Capsule().fill(p.0).frame(width: max(3, (geo.size.width - CGFloat(parts.count - 1) * 2) * p.1 / sum))
                }
            }
        }
    }
}

// MARK: - one trip

struct SplitTripDetail: View {
    let uid: UUID
    @Query(sort: \SplitTrip.createdAt) private var trips: [SplitTrip]
    @Environment(\.dismiss) private var dismiss
    @State private var newText = ""
    @State private var currency: SplitCurrency = .sar
    @State private var payer: UUID?
    @State private var editing: SplitExpense?
    @State private var confirmDelete = false
    @State private var askStop = false
    @State private var stopText = ""
    @State private var showNames = false
    @State private var pdf: SharedFile?
    @State private var pickDate = false
    @FocusState private var nameFocused: Bool

    private var trip: SplitTrip? { trips.first { $0.uid == uid } }

    var body: some View {
        ScrollView {
            if let trip {
                content(trip)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg.ignoresSafeArea())
        .keyboardDone()
        .navigationTitle(trip?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if trip?.name.isEmpty == true && trip?.expenses.isEmpty == true { nameFocused = true }
            #if DEBUG
            if Demo.screen == "splitpdf", let trip { pdf = SplitPDF.make(trip).map(SharedFile.init) }
            #endif
        }
        .onDisappear {
            if let trip, trip.name.trimmingCharacters(in: .whitespaces).isEmpty, trip.expenses.isEmpty {
                SplitActions.delete(trip)
            }
        }
        .sheet(item: $editing) { e in
            if let trip {
                SplitExpenseSheet(trip: trip, expense: e)
            }
        }
        .sheet(item: $pdf) { file in
            SplitPDFPreview(url: file.url)
        }
        .sheet(isPresented: $pickDate) {
            if let trip {
                NavigationStack {
                    DatePicker("تاريخ السفرة", selection: Binding(
                        get: { trip.tripDate },
                        set: { trip.tripDate = DF.startOfDay($0); SplitActions.commit() }
                    ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(SplitColors.ink)
                    .padding(.horizontal, 16)
                    .navigationTitle("تاريخ السفرة")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("تم") { pickDate = false }.fontWeight(.bold) }
                    }
                    Spacer(minLength: 0)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert("محطة جديدة", isPresented: $askStop) {
            TextField("مثل: أملج", text: $stopText)
            Button("تم") {
                let s = stopText.trimmingCharacters(in: .whitespaces)
                if let trip, !s.isEmpty { trip.currentStop = s; SplitActions.commit() }
                stopText = ""
            }
            Button("إلغاء", role: .cancel) { stopText = "" }
        }
        .confirmationDialog("تحذف القطة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let trip { SplitActions.delete(trip) }
                dismiss()
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(_ trip: SplitTrip) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("اسم السفرة: الشمال، أبها، مدريد…", text: Binding(
                    get: { trip.name },
                    set: { trip.name = $0; SplitActions.commit() }
                ))
                .font(.system(size: 24, weight: .bold))
                .focused($nameFocused)
                .submitLabel(.done)
                Button { pickDate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(verbatim: "\(DF.hijriText(trip.tripDate)) · \(DF.gregText(trip.tripDate))")
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SplitColors.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(SplitColors.soft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تاريخ السفرة، اضغط لتغييره")
            }

            if trip.expenses.isEmpty {
                setupCard(trip)
            } else {
                dashboard(trip)
            }

            entryCard(trip)

            if !trip.expenses.isEmpty {
                expenseList(trip)
                shareCard(trip)
                setupCard(trip)
            }

            if trip.usesForeign { ratesCard(trip) }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("احذف القطة", systemImage: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.urgentInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: setup — who pays, how many

    private func setupCard(_ trip: SplitTrip) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("مين يدفع؟").font(.system(size: 16, weight: .bold)).foregroundStyle(T.ink)
            HStack(spacing: 10) {
                modeOption(trip, .iPay, title: "أنا أدفع", sub: "وبعدين أقسم", icon: "person.fill")
                modeOption(trip, .everyone, title: "كل واحد يدفع", sub: "ويطلع مين يحوّل لمين", icon: "person.3.fill")
            }

            Divider().overlay(T.line)

            HStack {
                Text("عدد الأشخاص").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
                Spacer()
                HStack(spacing: 0) {
                    stepButton("minus", enabled: trip.count > 1) { trip.setCount(trip.count - 1); SplitActions.commit() }
                    Text(verbatim: "\(trip.count)")
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                        .frame(minWidth: 44)
                    stepButton("plus", enabled: trip.count < 40) { trip.setCount(trip.count + 1); SplitActions.commit() }
                }
            }

            if trip.mode == .everyone || showNames {
                VStack(spacing: 8) {
                    ForEach(Array(trip.people.enumerated()), id: \.element.id) { i, p in
                        TextField(i == 0 ? "أنا" : "اسم الشخص \(i + 1)", text: Binding(
                            get: { p.name },
                            set: { trip.rename(p.id, $0); SplitActions.commit() }
                        ))
                        .font(.system(size: 15))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(T.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            } else {
                Button { showNames = true } label: {
                    Label("أضف أسماءهم (اختياري) عشان تعلّم مين حوّل", systemImage: "person.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SplitColors.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .card(radius: 20)
    }

    private func modeOption(_ trip: SplitTrip, _ mode: SplitMode, title: String, sub: String, icon: String) -> some View {
        let on = trip.mode == mode
        return Button {
            trip.mode = mode
            SplitActions.commit()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .bold))
                Text(sub).font(.system(size: 12)).opacity(0.8)
            }
            .foregroundStyle(on ? .white : T.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(on ? SplitColors.ink : T.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? SplitColors.ink : T.track)
                .frame(width: 44, height: 40)
                .background(SplitColors.soft.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: dashboard

    private func dashboard(_ trip: SplitTrip) -> some View {
        let cats = trip.byCategory
        let stops = trip.byStop.filter { !$0.stop.isEmpty }
        let exact = trip.share
        let rounded = exact.rounded()

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("المجموع").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: SplitFormat.money(trip.total))
                            .font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text("ر.س").font(.system(size: 15, weight: .semibold))
                    }
                    Text(verbatim: "\(trip.expenses.count) مصروف" + (stops.isEmpty ? "" : " · \(stops.count) محطات"))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("على كل واحد").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                    Text(verbatim: SplitFormat.money(rounded))
                        .font(.system(size: 28, weight: .bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(verbatim: abs(exact - rounded) > 0.009
                         ? "\(trip.count) أشخاص · بالضبط \(SplitFormat.money(exact))"
                         : "\(trip.count) أشخاص")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(colors: [SplitColors.ink, SplitColors.deep], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            if !cats.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("في إيش انصرف").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                    HStack(spacing: 16) {
                        Chart(cats) { c in
                            SectorMark(angle: .value("المبلغ", c.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                                .cornerRadius(3)
                                .foregroundStyle(c.category.color)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 112, height: 112)
                        .overlay {
                            VStack(spacing: 0) {
                                Text(verbatim: "\(cats.count)").font(.system(size: 18, weight: .bold))
                                Text("بنود").font(.system(size: 11)).foregroundStyle(T.muted)
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(cats) { c in
                                HStack(spacing: 7) {
                                    Circle().fill(c.category.color).frame(width: 9, height: 9)
                                    Text(c.category.label).font(.system(size: 14)).foregroundStyle(T.ink)
                                    Spacer(minLength: 4)
                                    Text(verbatim: SplitFormat.money(c.amount))
                                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                    Text(verbatim: "\(Int((c.amount / max(trip.total, 0.01) * 100).rounded()))٪")
                                        .font(.system(size: 11)).foregroundStyle(T.muted)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .card(radius: 20)
            }

            if stops.count > 1 {
                let top = stops.map(\.amount).max() ?? 1
                VStack(alignment: .leading, spacing: 10) {
                    Text("حسب المحطة").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                    ForEach(stops) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(s.stop).font(.system(size: 14)).foregroundStyle(T.ink)
                                Spacer()
                                Text(verbatim: SplitFormat.money(s.amount))
                                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                            }
                            ProgressView(value: min(s.amount, top), total: max(top, 0.01))
                                .tint(SplitColors.ink)
                        }
                    }
                }
                .padding(16)
                .card(radius: 20)
            }

            settleCard(trip)
        }
    }

    @ViewBuilder
    private func settleCard(_ trip: SplitTrip) -> some View {
        if trip.mode == .iPay {
            let others = Array(trip.people.dropFirst())
            if !others.isEmpty {
                let done = others.filter(\.settled).count
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("التحصيل").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                        Spacer()
                        Text(verbatim: "حوّل \(done) من \(others.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(done == others.count ? T.accent : T.muted)
                    }
                    VStack(spacing: 6) {
                        ForEach(others) { p in
                            Button {
                                trip.toggleSettled(p.id)
                                SplitActions.commit()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: p.settled ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(p.settled ? T.accent : T.track)
                                    Text(trip.personName(p)).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
                                    Spacer()
                                    Text(p.settled ? "حوّل" : "باقي")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(p.settled ? T.accent : T.muted)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(T.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(verbatim: "كل واحد عليه \(SplitFormat.money(trip.share.rounded())) ر.س. اضغط على اسمه إذا حوّل. هذا القسم ما يطلع في المشاركة.")
                        .font(.system(size: 12)).foregroundStyle(T.muted)
                }
                .padding(16)
                .card(radius: 20)
            }
        } else {
            let moves = trip.transfers
            VStack(alignment: .leading, spacing: 10) {
                Text("التسوية").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                if moves.isEmpty {
                    Text("متساوين، ما على أحد شيء.").font(.system(size: 14)).foregroundStyle(T.muted)
                } else {
                    ForEach(Array(moves.enumerated()), id: \.offset) { _, m in
                        HStack(spacing: 8) {
                            Text(trip.personName(m.from)).font(.system(size: 15, weight: .semibold))
                            Image(systemName: "arrow.left").font(.system(size: 12, weight: .bold)).foregroundStyle(T.muted)
                            Text(trip.personName(m.to)).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(verbatim: "\(SplitFormat.money(m.amount.rounded())) ر.س")
                                .font(.system(size: 15, weight: .bold)).monospacedDigit()
                                .foregroundStyle(SplitColors.ink)
                        }
                        .foregroundStyle(T.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(T.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(trip.people) { p in
                        Text(verbatim: "\(trip.personName(p)) دفع \(SplitFormat.money(trip.paid(by: p.id)))")
                            .font(.system(size: 12)).foregroundStyle(T.muted)
                    }
                }
            }
            .padding(16)
            .card(radius: 20)
        }
    }

    // MARK: entry

    private func entryCard(_ trip: SplitTrip) -> some View {
        let empty = newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                TextField("141 بنزين — أو الصق ملاحظتك", text: $newText, axis: .vertical)
                    .lineLimit(1...10)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.track, lineWidth: 1.5))
                Menu {
                    ForEach(SplitCurrency.allCases) { c in
                        Button("\(c.name) \(c.symbol)") { currency = c }
                    }
                } label: {
                    Text(currency.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(currency == .sar ? T.muted : SplitColors.ink)
                        .frame(width: 48, height: 48)
                        .background(currency == .sar ? T.field : SplitColors.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("العملة: \(currency.name)")
                Button {
                    trip.addLines(newText, currency: currency, payer: trip.mode == .everyone ? (payer ?? trip.me.id) : nil)
                    SplitActions.commit()
                    newText = ""
                } label: {
                    Text("أضف")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 48)
                        .background(empty ? T.track : SplitColors.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(empty)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(trip.namedStops, id: \.self) { s in
                        Button(s) { trip.currentStop = s; SplitActions.commit() }
                    }
                    Button("محطة جديدة…", systemImage: "plus") { askStop = true }
                    if !trip.currentStop.isEmpty {
                        Button("بدون محطة", systemImage: "xmark") { trip.currentStop = ""; SplitActions.commit() }
                    }
                } label: {
                    Label(trip.currentStop.isEmpty ? "المحطة: —" : "المحطة: \(trip.currentStop)", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SplitColors.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(SplitColors.soft, in: Capsule())
                }
                Spacer(minLength: 0)
            }

            if trip.mode == .everyone {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("دفع:").font(.system(size: 13)).foregroundStyle(T.muted)
                        ForEach(trip.people) { p in
                            let on = (payer ?? trip.me.id) == p.id
                            Button { payer = p.id } label: {
                                Text(trip.personName(p))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? .white : T.ink)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 34)
                                    .background(on ? SplitColors.ink : T.field, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("اكتب المبلغ والبند بأي ترتيب. سطر بدون مبلغ مثل «أملج:» يبدأ محطة. المبلغ بالريال إلا إذا اخترت عملة أو كتبت «50 يورو».")
                .font(.system(size: 12)).foregroundStyle(T.muted)
        }
    }

    // MARK: list

    private func expenseList(_ trip: SplitTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(trip.byStop.reversed()) { group in
                VStack(alignment: .leading, spacing: 6) {
                    if !(group.stop.isEmpty && trip.stops.count == 1) {
                        HStack {
                            Text(group.stop.isEmpty ? "بدون محطة" : group.stop)
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(T.muted)
                            Spacer()
                            Text(verbatim: SplitFormat.money(group.amount))
                                .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(T.muted)
                        }
                        .padding(.horizontal, 6)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.reversed().enumerated()), id: \.element.id) { idx, e in
                            if idx > 0 { Divider().overlay(T.line).padding(.leading, 60) }
                            expenseRow(e, in: trip)
                        }
                    }
                    .padding(.vertical, 4)
                    .card(radius: 20)
                }
            }
            Text("اضغط على أي مصروف تعدّله أو تغيّر تصنيفه.")
                .font(.system(size: 12)).foregroundStyle(T.muted)
        }
    }

    private func expenseRow(_ e: SplitExpense, in trip: SplitTrip) -> some View {
        Button { editing = e } label: {
            HStack(spacing: 12) {
                Image(systemName: e.category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(e.category.color)
                    .frame(width: 38, height: 38)
                    .background(e.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.note).font(.system(size: 15)).foregroundStyle(T.ink).lineLimit(1)
                    if trip.mode == .everyone {
                        Text(verbatim: "دفع \(trip.personName(trip.person(e.payer)))")
                            .font(.system(size: 12)).foregroundStyle(T.muted)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: SplitFormat.amount(e))
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                    if e.currency != .sar {
                        Text(verbatim: "≈ \(SplitFormat.money(trip.riyals(e))) ر.س")
                            .font(.system(size: 11)).foregroundStyle(T.muted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("حذف", systemImage: "trash", role: .destructive) { trip.remove(e.id); SplitActions.commit() }
        }
    }

    // MARK: share

    private func shareCard(_ trip: SplitTrip) -> some View {
        HStack(spacing: 10) {
            Button {
                pdf = SplitPDF.make(trip).map(SharedFile.init)
            } label: {
                Label("PDF", systemImage: "doc.richtext")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SplitColors.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            ShareLink(item: trip.summaryText) {
                Label("رسالة للقروب", systemImage: "text.bubble")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(SplitColors.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(SplitColors.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: currencies

    private func ratesCard(_ trip: SplitTrip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("سعر الصرف بالريال").font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
            ForEach(SplitCurrency.allCases.filter { $0 != .sar }) { c in
                HStack {
                    Text(verbatim: "1 \(c.name) \(c.symbol) =").font(.system(size: 14)).foregroundStyle(T.ink)
                    Spacer()
                    TextField("", value: Binding(
                        get: { trip.rate(c) },
                        set: { v in
                            var r = trip.rates
                            r[c.rawValue] = v > 0 ? v : c.defaultRate
                            trip.rates = r
                            SplitActions.commit()
                        }
                    ), format: .number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US_POSIX")))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .frame(width: 90, height: 38)
                    .background(T.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("ر.س").font(.system(size: 13)).foregroundStyle(T.muted)
                }
            }
            Text("عدّل السعر حسب اللي صرفت فيه، والمجموع يتحدث.")
                .font(.system(size: 12)).foregroundStyle(T.muted)
        }
        .padding(16)
        .card(radius: 20)
    }
}

// MARK: - edit one expense

struct SplitExpenseSheet: View {
    let trip: SplitTrip
    @State var expense: SplitExpense
    @State private var amountText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        TextField("المبلغ", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        Picker("العملة", selection: $expense.currency) {
                            ForEach(SplitCurrency.allCases) { c in Text("\(c.name) \(c.symbol)").tag(c) }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(14)
                    .card(radius: 18)

                    TextField("على إيش؟", text: $expense.note)
                        .font(.system(size: 17))
                        .padding(14)
                        .card(radius: 18)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("التصنيف").font(.system(size: 14, weight: .bold)).foregroundStyle(T.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(SplitCategory.allCases) { c in
                                let on = expense.category == c
                                Button { expense.category = c } label: {
                                    Label(c.label, systemImage: c.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(on ? .white : c.color)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 38)
                                        .background(on ? c.color : c.color.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("المحطة").font(.system(size: 14, weight: .bold)).foregroundStyle(T.muted)
                        TextField("بدون محطة", text: $expense.stop)
                            .font(.system(size: 16))
                            .padding(12)
                            .card(radius: 14)
                        if !trip.namedStops.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(trip.namedStops, id: \.self) { s in
                                    Button { expense.stop = s } label: {
                                        Text(s)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(expense.stop == s ? .white : SplitColors.ink)
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 34)
                                            .background(expense.stop == s ? SplitColors.ink : SplitColors.soft, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if trip.mode == .everyone {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("مين دفع؟").font(.system(size: 14, weight: .bold)).foregroundStyle(T.muted)
                            FlowLayout(spacing: 8) {
                                ForEach(trip.people) { p in
                                    let on = (expense.payer ?? trip.me.id) == p.id
                                    Button { expense.payer = p.id } label: {
                                        Text(trip.personName(p))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(on ? .white : T.ink)
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 38)
                                            .background(on ? SplitColors.ink : Color.white, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button(role: .destructive) {
                        trip.remove(expense.id)
                        SplitActions.commit()
                        dismiss()
                    } label: {
                        Label("احذف المصروف", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(T.urgentInk)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(T.bg.ignoresSafeArea())
            .keyboardDone()
            .navigationTitle("المصروف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.fontWeight(.bold)
                }
            }
            .onAppear { amountText = SplitFormat.money(expense.amount).replacingOccurrences(of: ",", with: "") }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let t = SplitParser.normalize(amountText).replacingOccurrences(of: ",", with: "")
        if let v = Double(t), v > 0 { expense.amount = v }
        expense.note = expense.note.trimmingCharacters(in: .whitespaces)
        if expense.note.isEmpty { expense.note = "مصروف" }
        expense.stop = expense.stop.trimmingCharacters(in: .whitespaces)
        trip.update(expense)
        SplitActions.commit()
        dismiss()
    }
}

// MARK: - PDF

/// The shared sheet: simple and light — the total, where it went, and each share. No names.
struct SplitReport: View {
    let trip: SplitTrip
    static let width: CGFloat = 595

    var body: some View {
        let cats = trip.byCategory
        let groups = trip.byStop
        let rounded = trip.share.rounded()

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("قطة").font(.system(size: 13, weight: .semibold)).foregroundStyle(SplitColors.ink)
                Text(trip.displayName).font(.system(size: 30, weight: .bold)).foregroundStyle(T.ink)
                Text(verbatim: "\(DF.hijriText(trip.tripDate)) · \(DF.gregText(trip.tripDate))")
                    .font(.system(size: 13)).foregroundStyle(T.muted)
            }

            HStack(spacing: 0) {
                stat("المجموع", SplitFormat.money(trip.total), unit: "ر.س", big: true)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 54)
                stat("على كل واحد", SplitFormat.money(rounded), unit: "ر.س", big: true)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 54)
                stat("عددنا", "\(trip.count)", unit: "أشخاص", big: false)
            }
            .padding(.vertical, 20)
            .background(
                LinearGradient(colors: [SplitColors.ink, SplitColors.deep], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            if !cats.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("في إيش انصرف").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                    SplitStripe(parts: cats.map { ($0.category.color, $0.amount) }).frame(height: 10)
                    ForEach(cats) { c in
                        HStack(spacing: 10) {
                            Image(systemName: c.category.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(c.category.color)
                                .frame(width: 30, height: 30)
                                .background(c.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(c.category.label).font(.system(size: 15)).foregroundStyle(T.ink)
                            Spacer()
                            Text(verbatim: "\(Int((c.amount / max(trip.total, 0.01) * 100).rounded()))٪")
                                .font(.system(size: 12)).foregroundStyle(T.muted)
                            Text(verbatim: SplitFormat.money(c.amount))
                                .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                                .frame(minWidth: 64, alignment: .trailing)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("التفاصيل").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        if !(g.stop.isEmpty && groups.count == 1) {
                            HStack {
                                Text(g.stop.isEmpty ? "أخرى" : g.stop)
                                    .font(.system(size: 14, weight: .bold)).foregroundStyle(SplitColors.ink)
                                Spacer()
                                Text(verbatim: SplitFormat.money(g.amount))
                                    .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(SplitColors.ink)
                            }
                        }
                        ForEach(g.items) { e in
                            HStack(spacing: 8) {
                                Circle().fill(e.category.color).frame(width: 7, height: 7)
                                Text(e.note).font(.system(size: 14)).foregroundStyle(T.ink)
                                Spacer()
                                if e.currency != .sar {
                                    Text(verbatim: SplitFormat.amount(e)).font(.system(size: 11)).foregroundStyle(T.muted)
                                }
                                Text(verbatim: SplitFormat.money(trip.riyals(e)))
                                    .font(.system(size: 14)).monospacedDigit().foregroundStyle(T.ink)
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(hex: 0xF7F5F0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Text("المبالغ بالريال السعودي · من دفتري")
                .font(.system(size: 11)).foregroundStyle(T.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(36)
        .frame(width: Self.width)
        .background(Color.white)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, DF.locale)
    }

    private func stat(_ title: String, _ value: String, unit: String, big: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
            Text(verbatim: value).font(.system(size: big ? 30 : 26, weight: .bold)).monospacedDigit()
            Text(unit).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

@MainActor
enum SplitPDF {
    static func make(_ trip: SplitTrip) -> URL? {
        let renderer = ImageRenderer(content: SplitReport(trip: trip))
        renderer.proposedSize = ProposedViewSize(width: SplitReport.width, height: nil)
        let safe = trip.displayName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("قطة \(safe).pdf")
        try? FileManager.default.removeItem(at: url)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Shows the PDF as it will be sent, with the share button on top.
struct SplitPDFPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .background(Color(hex: 0xE9E6DF))
                .navigationTitle("معاينة")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: url) {
                            Label("مشاركة", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(red: 0.91, green: 0.90, blue: 0.87, alpha: 1)
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

// MARK: - actions

@MainActor
enum SplitActions {
    static func create() -> UUID {
        let t = SplitTrip(name: "")
        Store.context.insert(t)
        Store.save()
        return t.uid
    }

    static func delete(_ trip: SplitTrip) {
        Store.context.delete(trip)
        Store.save()
    }

    static func commit() {
        Store.save()
    }
}
