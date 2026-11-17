import SwiftUI

extension Font {
    /// Almarai, following the phone's text size setting (Settings › Display › Text Size),
    /// capped so very large settings don't break the layout.
    static func dyn(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        return .custom(AppFont.name(weight), fixedSize: min(scaled, size * 1.6))
    }

    /// Almarai at a fixed size (the PDF report must not grow with the text size setting).
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(weight), fixedSize: size)
    }
}

enum AppFont {
    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "Almarai-Light"
        case .semibold, .bold: return "Almarai-Bold"
        case .heavy, .black: return "Almarai-ExtraBold"
        default: return "Almarai-Regular"
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> UIFont {
        UIFont(name: name(weight), size: size) ?? .systemFont(ofSize: size)
    }

    /// Navigation titles, segmented pickers and tab labels in Almarai too.
    static func applyAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.font: ui(17, .bold)]
        nav.largeTitleTextAttributes = [.font: ui(30, .heavy)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: ui(14)], for: .normal)
        seg.setTitleTextAttributes([.font: ui(14, .bold)], for: .selected)
        UITabBarItem.appearance().setTitleTextAttributes([.font: ui(11)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: ui(11, .bold)], for: .selected)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: ui(17)], for: .normal)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The new light design: airy grey-white background, white cards with a soft shadow,
/// one teal accent; red only for «ضروري», amber for «مهم».
enum T {
    static let bg = Color(hex: 0xF6F7FB)
    static let field = Color(hex: 0xF9FAFB)
    static let card = Color.white
    static let ink = Color(hex: 0x111827)
    static let muted = Color(hex: 0x6B7280)
    static let line = Color(hex: 0xF0F1F4)
    static let track = Color(hex: 0xE5E7EB)
    /// Outlines that must be seen (tick circles, choice borders): ≥ 3:1 on white.
    static let outline = Color(hex: 0x9CA3AF)
    static let accent = Color(hex: 0x0F766E)
    static let accentSoft = Color(hex: 0xCCFBF1)
    static let accentDeep = Color(hex: 0x115E59)
    static let taskInk = Color(hex: 0x92400E)
    static let taskSoft = Color(hex: 0xFEF3C7)
    static let ideaInk = Color(hex: 0x5B21B6)
    static let ideaSoft = Color(hex: 0xEDE9FE)
    static let habitInk = Color(hex: 0x166534)
    static let habitSoft = Color(hex: 0xDCFCE7)
    static let urgentInk = Color(hex: 0xB91C1C)
    static let urgentSoft = Color(hex: 0xFEE2E2)
    static let urgent = Color(hex: 0xDC2626)
    static let urgentLine = Color(hex: 0xFCA5A5)
    static let normalInk = Color(hex: 0x374151)
    static let normalSoft = Color(hex: 0xF3F4F6)
    static let systemDot = Color(hex: 0x6B7280)
    static let morningBg = Color(hex: 0xFFF8EC)
    static let morningInk = Color(hex: 0x1F1A14)
    static let nightBg = Color(hex: 0x131C2E)
    static let nightCard = Color(hex: 0x1C2840)
    static let nightButton = Color(hex: 0x2A3B57)
    static let nightText = Color(hex: 0xEEF2F7)
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

    /// The small dot in the calendar and the strong colour of a selected choice.
    static func strong(_ i: Importance) -> Color {
        switch i {
        case .normal: return accent
        case .important: return Color(hex: 0xD97706)
        case .urgent: return urgent
        }
    }
}

struct ImportanceBadge: View {
    let importance: Importance
    var body: some View {
        Text(importance.label)
            .font(.dyn(12, weight: .semibold))
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
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(color)
                .shadow(color: color == T.card ? Color(hex: 0x111827).opacity(0.06) : .clear, radius: 10, x: 0, y: 4)
        }
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
            Text(title).font(.dyn(17, weight: .bold)).foregroundStyle(color)
            Spacer()
            if let trailing {
                Text(trailing).font(.dyn(13)).foregroundStyle(T.muted)
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
                        .font(.dyn(24))
                        .foregroundStyle(e.isDone ? T.accent : T.outline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(e.isDone ? "منجز، اضغط للتراجع" : "علّم كمنجز")
            } else {
                Image(systemName: "calendar")
                    .font(.dyn(18))
                    .foregroundStyle(T.systemDot)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.dyn(15))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? T.muted : T.ink)
                    .lineLimit(2)
                Text(whenLine)
                    .font(.dyn(12))
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
                Menu {
                Button("نعم، احذف", systemImage: "trash", role: .destructive) { EntryActions.delete(e) }
            } label: {
                Label("حذف", systemImage: "trash")
            }
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
                    .font(.dyn(16, weight: .bold))
                }
            }
    }
}

extension View {
    func keyboardDone() -> some View { modifier(KeyboardDone()) }
}

/// Shown when the real alarm permission is off: «ضروري» would then be a silent notification.
struct AlarmOffBanner: View {
    var body: some View {
        Button {
            Task {
                if AlarmService.canAsk { await AlarmService.requestAuthorization() }
                else if let url = URL(string: UIApplication.openSettingsURLString) { _ = await UIApplication.shared.open(url) }
                Scheduler.shared.rebuildSoon()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "alarm.waves.left.and.right").font(.dyn(18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("المنبّه الحقيقي مقفل").font(.dyn(16, weight: .bold))
                    Text("بدونه ما يرن الضروري والجوال صامت. اضغط هنا وفعّله.").font(.dyn(14))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.urgentInk)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.urgentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
