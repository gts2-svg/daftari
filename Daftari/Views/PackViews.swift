import SwiftUI
import SwiftData

enum PackColors {
    static let ink = Color(hex: 0x8A5A12)
    static let deep = Color(hex: 0x5E3C08)
    static let soft = Color(hex: 0xF6EBD6)
}

/// «أغراضي» inside أشيائي: the list of packing lists.
struct PackListsSection: View {
    @Query(sort: \PackList.createdAt) private var lists: [PackList]
    let now: Date
    var onOpen: (UUID) -> Void

    var body: some View {
        if lists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("قوائم أغراضك").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                Text("سوّ قائمة للبر أو السفر أو العزبة، والصق أغراضك من الملاحظات مرة وحدة. علّم وأنت تجهّز، وبعد ما ترجع اضغط «صفّر العلامات» فتصير جاهزة للطلعة الجاية.")
                    .font(.system(size: 14)).foregroundStyle(T.muted).lineSpacing(3)
                Button {
                    onOpen(PackActions.create())
                } label: {
                    Text("قائمة جديدة")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PackColors.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .card(radius: 22)
        } else {
            VStack(spacing: 12) {
                ForEach(lists, id: \.uid) { list in
                    Button { onOpen(list.uid) } label: { PackCard(list: list, now: now) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PackCard: View {
    let list: PackList
    let now: Date

    var body: some View {
        let done = list.total > 0 && list.doneCount == list.total
        HStack(spacing: 14) {
            PackRing(list: list, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(list.displayName).font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                Text(verbatim: list.total == 0 ? "فاضية — أضف أغراضك"
                     : (done ? "جاهز كله ✓" : "جهّزت \(list.doneCount) من \(list.total)"))
                    .font(.system(size: 13)).foregroundStyle(done ? T.accent : T.muted)
                if let trip = list.tripDate {
                    Text(verbatim: tripText(trip))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PackColors.ink)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.muted)
        }
        .padding(16)
        .card(radius: 22)
    }

    private func tripText(_ trip: Date) -> String {
        let days = DF.daysBetween(now, trip)
        if days < 0 { return "رجعت؟ صفّر العلامات للطلعة الجاية" }
        if days == 0 { return "الطلعة اليوم" }
        if days == 1 { return "الطلعة بكرة" }
        return "الطلعة \(DF.relativeDay(trip, now: now)) · بعد \(days == 2 ? "يومين" : DF.daysText(days))"
    }
}

struct PackRing: View {
    let list: PackList
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: 0xEEEDE7), lineWidth: size / 9)
            Circle()
                .trim(from: 0, to: list.fraction)
                .stroke(list.fraction >= 1 ? T.accent : PackColors.ink,
                        style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(list.doneCount)/\(list.total)")
                .font(.system(size: size / 4.2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(T.ink)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("جهّزت \(list.doneCount) من \(list.total)")
    }
}

/// One packing list: name, trip day, add or paste items, tick, reset, delete.
struct PackListDetail: View {
    let uid: UUID
    @Query(sort: \PackList.createdAt) private var lists: [PackList]
    @Environment(\.dismiss) private var dismiss
    @State private var newText = ""
    @State private var confirmDelete = false
    @State private var confirmReset = false
    @FocusState private var nameFocused: Bool

    private var list: PackList? { lists.first { $0.uid == uid } }

    var body: some View {
        ScrollView {
            if let list {
                content(list)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg.ignoresSafeArea())
        .keyboardDone()
        .navigationTitle(list?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if list?.name.isEmpty == true { nameFocused = true }
        }
        .onDisappear {
            // A list that was opened and left empty is dropped.
            if let list, list.name.trimmingCharacters(in: .whitespaces).isEmpty, list.total == 0 {
                PackActions.delete(list)
            }
        }
        .confirmationDialog("تحذف القائمة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                if let list { PackActions.delete(list) }
                dismiss()
            }
            Button("إلغاء", role: .cancel) {}
        }
        .confirmationDialog("تشيل كل العلامات؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("صفّرها") { if let list { PackActions.reset(list) } }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("الأغراض تبقى، بس ترجع كلها بدون علامة للطلعة الجاية.")
        }
    }

    @ViewBuilder
    private func content(_ list: PackList) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("اسم القائمة: البر، السفر، العزبة…", text: Binding(
                get: { list.name },
                set: { list.name = $0; PackActions.commit() }
            ))
            .font(.system(size: 24, weight: .bold))
            .focused($nameFocused)
            .submitLabel(.done)

            HStack(spacing: 14) {
                PackRing(list: list, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: list.total == 0 ? "ما فيها أغراض بعد" : "جهّزت \(list.doneCount) من \(list.total)")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(T.ink)
                    if list.doneCount > 0 {
                        Button {
                            confirmReset = true
                        } label: {
                            Label("صفّر العلامات", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(PackColors.ink)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 38)
                                .background(PackColors.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .card(radius: 20)

            tripCard(list)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    TextField("أضف غرض، أو الصق قائمتك من الملاحظات", text: $newText, axis: .vertical)
                        .lineLimit(1...8)
                        .font(.system(size: 16))
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.track, lineWidth: 1.5))
                    Button {
                        PackActions.add(newText, to: list)
                        newText = ""
                    } label: {
                        Text("أضف")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 48)
                            .background(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? T.track : PackColors.ink,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("كل سطر يصير غرض. اضغط مطوّلاً على أي غرض لحذفه.")
                    .font(.system(size: 12)).foregroundStyle(T.muted)
            }

            if !list.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Divider().overlay(T.line).padding(.leading, 56) }
                        itemRow(item, in: list)
                    }
                }
                .padding(.vertical, 4)
                .card(radius: 20)
            }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("احذف القائمة", systemImage: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.urgentInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func tripCard(_ list: PackList) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("عندي طلعة بتاريخ", isOn: Binding(
                get: { list.tripDate != nil },
                set: { on in
                    list.tripDate = on ? DF.addDays(1, to: DF.startOfDay(Date())) : nil
                    PackActions.commit()
                }
            ))
            .font(.system(size: 15, weight: .semibold))
            if let trip = list.tripDate {
                DatePicker("يوم الطلعة", selection: Binding(
                    get: { trip },
                    set: { list.tripDate = DF.startOfDay($0); PackActions.commit() }
                ), displayedComponents: .date)
                Text(verbatim: "\(DF.weekday(trip)) · \(DF.fullDate(trip))")
                    .font(.system(size: 12)).foregroundStyle(T.muted)
                Text("يذكّرك الليلة اللي قبلها الساعة 8:00 م، وصباح يوم الطلعة، بالأغراض اللي ما علّمت عليها.")
                    .font(.system(size: 12)).foregroundStyle(T.muted)
            }
        }
        .padding(16)
        .card(radius: 20)
    }

    private func itemRow(_ item: PackItem, in list: PackList) -> some View {
        Button {
            PackActions.toggle(item.id, in: list)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(item.done ? T.accent : T.track)
                    .frame(width: 40, height: 44)
                Text(item.text)
                    .font(.system(size: 16))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? T.muted : T.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("حذف", systemImage: "trash", role: .destructive) { PackActions.remove(item.id, from: list) }
        }
        .accessibilityLabel("\(item.text)، \(item.done ? "جاهز" : "ما جهّزته")")
    }
}

@MainActor
enum PackActions {
    static func create() -> UUID {
        let l = PackList(name: "")
        Store.context.insert(l)
        Store.save()
        return l.uid
    }

    static func add(_ text: String, to list: PackList) {
        list.add(text)
        commit()
    }

    static func toggle(_ id: UUID, in list: PackList) {
        list.toggle(id)
        commit()
    }

    static func remove(_ id: UUID, from list: PackList) {
        list.remove(id)
        commit()
    }

    static func reset(_ list: PackList) {
        list.resetChecks()
        commit()
    }

    static func delete(_ list: PackList) {
        Store.context.delete(list)
        commit()
    }

    static func commit() {
        Store.save()
        Scheduler.shared.rebuildSoon()
    }
}
