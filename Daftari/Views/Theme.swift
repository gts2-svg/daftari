import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Colours from the chosen «هادئ» designs.
enum T {
    static let bg = Color(hex: 0xF5F1E8)
    static let field = Color(hex: 0xFAF8F3)
    static let card = Color.white
    static let ink = Color(hex: 0x1E2A2B)
    static let muted = Color(hex: 0x5E6866)
    static let line = Color(hex: 0xEDE7DA)
    static let track = Color(hex: 0xE3DCCB)
    static let accent = Color(hex: 0x1D6A63)
    static let accentSoft = Color(hex: 0xDCEBE7)
    static let accentDeep = Color(hex: 0x14524C)
    static let taskInk = Color(hex: 0x7A4F00)
    static let taskSoft = Color(hex: 0xFCEFCF)
    static let ideaInk = Color(hex: 0x55407A)
    static let ideaSoft = Color(hex: 0xEEE8F6)
    static let habitInk = Color(hex: 0x22633A)
    static let habitSoft = Color(hex: 0xE3F1E7)
    static let urgentInk = Color(hex: 0xA63A0B)
    static let urgentSoft = Color(hex: 0xFBE2D5)
    static let normalInk = Color(hex: 0x3F4E5C)
    static let normalSoft = Color(hex: 0xE8EDF2)
    static let systemDot = Color(hex: 0x6B7C8C)
    static let morningBg = Color(hex: 0xFFF1D6)
    static let morningInk = Color(hex: 0x2A1E0E)
    static let nightBg = Color(hex: 0x142033)
    static let nightCard = Color(hex: 0x1D2C44)
    static let nightButton = Color(hex: 0x2A3B57)
    static let nightText = Color(hex: 0xEEF2F6)
    static let nightMuted = Color(hex: 0xA9B8CC)
    static let nightGreen = Color(hex: 0x5CC08F)
    static let gold = Color(hex: 0xF2B544)

    static func ink(_ i: Importance) -> Color {
        switch i {
        case .normal: return normalInk
        case .important: return taskInk
        case .urgent: return urgentInk
        }
    }

    static func soft(_ i: Importance) -> Color {
        switch i {
        case .normal: return normalSoft
        case .important: return taskSoft
        case .urgent: return urgentSoft
        }
    }
}

struct ImportanceBadge: View {
    let importance: Importance
    var body: some View {
        Text(importance.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(T.ink(importance))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(T.soft(importance), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct CardBackground: ViewModifier {
    var color: Color = T.card
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content.background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(_ color: Color = T.card, radius: CGFloat = 20) -> some View {
        modifier(CardBackground(color: color, radius: radius))
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var color: Color = T.ink
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(color)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 13)).foregroundStyle(T.muted)
            }
        }
    }
}

/// One row: tick circle (ours) or calendar icon (iPhone), title, when, importance.
struct ItemRow: View {
    let item: DayItem
    var showDay = false

    var body: some View {
        HStack(spacing: 12) {
            if let e = item.entry {
                Button {
                    EntryActions.toggleDone(e)
                } label: {
                    Image(systemName: e.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(e.isDone ? T.accent : T.track)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.isDone ? "منجز، اضغط للتراجع" : "علّم كمنجز")
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 18))
                    .foregroundStyle(T.systemDot)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? T.muted : T.ink)
                    .lineLimit(2)
                Text(whenLine)
                    .font(.system(size: 12))
                    .foregroundStyle(T.muted)
            }
            Spacer(minLength: 4)
            if item.importance != .normal && !item.isDone {
                ImportanceBadge(importance: item.importance)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let e = item.entry { AppState.shared.open(.edit(e.uid)) }
        }
        .contextMenu {
            if let e = item.entry {
                if e.isNagging {
                    Button("مو اليوم", systemImage: "moon.zzz") { EntryActions.notToday(e) }
                }
                Button("لبكرة", systemImage: "arrow.uturn.backward") { EntryActions.postpone(e) }
                Button("تعديل", systemImage: "pencil") { AppState.shared.open(.edit(e.uid)) }
                Button("حذف", systemImage: "trash", role: .destructive) { EntryActions.delete(e) }
            }
        }
    }

    private var whenLine: String {
        var parts: [String] = []
        if let d = item.date {
            if showDay { parts.append(DF.relativeDay(d)) }
            parts.append(item.hasTime ? DF.time(d) : (showDay ? "" : "طول اليوم"))
        }
        if item.date == nil, let e = item.entry, e.isScheduledKind {
            parts.append(e.nagLabel)
        }
        if item.isSystem { parts.append("تقويم الآيفون") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ItemList: View {
    let items: [DayItem]
    var showDay = false
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Divider().overlay(T.line).padding(.leading, 60) }
                ItemRow(item: item, showDay: showDay)
            }
        }
        .padding(.vertical, 4)
        .card()
    }
}

/// A «تم» button above the keyboard (multi-line fields have no return-to-close),
/// and dragging the page closes the keyboard too.
struct KeyboardDone: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .scrollBounceBehavior(.always)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 16, weight: .bold))
                }
            }
    }
}

extension View {
    func keyboardDone() -> some View { modifier(KeyboardDone()) }
}
