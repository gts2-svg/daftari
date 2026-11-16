import SwiftUI
import SwiftData

/// One search over everything: appointments, tasks, ideas, journal, medicines, lists, trips.
/// With nothing typed it shows what's coming («الجاي»), so nothing needs digging through days.
struct SearchAllView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query(sort: \Medicine.createdAt) private var meds: [Medicine]
    @Query(sort: \PackList.createdAt) private var packs: [PackList]
    @Query(sort: \SplitTrip.createdAt) private var trips: [SplitTrip]
    @ObservedObject private var app = AppState.shared
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField("ابحث في كل شيء…", text: $query)
                        .font(.dyn(17))
                        .focused($focused)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.muted) }
                            .accessibilityLabel("امسح")
                    }
                }
                .padding(14)
                .card(radius: 16)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    upcoming
                } else {
                    results
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(T.bg.ignoresSafeArea())
        .navigationTitle("بحث")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    // MARK: nothing typed: what's coming

    @ViewBuilder
    private var upcoming: some View {
        let now = Date()
        let next = entries
            .filter { $0.isScheduledKind && $0.isOpen && ($0.anchorDate ?? .distantPast) > DF.startOfDay(now) }
            .sorted { ($0.anchorDate ?? now) < ($1.anchorDate ?? now) }
        SectionTitle(title: "الجاي", trailing: next.isEmpty ? nil : "\(next.count)")
        if next.isEmpty {
            Text("ما عندك مواعيد ولا مهام قادمة.").font(.dyn(15)).foregroundStyle(T.muted)
        } else {
            ItemList(items: next.prefix(40).map(DayItem.init(entry:)), showDay: true)
        }
    }

    // MARK: results

    private func matches(_ text: String) -> Bool {
        let q = Self.norm(query)
        return !q.isEmpty && Self.norm(text).contains(q)
    }

    /// Same folding as the date parser: أ/إ/آ = ا, ة = ه, ى = ي, no tashkeel.
    static func norm(_ s: String) -> String {
        ArabicDateParser.fold(ArabicDateParser.clean(s)).lowercased().trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private var results: some View {
        let found = entries.filter { matches($0.title) }
            .sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) }
        let scheduled = found.filter { $0.isScheduledKind }
        let notes = found.filter { !$0.isScheduledKind }
        let medHits = meds.filter { matches($0.name) || matches($0.doseNote) }
        let packHits = packs.filter { p in matches(p.name) || p.items.contains { matches($0.text) } }
        let tripHits = trips.filter { t in matches(t.name) || t.expenses.contains { matches($0.note) } }

        if found.isEmpty && medHits.isEmpty && packHits.isEmpty && tripHits.isEmpty {
            Text("ما لقيت شيء بهذا الاسم.").font(.dyn(15)).foregroundStyle(T.muted)
        }
        if !scheduled.isEmpty {
            SectionTitle(title: "مواعيد ومهام", trailing: "\(scheduled.count)")
            ItemList(items: scheduled.prefix(40).map(DayItem.init(entry:)), showDay: true)
        }
        if !notes.isEmpty {
            SectionTitle(title: "أفكار ويوميات", trailing: "\(notes.count)")
            VStack(spacing: 0) {
                ForEach(notes.prefix(40)) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title).font(.dyn(16)).foregroundStyle(T.ink)
                        Text("\(e.kind.label) · \(DF.fullDate(e.createdAt))").font(.dyn(13)).foregroundStyle(T.muted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().overlay(T.line)
                }
            }
            .card()
        }
        if !medHits.isEmpty {
            SectionTitle(title: "أدويتي", trailing: "\(medHits.count)")
            ForEach(medHits) { m in
                link(m.name, sub: m.openedText, icon: "pills") { app.thingsSection = 0; app.tab = 3 }
            }
        }
        if !packHits.isEmpty {
            SectionTitle(title: "قوائم الأغراض", trailing: "\(packHits.count)")
            ForEach(packHits) { p in
                link(p.displayName, sub: "\(p.doneCount) من \(p.total)", icon: "checklist") {
                    UserDefaults.standard.set(0, forKey: "packSub"); app.thingsSection = 1; app.tab = 3; app.openPack = p.uid
                }
            }
        }
        if !tripHits.isEmpty {
            SectionTitle(title: "القطة", trailing: "\(tripHits.count)")
            ForEach(tripHits) { t in
                link(t.name, sub: DF.fullDate(t.tripDate), icon: "banknote") {
                    UserDefaults.standard.set(1, forKey: "packSub"); app.thingsSection = 1; app.tab = 3; app.openSplit = t.uid
                }
            }
        }
    }

    private func link(_ title: String, sub: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.dyn(17, weight: .semibold)).foregroundStyle(T.accent)
                    .frame(width: 36, height: 36).background(T.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.dyn(16, weight: .semibold)).foregroundStyle(T.ink)
                    Text(sub).font(.dyn(13)).foregroundStyle(T.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.dyn(12, weight: .bold)).foregroundStyle(T.muted)
            }
            .padding(12)
            .card(radius: 16)
        }
        .buttonStyle(.plain)
    }
}
