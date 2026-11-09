import SwiftUI
import SwiftData

private enum MedColors {
    static let ink = Color(hex: 0x2F6F8F)
    static let deep = Color(hex: 0x1F5570)
    static let soft = Color(hex: 0xE1EEF4)
    static let outline = Color(hex: 0xC6D9E3)
}

// MARK: - Today card

/// «أدويتي اليوم» on the Today screen: dose dots per medicine, next time, and an expiry warning.
struct MedsTodayCard: View {
    let meds: [Medicine]
    let now: Date

    var body: some View {
        let active = meds.filter { $0.isActive(on: now) && !$0.slots.isEmpty }
        let total = active.reduce(0) { $0 + $1.slots.count }
        let taken = active.reduce(0) { $0 + $1.takenCount(on: now) }
        let expiring = meds.filter { m in
            guard !m.courseFinished, let left = m.daysLeft(now: now) else { return false }
            return left <= 3
        }

        Button {
            AppState.shared.tab = 3
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "drop")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MedColors.ink)
                        .frame(width: 36, height: 36)
                        .background(MedColors.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Text("أدويتي اليوم").font(.system(size: 15, weight: .bold)).foregroundStyle(MedColors.ink)
                    Spacer()
                    if total > 0 {
                        Text(verbatim: "\(taken) من \(total) جرعات").font(.system(size: 13)).foregroundStyle(T.muted)
                    }
                }
                ForEach(active, id: \.uid) { m in
                    HStack(spacing: 10) {
                        Text(m.name).font(.system(size: 14)).foregroundStyle(T.ink).lineLimit(1)
                        Spacer(minLength: 6)
                        HStack(spacing: 5) {
                            ForEach(m.slots, id: \.self) { slot in
                                DoseDot(state: m.state(now, slot, now: now))
                            }
                        }
                        Text(m.nextDose(now: now).map(Medicine.slotText) ?? "خلصت")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(m.nextDose(now: now) == nil ? T.accent : MedColors.ink)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                ForEach(expiring, id: \.uid) { m in
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text(verbatim: "\(m.name): \(m.expiryText(now: now))").lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x8E2F0A))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .card(radius: 22)
        }
        .buttonStyle(.plain)
    }
}

struct DoseDot: View {
    let state: DoseState
    var body: some View {
        switch state {
        case .taken:
            Circle().fill(MedColors.ink).frame(width: 12, height: 12)
        case .late:
            Circle().strokeBorder(T.urgentInk, lineWidth: 2).frame(width: 12, height: 12)
        case .upcoming:
            Circle().strokeBorder(MedColors.ink, lineWidth: 2).frame(width: 12, height: 12)
        }
    }
}

// MARK: - أشيائي

