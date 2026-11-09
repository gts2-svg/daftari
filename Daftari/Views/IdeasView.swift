import SwiftUI
import SwiftData

struct IdeasView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var ctx
    @State private var text = ""
    @FocusState private var focused: Bool

    private var notes: [Entry] { entries.filter { $0.kind == .idea || $0.kind == .journal } }

    private var groups: [(key: String, title: String, items: [Entry])] {
        var order: [String] = []
        var map: [String: [Entry]] = [:]
        var titles: [String: String] = [:]
        for e in notes {
            let k = DF.dayKey(e.createdAt)
            if map[k] == nil { order.append(k); titles[k] = DF.relativeDay(e.createdAt) }
            map[k, default: []].append(e)
        }
        return order.map { ($0, titles[$0] ?? "", map[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("الأفكار").font(.system(size: 30, weight: .bold)).foregroundStyle(T.ink)

                    Button {
                        AppState.shared.open(.voice(.idea))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(T.accent)
                                .frame(width: 60, height: 60)
                                .background(Color.white, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("قلها بصوتك").font(.system(size: 17, weight: .bold))
                                Text("تتحول لنص داخل جوالك، وتقدر تخليها مهمة").font(.system(size: 13)).opacity(0.9)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(T.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        TextField("أو اكتبها هنا…", text: $text, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focused)
                            .padding(14)
                            .card(radius: 16)
                        Button("أضف", action: add)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 50)
                            .background(text.trimmingCharacters(in: .whitespaces).isEmpty ? T.track : T.ink,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if notes.isEmpty {
                        Text("أي فكرة تمر عليك، قلها أو اكتبها هنا. وتطلع لك هنا مرتبة بالأيام.")
                            .font(.system(size: 14)).foregroundStyle(T.muted)
                            .padding(.top, 8)
                    }

                    ForEach(groups, id: \.key) { group in
                        SectionTitle(title: group.title, trailing: "\(group.items.count)")
                            .padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.uid) { idx, e in
                                if idx > 0 { Divider().overlay(T.line) }
                                noteRow(e)
                            }
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .keyboardDone()
            .background(T.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func noteRow(_ e: Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: e.kind == .journal ? "book.closed" : "lightbulb")
                .font(.system(size: 15))
                .foregroundStyle(e.kind == .journal ? T.accent : T.ideaInk)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.system(size: 15)).foregroundStyle(T.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(e.kind == .journal ? "يومية · \(DF.time(e.createdAt))" : DF.time(e.createdAt))
                    .font(.system(size: 12)).foregroundStyle(T.muted)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .contextMenu {
            Button("حوّلها لمهمة", systemImage: "checklist") { AppState.shared.open(.convert(e.uid)) }
            Button("انسخ", systemImage: "doc.on.doc") { UIPasteboard.general.string = e.title }
            Button("حذف", systemImage: "trash", role: .destructive) { EntryActions.delete(e) }
        }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        ctx.insert(Entry(title: t, kind: .idea))
        try? ctx.save()
        text = ""
        focused = false
    }
}
