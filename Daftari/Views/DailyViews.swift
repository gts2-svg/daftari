import SwiftUI
import SwiftData

/// «وش صار اليوم؟» — opens from the 8 pm alert.
struct EveningCheckView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss
    @State private var moved: Set<UUID> = []
    @State private var showVoice = false
    @State private var note = ""

    private var items: [Entry] {
        let now = Date()
        let today = DF.startOfDay(now)
        return entries.filter { e in
            guard e.isScheduledKind, let d = e.date else { return false }
            if moved.contains(e.uid) { return true }
            if DF.greg.isDate(d, inSameDayAs: now) { return true }
            return d < today && e.isOpen
        }
        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(DF.time(Date())) · \(DF.weekday(Date()))").font(.system(size: 14)).foregroundStyle(T.nightMuted)
                    Text("وش صار اليوم؟").font(.system(size: 32, weight: .bold))
                    Text("علّم على اللي صار، والباقي انقله لبكرة.").font(.system(size: 14)).foregroundStyle(T.nightMuted)
                }

                if items.isEmpty {
                    Text("ما كان عندك مواعيد أو مهام اليوم. قل وش صار بصوتك أو اكتبه تحت.")
                        .font(.system(size: 14)).foregroundStyle(T.nightMuted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(T.nightCard, radius: 18)
                }

                ForEach(items, id: \.uid) { e in row(e) }

                Button {
                    showVoice = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(T.nightBg)
                            .frame(width: 62, height: 62)
                            .background(T.gold, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("شيء ثاني صار؟").font(.system(size: 16, weight: .bold))
                            Text("قله بصوتك، ويتحفظ في يومياتك").font(.system(size: 13)).foregroundStyle(T.nightMuted)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .card(T.nightCard, radius: 24)
                }
                .buttonStyle(.plain)

                TextField("", text: $note, prompt: Text("أو اكتب هنا…").foregroundStyle(T.nightMuted), axis: .vertical)
                    .lineLimit(1...5)
                    .padding(14)
                    .card(T.nightCard, radius: 16)

                Button {
                    EntryActions.addJournal(note)
                    Prefs.markEveningLogged()
                    Scheduler.shared.rebuildSoon()
                    dismiss()
                } label: {
                    Text("خلصت")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(T.nightBg)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(T.nightText, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .foregroundStyle(T.nightText)
        .background(T.nightBg.ignoresSafeArea())
        .keyboardDone()
        .fullScreenCover(isPresented: $showVoice) {
            VoiceCaptureView(mode: .journal).daftariEnvironment()
        }
    }

    private func row(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(e.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if let d = e.date {
                    Text(e.hasTime ? DF.time(d) : DF.relativeDay(d)).font(.system(size: 13)).foregroundStyle(T.nightMuted)
                }
            }
            if moved.contains(e.uid) {
                Text("انتقلت لبكرة").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.gold)
            } else {
                HStack(spacing: 6) {
                    choice("تم", on: e.isDone, color: T.nightGreen) { EntryActions.markDone(e) }
                    choice("ما صار", on: e.isCancelled, color: T.nightMuted) { EntryActions.markMissed(e) }
                    choice("لبكرة", on: false, color: T.gold) {
                        moved.insert(e.uid)
                        EntryActions.postpone(e)
                    }
                }
            }
        }
        .padding(14)
        .card(T.nightCard, radius: 18)
    }

    private func choice(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: on ? .bold : .regular))
                .foregroundStyle(on ? T.nightBg : T.nightText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? color : T.nightButton, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// «رسالة الصباح» — opens from the 8 am alert.
struct MorningBriefView: View {
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let now = Date()
        let items = Agenda.items(on: now, entries: entries, includeClosed: false)
        let overdue = Agenda.overdue(entries: entries, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(DF.time(now)) · \(DF.weekday(now))").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0x7A5A20))
                    Text(verbatim: "\(DF.greeting(now))\nهذا يومك").font(.system(size: 32, weight: .bold)).lineSpacing(4)
                    Text(DF.fullDate(now)).font(.system(size: 14)).foregroundStyle(Color(hex: 0x6B5A40))
                }

                HStack(spacing: 8) {
                    counter(items.filter { $0.importance == .urgent }.count, "ضروري", T.urgentInk)
                    counter(items.filter { $0.importance == .important }.count, "مهم", T.taskInk)
                    counter(items.filter { $0.importance == .normal }.count, "عادي", T.normalInk)
                }

                if items.isEmpty {
                    Text("يومك فاضي من المواعيد. أي شيء ببالك أضفه من زر +.")
                        .font(.system(size: 15)).foregroundStyle(Color(hex: 0x6B5A40))
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card(radius: 22)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { Divider().overlay(Color(hex: 0xF1E6CF)) }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.hasTime ? DF.time(item.date ?? now) : "طول اليوم")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(T.ink(item.importance))
                                    .frame(width: 74, alignment: .leading)
                                Text(item.title).font(.system(size: 15))
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .card(radius: 22)
                }

                let pending = entries.filter(\.isPending)
                if !pending.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "معلّقة عندك · \(pending.count)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(T.taskInk)
                            .padding(.vertical, 10)
                        ForEach(pending.prefix(5), id: \.uid) { e in
                            HStack(spacing: 10) {
                                Button {
                                    EntryActions.markDone(e)
                                } label: {
                                    Image(systemName: "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color(hex: 0xC9A15A))
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("علّم «\(e.title)» كمنجز")
                                Text(e.title).font(.system(size: 15))
                                Spacer()
                                if e.isNagging {
                                    Button("مو اليوم") { EntryActions.notToday(e) }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(hex: 0x6B5A40))
                                        .frame(minHeight: 40)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .card(radius: 22)
                }

                if !overdue.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "clock").foregroundStyle(T.urgentInk)
                        Text("عندك \(overdue.count) متأخرة من أيام سابقة").font(.system(size: 14)).foregroundStyle(Color(hex: 0x6B2A0B))
                        Spacer()
                    }
                    .padding(14)
                    .card(T.urgentSoft, radius: 18)
                }

                Button {
                    dismiss()
                } label: {
                    Text("ابدأ يومي")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(T.morningInk, in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }
            .padding(22)
        }
        .foregroundStyle(T.morningInk)
        .background(T.morningBg.ignoresSafeArea())
    }

    private func counter(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(n)").font(.system(size: 26, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(Color(hex: 0x6B5A40))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card(radius: 18)
    }
}