struct ThingsView: View {
    @Query(sort: \Medicine.createdAt) private var meds: [Medicine]
    @State private var section = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("أشيائي").font(.system(size: 28, weight: .bold)).foregroundStyle(T.ink)
                            Spacer()
                            if section == 0 {
                                Button {
                                    AppState.shared.open(.medicine(nil))
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(T.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .accessibilityLabel("إضافة دواء")
                            }
                        }
                        Picker("القسم", selection: $section) {
                            Text("أدويتي").tag(0)
                            Text("تجديدات").tag(1)
                            Text("ضمانات").tag(2)
                            Text("السيارة").tag(3)
                        }
                        .pickerStyle(.segmented)

                        if section == 0 {
                            medsSection(now: context.date)
                        } else {
                            comingSoon
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .background(T.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func medsSection(now: Date) -> some View {
        let current = meds.filter { !$0.courseFinished }
        let finished = meds.filter { $0.courseFinished }
        if meds.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("أضف قطراتك وأدويتك").font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                Text("سجّل متى فتحت العلبة وكم تبقى صالحة، وأوقات الجرعات. يذكّرك بكل جرعة لين تضغط «أخذتها»، وينبهك قبل ما تنتهي العلبة.")
                    .font(.system(size: 14)).foregroundStyle(T.muted).lineSpacing(3)
                Button {
                    AppState.shared.open(.medicine(nil))
                } label: {
                    Text("إضافة دواء")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(MedColors.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .card(radius: 22)
        }
        ForEach(current, id: \.uid) { m in MedCard(med: m, now: now) }
        if !meds.isEmpty {
            Text("الدائرة = كم باقي من صلاحية العلبة بعد فتحها. تنقص يوم بيوم، وتحمرّ إذا قربت تخلص.")
                .font(.system(size: 13)).foregroundStyle(T.muted).lineSpacing(3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(T.track, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
        if !finished.isEmpty {
            SectionTitle(title: "انتهى علاجها", trailing: "\(finished.count)", color: T.muted).padding(.top, 6)
            ForEach(finished, id: \.uid) { m in
                Button {
                    AppState.shared.open(.medicine(m.uid))
                } label: {
                    HStack {
                        Text(m.name).font(.system(size: 15)).foregroundStyle(T.muted)
                        Spacer()
                        Image(systemName: "chevron.backward").font(.system(size: 13)).foregroundStyle(T.track)
                    }
                    .padding(14)
                    .card(radius: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("في المرحلة الثانية").font(.system(size: 18, weight: .bold)).foregroundStyle(T.ink)
            Text("التجديدات (الاستمارة، الرخصة، التأمين، الفحص، الجواز)، وضمانات أجهزتك مع صور فواتيرها، وصيانة السيارة بالكيلو أو بالتاريخ — بنفس الدوائر.")
                .font(.system(size: 14)).foregroundStyle(T.muted).lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 22)
    }
}

struct MedCard: View {
    let med: Medicine
    let now: Date
    @State private var confirmNewPack = false

    var body: some View {
        let left = med.daysLeft(now: now)
        let urgent = (left ?? 99) <= 3
        let color = med.openedAt == nil ? T.track : (urgent ? Color(hex: 0xB4410E) : MedColors.ink)

        VStack(alignment: .leading, spacing: 14) {
            Button {
                AppState.shared.open(.medicine(med.uid))
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color(hex: 0xEEEDE7), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: med.fractionLeft(now: now))
                            .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(left.map { "\(max(0, $0))" } ?? "—")
                                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                                .foregroundStyle(med.openedAt == nil ? T.muted : (urgent ? T.urgentInk : MedColors.ink))
                            Text(left.map { $0 >= 3 && $0 <= 10 ? "أيام" : ($0 == 1 ? "يوم" : ($0 == 2 ? "يومان" : "يوماً")) } ?? "")
                                .font(.system(size: 10)).foregroundStyle(T.muted)
                        }
                    }
                    .frame(width: 76, height: 76)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(med.name).font(.system(size: 17, weight: .bold)).foregroundStyle(T.ink)
                        Text(med.openedText).font(.system(size: 12)).foregroundStyle(T.muted)
                        Text(med.expiryText(now: now))
                            .font(.system(size: 12, weight: urgent ? .bold : .regular))
                            .foregroundStyle(urgent ? T.urgentInk : T.muted)
                        if !med.doseNote.isEmpty {
                            Text(med.doseNote).font(.system(size: 12)).foregroundStyle(MedColors.deep)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if !med.slots.isEmpty {
                HStack(spacing: 8) {
                    Text("اليوم").font(.system(size: 13)).foregroundStyle(T.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(med.slots, id: \.self) { slot in
                                doseChip(slot)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if !med.slots.isEmpty {
                    Button {
                        MedActions.takeNow(med)
                    } label: {
                        Text(med.slotToMarkNow(now: now) == nil ? "خلصت جرعات اليوم" : "أخذت جرعة الآن")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(med.slotToMarkNow(now: now) == nil ? T.track : MedColors.ink,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(med.slotToMarkNow(now: now) == nil)
                }
                Button {
                    if med.openedAt == nil { MedActions.openNewPack(med) } else { confirmNewPack = true }
                } label: {
                    Text(med.openedAt == nil ? "فتحتها اليوم" : "فتحت علبة جديدة")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(T.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.track, lineWidth: 1.5))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card(radius: 22)
        .confirmationDialog("فتحت علبة جديدة اليوم؟", isPresented: $confirmNewPack, titleVisibility: .visible) {
            Button("نعم، فتحتها اليوم") { MedActions.openNewPack(med) }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("يبدأ العدّ من جديد: \(med.shelfDays) يوماً.")
        }
    }

    private func doseChip(_ slot: Int) -> some View {
        let state = med.state(now, slot, now: now)
        return Button {
            MedActions.toggle(med, slot: slot)
        } label: {
            HStack(spacing: 4) {
                if state == .taken { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(Medicine.slotText(slot)).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .foregroundStyle(state == .taken ? Color.white : (state == .late ? T.urgentInk : MedColors.ink))
            .background(state == .taken ? MedColors.ink : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(state == .taken ? Color.clear : (state == .late ? T.urgentInk : MedColors.outline), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Medicine.slotText(slot)) \(state == .taken ? "أخذتها" : "ما أخذتها")")
    }
}

// MARK: - add / edit

struct MedicineSheet: View {
    var editingUID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name = ""
    @State private var shelfDays = 30
    @State private var customShelf = false
    @State private var opened = true
    @State private var openedDay = Date()
    @State private var slots: [Int] = []
    @State private var newTime = DF.greg.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var addingTime = false
    @State private var timesPerDay = 0     // 0 = أوقات يدوية
    @State private var firstDose = DF.greg.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var doseNote = ""
    @State private var course = 0          // 0 مستمر، 7 أسبوع، 14 أسبوعان، -1 لين تاريخ
    @State private var courseEnd = DF.addDays(14, to: Date())
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Medicine? { editingUID.flatMap { Store.medicine(uid: $0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("الاسم") {
                        TextField("مثال: قطرة العين", text: $name)
                            .font(.system(size: 17))
                            .padding(14)
                            .background(T.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MedColors.ink, lineWidth: 1.5))
                    }

                    field("صلاحيتها بعد الفتح") {
                        HStack(spacing: 8) {
                            choice("أسبوعان", on: !customShelf && shelfDays == 14) { customShelf = false; shelfDays = 14 }
                            choice("شهر", on: !customShelf && shelfDays == 30) { customShelf = false; shelfDays = 30 }
                            choice("3 أشهر", on: !customShelf && shelfDays == 90) { customShelf = false; shelfDays = 90 }
                            choice("غيره", on: customShelf) { customShelf = true }
                        }
                        if customShelf {
                            Stepper("\(shelfDays) يوماً", value: $shelfDays, in: 1...730)
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $opened) {
                            Text("فتحت العلبة").font(.system(size: 15, weight: .bold))
                        }
                        if opened {
                            DatePicker("يوم الفتح", selection: $openedDay, in: ...Date(), displayedComponents: .date)
                            Text("فتحتها \(DF.fullDate(openedDay)) · تنتهي \(DF.dayMonth(DF.addDays(shelfDays, to: DF.startOfDay(openedDay)), cal: DF.primary))")
                                .font(.system(size: 12)).foregroundStyle(T.muted)
                        } else {
                            Text("لما تفتحها اضغط «فتحتها اليوم» في أدويتي، ويبدأ العدّ.")
                                .font(.system(size: 12)).foregroundStyle(T.muted)
                        }
                    }
                    .padding(14)
                    .card(T.bg, radius: 18)

                    field("أوقات الجرعات") {
                        HStack(spacing: 8) {
                            countButton("مرة", 1)
                            countButton("مرتين", 2)
                            countButton("3 مرات", 3)
                            countButton("4 مرات", 4)
                        }
                        if timesPerDay > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("أول جرعة").font(.system(size: 15, weight: .semibold))
                                    if timesPerDay > 1 {
                                        Text(verbatim: "والباقي كل \(24 / timesPerDay) ساعات تلقائياً")
                                            .font(.system(size: 12)).foregroundStyle(T.muted)
                                    }
                                }
                                Spacer()
                                DatePicker("أول جرعة", selection: $firstDose, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            .padding(12)
                            .background(MedColors.soft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(slots.sorted(), id: \.self) { slot in
                                Button {
                                    slots.removeAll { $0 == slot }
                                    timesPerDay = 0
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(Medicine.slotText(slot)).font(.system(size: 14, weight: .bold))
                                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(MedColors.deep)
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background(MedColors.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("احذف \(Medicine.slotText(slot))")
                            }
                            Button {
                                addingTime.toggle()
                            } label: {
                                Text("+ وقت")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MedColors.ink)
                                    .padding(.horizontal, 14)
                                    .frame(height: 40)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(MedColors.ink, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }
                            .buttonStyle(.plain)
                        }
                        if addingTime {
                            HStack {
                                DatePicker("الوقت", selection: $newTime, displayedComponents: .hourAndMinute)
                                Button("أضف") {
                                    let c = DF.greg.dateComponents([.hour, .minute], from: newTime)
                                    let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                                    if !slots.contains(m) { slots.append(m) }
                                    timesPerDay = 0
                                    addingTime = false
                                }
                                .font(.system(size: 15, weight: .bold))
                            }
                        }
                        TextField("الكمية، مثال: قطرة وحدة في كل عين", text: $doseNote)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(T.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(T.track, lineWidth: 1.5))
                        Text(slots.isEmpty ? "بدون أوقات: يتابع الصلاحية فقط بدون تذكير بالجرعات."
                                           : "يذكّرك بكل جرعة، ويرجع كل 15 دقيقة لين تضغط «أخذتها».")
                            .font(.system(size: 12)).foregroundStyle(T.muted)
                    }

                    field("مدة العلاج") {
                        HStack(spacing: 8) {
                            choice("مستمر", on: course == 0) { course = 0 }
                            choice("أسبوع", on: course == 7) { course = 7 }
                            choice("أسبوعان", on: course == 14) { course = 14 }
                            choice("لين تاريخ", on: course == -1) { course = -1 }
                        }
                        if course == -1 {
                            DatePicker("آخر يوم", selection: $courseEnd, displayedComponents: .date)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("حفظ")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? T.track : MedColors.ink,
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white)
            }
            .navigationTitle(editing == nil ? "دواء جديد" : "تعديل الدواء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                if editing != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("حذف")
                    }
                }
            }
            .confirmationDialog("تحذف الدواء؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف", role: .destructive) {
                    if let m = editing { MedActions.delete(m) }
                    dismiss()
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .onAppear(perform: load)
        .onChange(of: firstDose) { _, _ in fillEvenly() }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            content()
        }
    }

    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: on ? .bold : .regular))
                .foregroundStyle(on ? MedColors.deep : T.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? MedColors.soft : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? MedColors.ink : T.track, lineWidth: on ? 2 : 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// «4 مرات» + أول جرعة 4 م → 4 م، 10 م، 4 ص، 10 ص (every 24/n hours).
    private func countButton(_ title: String, _ n: Int) -> some View {
        choice(title, on: timesPerDay == n) {
            timesPerDay = n
            fillEvenly()
        }
    }

    private func fillEvenly() {
        guard timesPerDay > 0 else { return }
        let c = DF.greg.dateComponents([.hour, .minute], from: firstDose)
        let start = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let step = 24 * 60 / timesPerDay
        slots = (0..<timesPerDay).map { (start + $0 * step) % (24 * 60) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let m = editing else { return }
        name = m.name
        shelfDays = m.shelfDays
        customShelf = ![14, 30, 90].contains(m.shelfDays)
        opened = m.openedAt != nil
        openedDay = m.openedAt ?? Date()
        slots = m.slots
        let sorted = m.slots.sorted()
        if !sorted.isEmpty, (24 * 60) % sorted.count == 0 {
            let step = 24 * 60 / sorted.count
            let even = zip(sorted, sorted.dropFirst()).allSatisfy { $1 - $0 == step }
            if even {
                timesPerDay = sorted.count
                firstDose = DF.greg.date(bySettingHour: sorted[0] / 60, minute: sorted[0] % 60, second: 0, of: Date()) ?? firstDose
            }
        }
        doseNote = m.doseNote
        if let end = m.courseEnd {
            course = -1
            courseEnd = end
        }
    }

    private func save() {
        let m: Medicine
        if let e = editing {
            m = e
        } else {
            m = Medicine(name: name)
            ctx.insert(m)
        }
        m.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        m.shelfDays = max(1, shelfDays)
        m.openedAt = opened ? DF.startOfDay(openedDay) : nil
        m.doseMinutes = slots.sorted()
        m.doseNote = doseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        switch course {
        case 0: m.courseEnd = nil
        case -1: m.courseEnd = DF.startOfDay(courseEnd)
        default:
            if editing?.courseEnd == nil || editing == nil {
                m.courseEnd = DF.addDays(course - 1, to: DF.startOfDay(Date()))
            }
        }
        try? ctx.save()
        Scheduler.shared.rebuildSoon()
        dismiss()
    }
}
