import SwiftUI
import SwiftData

/// «ضروري» full screen — opens after the alarm is stopped, or from its notification.
/// Same design as the approved «تنبيه ضروري» artboard.
struct UrgentView: View {
    let uid: UUID
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Environment(\.dismiss) private var dismiss

    private let bg = Color(hex: 0x8E2F0A)

    private var entry: Entry? { entries.first { $0.uid == uid } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
        }
        .background(bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.white.opacity(0.14))
                Image(systemName: "bell")
                    .font(.system(size: 44, weight: .regular))
            }
            .frame(width: 96, height: 96)
            .padding(.top, 40)

            Text("ضروري")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

            Text(verbatim: clock(now))
                .font(.system(size: 76, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            VStack(spacing: 8) {
                Text(entry?.title ?? "موعد ضروري")
                    .font(.system(size: 25, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Text(verbatim: subtitle(now: now))
                    .font(.system(size: 17))
                    .opacity(0.9)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button {
                    if let entry { EntryActions.markDone(entry) }
                    dismiss()
                } label: {
                    Text("تم، شفته")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(bg)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await UrgentActions.snooze(entryID: uid.uuidString, title: entry?.title ?? "")
                        dismiss()
                    }
                } label: {
                    Text("ذكّرني بعد 10 دقائق")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("سكّر بدون شيء") { dismiss() }
                    .font(.system(size: 15))
                    .opacity(0.8)
                    .frame(minHeight: 44)
            }

            Text("يرن حتى لو الجوال صامت · يتكرر لين تضغط «تم»")
                .font(.system(size: 13))
                .opacity(0.8)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }

    private func clock(_ now: Date) -> String {
        let c = DF.greg.dateComponents([.hour, .minute], from: now)
        let h = (c.hour ?? 0) % 12 == 0 ? 12 : (c.hour ?? 0) % 12
        return String(format: "%d:%02d", h, c.minute ?? 0)
    }

    private func subtitle(now: Date) -> String {
        guard let entry, let anchor = entry.anchorDate else { return "" }
        let at = entry.hasTime ? "الساعة \(DF.time(anchor))" : DF.relativeDay(anchor, now: now)
        let s = anchor.timeIntervalSince(now)
        if s <= 60 && s > -15 * 60 { return "الحين · \(at)" }
        if s <= -15 * 60 { return "فات وقته · \(at)" }
        let m = Int((s / 60).rounded(.up))
        let left: String
        if m < 60 { left = m <= 10 ? "بعد \(m) دقايق" : "بعد \(m) دقيقة" }
        else if m < 24 * 60 {
            let h = m / 60, r = m % 60
            let hText = h == 1 ? "ساعة" : (h == 2 ? "ساعتين" : "\(h) ساعات")
            left = r >= 5 ? "بعد \(hText) و\(r) دقيقة" : "بعد \(hText)"
        } else { left = DF.relativeDay(anchor, now: now) }
        return "\(left) · \(at)"
    }
}
