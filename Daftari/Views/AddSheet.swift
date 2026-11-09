import SwiftUI
import SwiftData

/// «إضافة سريعة»: write it the way you'd say it; the date, time and type are picked up on their own.
struct AddSheet: View {
    var prefill: String = ""
    var presetDate: Date? = nil
    var presetKind: EntryKind? = nil
    var editingUID: UUID? = nil
    var convertUID: UUID? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @AppStorage(Prefs.Key.defaultLead) private var defaultLead = 60
    @StateObject private var speech = SpeechService()

    @State private var text = ""
    @State private var kind: EntryKind = .task
    @State private var hasDate = false
    @State private var day = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var importance: Importance = .normal
    @State private var lead = 60
    @State private var manualDate = false
    @State private var manualKind = false
    @State private var loaded = false
    @State private var dictationBase = ""
    @State private var confirmDelete = false
    @State private var nagDays = 3
    @AppStorage(Prefs.Key.nag) private var nagMinutes = 17 * 60

    private var editing: Entry? { editingUID.flatMap { Store.entry(uid: $0) } }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputField
                    if kind != .idea && hasDate { detectedChips }
                    kindPicker
                    if kind != .idea {
                        dateCard
                        if !hasDate { nagCard }
                        importanceCard
                        if hasDate { ladderCard }
                    }
                    if let err = speech.errorText {
                        Text(err).font(.system(size: 13)).foregroundStyle(T.urgentInk)
                    }
                    if editing != nil {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("احذفه نهائياً", systemImage: "trash")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(T.urgentInk)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .keyboardDone()
            .background(Color.white)
            .safeAreaInset(edge: .bottom) { saveBar }
            .navigationTitle(editing == nil ? "إضافة" : "تعديل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { speech.cancel(); dismiss() }
                }
                if editing != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("حذف")
                    }
                }
            }
            .confirmationDialog("تحذفه؟", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("حذف", role: .destructive) { deleteEditing() }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, _ in if loaded { applyParse() } }
        .onChange(of: speech.transcript) { _, t in
            guard !t.isEmpty else { return }
            text = dictationBase.isEmpty ? t : dictationBase + " " + t
        }
        .onDisappear { speech.cancel() }
    }

    // MARK: sections

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("اكتب كما تتكلم").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            HStack(alignment: .top, spacing: 8) {
                TextField("مثال: موعد الأسنان الثلاثاء 4 العصر", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 17))
                    .padding(14)
                    .background(T.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.accent, lineWidth: 1.5))
                Button {
                    toggleDictation()
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(speech.isRecording ? Color.white : T.accent)
                        .frame(width: 52, height: 52)
                        .background(speech.isRecording ? T.urgentInk : T.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel(speech.isRecording ? "أوقف الإملاء" : "إملاء بالصوت")
            }
        }
    }

    private var detectedChips: some View {
        let d = combinedDate
        var chips = [kind.label, "\(DF.weekday(d)) \(DF.fullDate(d, year: false))"]
        if hasTime { chips.append(DF.time(d)) }
        return FlowRow(items: chips)
    }

    private var kindPicker: some View {
        Picker("النوع", selection: Binding(get: { kind }, set: { kind = $0; manualKind = true })) {
            ForEach([EntryKind.appointment, .task, .idea], id: \.self) { k in
                Text(k.label).tag(k)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("له تاريخ", isOn: Binding(get: { hasDate }, set: { hasDate = $0; manualDate = true }))
                .font(.system(size: 15, weight: .semibold))
            if hasDate {
                DatePicker("اليوم", selection: Binding(get: { day }, set: { day = $0; manualDate = true }),
                           displayedComponents: .date)
                Text(verbatim: "\(DF.weekday(day)) · \(DF.fullDate(day))")
                    .font(.system(size: 13)).foregroundStyle(T.muted)
                Toggle("له وقت", isOn: Binding(get: { hasTime }, set: { hasTime = $0; manualDate = true }))
                    .font(.system(size: 15, weight: .semibold))
                if hasTime {
                    DatePicker("الوقت", selection: Binding(get: { time }, set: { time = $0; manualDate = true }),
                               displayedComponents: .hourAndMinute)
                }
            }
        }
        .padding(16)
        .card(T.bg, radius: 18)
    }

    /// No date? Then it nudges every few days until «تم» (تغيير الزيت، تجديد…).
    private var nagCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ما له وقت محدد؟ ذكّرني فيه لين أخلّصه").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            HStack(spacing: 6) {
                ForEach([(0, "لا"), (1, "كل يوم"), (2, "يومين"), (3, "3 أيام"), (7, "أسبوع")], id: \.0) { opt in
                    let on = nagDays == opt.0
                    Button {
                        nagDays = opt.0
                    } label: {
                        Text(opt.1)
                            .font(.system(size: 14, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? T.taskInk : T.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? T.taskSoft : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(on ? T.taskInk : T.track, lineWidth: on ? 2 : 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(nagDays == 0
                 ? "يطلع لك تحت «معلّقة» وفي رسالة الصباح بس."
                 : "يطلع لك تحت «معلّقة» وفي رسالة الصباح، ويوصلك تذكير الساعة \(nagTimeText) \(nagEveryText) لين تضغط «تم». وفيه زر «مو اليوم».")
                .font(.system(size: 12)).foregroundStyle(T.muted)
        }
        .padding(16)
        .card(T.bg, radius: 18)
    }

    private var nagTimeText: String {
        DF.time(DF.startOfDay(Date()).addingTimeInterval(TimeInterval(nagMinutes * 60)))
    }

    private var nagEveryText: String {
        switch nagDays {
        case 1: return "كل يوم"
        case 2: return "كل يومين"
        case 7: return "كل أسبوع"
        default: return "كل \(nagDays) أيام"
        }
    }

    private var importanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("الأهمية").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            HStack(spacing: 8) {
                ForEach(Importance.allCases, id: \.self) { i in
                    let on = importance == i
                    Button {
                        importance = i
                    } label: {
                        VStack(spacing: 2) {
                            Text(i.label).font(.system(size: 15, weight: on ? .bold : .semibold))
                            Text(i.hint).font(.system(size: 11))
                        }
                        .foregroundStyle(T.ink(i))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(on ? T.soft(i) : Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(on ? T.ink(i) : T.track, lineWidth: on ? 2 : 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if importance == .urgent {
                HStack {
                    Text("المنبّه يرن قبل الموعد بـ").font(.system(size: 14))
                    Spacer()
                    Picker("المنبّه قبل الموعد", selection: $lead) {
                        Text("وقت الموعد").tag(0)
                        Text("15 دقيقة").tag(15)
                        Text("30 دقيقة").tag(30)
                        Text("ساعة").tag(60)
                        Text("ساعتين").tag(120)
                        Text("يوم").tag(1440)
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("يذكّرك كذا").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
            ForEach(Array(ladder.enumerated()), id: \.offset) { _, step in
                HStack(spacing: 8) {
                    Circle().fill(step.strong ? T.urgentInk : Color(hex: 0xC9A15A)).frame(width: 8, height: 8)
                    Text(step.when).font(.system(size: 14, weight: step.strong ? .bold : .regular))
                    Spacer()
                    Text(step.how).font(.system(size: 13, weight: step.strong ? .bold : .regular))
                        .foregroundStyle(step.strong ? T.urgentInk : T.muted)
                }
            }
        }
        .padding(16)
        .card(T.field, radius: 18)
    }

    private var ladder: [(when: String, how: String, strong: Bool)] {
        let at = hasTime ? "وقت الموعد \(DF.time(combinedDate))" : "الساعة 9:00 ص"
        let morning = "صباح يوم الموعد \(DF.time(DF.startOfDay(Date()).addingTimeInterval(TimeInterval(Prefs.morningMinutes * 60))))"
        switch importance {
        case .normal:
            return [(morning, "في رسالة الصباح", false)] + (hasTime ? [(at, "إشعار", false)] : [])
        case .important:
            return [("قبل يوم 8:00 م", "إشعار مهم", false), (morning, "في رسالة الصباح", false),
                    (at, "يتكرر كل 30 دقيقة لين «تم»", true)]
        case .urgent:
            let leadText: String = {
                switch lead {
                case 0: return "وقت الموعد"
                case 15: return "قبل 15 دقيقة"
                case 30: return "قبل 30 دقيقة"
                case 60: return "قبل ساعة"
                case 120: return "قبل ساعتين"
                default: return "قبل يوم"
                }
            }()
            return [("قبل أسبوع", "إشعار", false), ("قبل يوم 8:00 م", "إشعار مهم", false),
                    (morning, "في رسالة الصباح", false), (leadText, "منبّه حقيقي", true),
                    (at, "يتكرر لين «تم»", true)]
        }
    }

    private var saveBar: some View {
        Button(action: save) {
            Text("حفظ")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(trimmed.isEmpty ? T.track : T.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(trimmed.isEmpty)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    // MARK: logic

    private var combinedDate: Date {
        let g = DF.greg
        let d = g.dateComponents([.year, .month, .day], from: day)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        if hasTime {
            let t = g.dateComponents([.hour, .minute], from: time)
            c.hour = t.hour; c.minute = t.minute
        } else {
            c.hour = 0; c.minute = 0
        }
        return g.date(from: c) ?? day
    }

    private func load() {
        guard !loaded else { return }
        lead = defaultLead
        if let e = editing {
            text = e.title
            kind = e.kind
            importance = e.importance
            lead = e.alarmLeadMinutes
            nagDays = e.date == nil ? e.nagDays : 3
            if let d = e.date {
                hasDate = true; day = d; hasTime = e.hasTime; time = d
            }
            manualDate = true
            manualKind = true
        } else if let cu = convertUID, let src = Store.entry(uid: cu) {
            text = src.title
            kind = .task
            applyParse()
        } else {
            text = prefill
            if let presetDate {
                hasDate = true; day = presetDate; manualDate = true
            }
            if let presetKind { kind = presetKind; manualKind = true }
            if !prefill.isEmpty { applyParse() }
        }
        Task { @MainActor in loaded = true }
    }

    private func applyParse() {
        guard editing == nil else { return }
        let p = ArabicDateParser.parse(text)
        if !manualDate {
            if let d = p.date {
                hasDate = true
                day = d
                hasTime = p.hasTime
                if p.hasTime { time = d }
            } else {
                hasDate = false
                hasTime = false
            }
        }
        if !manualKind {
            kind = p.kind
        }
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stop()
        } else {
            dictationBase = trimmed
            Task { await speech.start() }
        }
    }

    private func save() {
        speech.cancel()
        let parsed = ArabicDateParser.parse(text)
        let title: String = {
            if editing != nil { return trimmed }
            if !manualDate && parsed.date != nil { return parsed.title }
            return trimmed
        }()
        let date: Date? = (kind != .idea && hasDate) ? combinedDate : nil

        let entry: Entry
        if let e = editing {
            entry = e
        } else {
            entry = Entry(title: title, kind: kind)
            ctx.insert(entry)
        }
        entry.title = title
        entry.kind = kind
        entry.date = date
        entry.hasTime = date != nil && hasTime
        entry.importance = kind == .idea ? .normal : importance
        entry.alarmLeadMinutes = lead
        entry.snoozeUntil = nil
        if date == nil && kind != .idea {
            if entry.nagDays != nagDays || entry.nagNext == nil {
                entry.nagNext = DF.addDays(1, to: DF.startOfDay(Date()))
            }
            entry.nagDays = nagDays
        } else {
            entry.nagDays = 0
            entry.nagNext = nil
        }
        if let cu = convertUID, let src = Store.entry(uid: cu), src.uid != entry.uid {
            ctx.delete(src)
        }
        try? ctx.save()
        Scheduler.shared.rebuildSoon()
        dismiss()
    }

    private func deleteEditing() {
        guard let e = editing else { return }
        ctx.delete(e)
        try? ctx.save()
        Scheduler.shared.rebuildSoon()
        dismiss()
    }
}

/// Small rounded labels that wrap onto new lines.
struct FlowRow: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.accentDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(T.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
