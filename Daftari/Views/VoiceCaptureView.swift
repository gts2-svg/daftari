import SwiftUI
import SwiftData

/// «إضافة بالصوت»: full green screen, speak and watch it turn into text.
struct VoiceCaptureView: View {
    let mode: VoiceMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @StateObject private var speech = SpeechService()
    @State private var levels: [CGFloat] = Array(repeating: 0.08, count: 28)
    @State private var started = false

    private var trimmed: String { speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Button {
                    speech.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityLabel("إغلاق")
                Spacer()
                Text(statusText).font(.system(size: 15, weight: .semibold)).opacity(0.9)
            }

            Spacer(minLength: 0)

            ScrollView {
                Text(trimmed.isEmpty ? placeholder : speech.transcript)
                    .font(.system(size: 24, weight: .medium))
                    .lineSpacing(8)
                    .opacity(trimmed.isEmpty ? 0.6 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            if let err = speech.errorText {
                Text(err)
                    .font(.system(size: 14))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("يتحول لنص داخل جوالك")
                .font(.system(size: 13)).opacity(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 4) {
                ForEach(levels.indices, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: 5, height: 6 + levels[i] * 50)
                }
            }
            .frame(height: 58)
            .accessibilityHidden(true)

            Button {
                if speech.isRecording { speech.stop() } else { Task { await speech.start() } }
            } label: {
                ZStack {
                    Circle().fill(Color.white).frame(width: 92, height: 92)
                    if speech.isRecording {
                        RoundedRectangle(cornerRadius: 8).fill(T.urgentInk).frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 34)).foregroundStyle(T.accent)
                    }
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 6).frame(width: 104, height: 104))
            }
            .accessibilityLabel(speech.isRecording ? "إيقاف التسجيل" : "ابدأ التسجيل")

            HStack(spacing: 10) {
                Button {
                    saveAsNote()
                } label: {
                    Text(mode == .journal ? "احفظها في يومي" : "احفظها فكرة")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                }
                if mode == .idea {
                    Button {
                        convertToTask()
                    } label: {
                        Text("حوّلها لمهمة")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(T.accentDeep)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.5 : 1)

            Text("تفتحها بسرعة من الزر الجانبي أو «يا Siri فكرة جديدة في دفتري»")
                .font(.system(size: 12)).opacity(0.8)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .foregroundStyle(.white)
        .background(T.accent.ignoresSafeArea())
        .task {
            guard !started else { return }
            started = true
            #if DEBUG
            if Demo.isOn {
                speech.transcript = Demo.transcript
                levels = (0..<28).map { i in CGFloat(0.15 + 0.7 * abs(sin(Double(i) * 0.7))) }
                return
            }
            #endif
            await speech.start()
        }
        .onChange(of: speech.level) { _, value in
            levels.removeFirst()
            levels.append(CGFloat(min(1, max(0.05, value))))
        }
        .onDisappear { speech.cancel() }
    }

    private var statusText: String {
        if speech.isRecording { return "يسجّل…" }
        return trimmed.isEmpty ? "اضغط المايك وتكلم" : "انتهى التسجيل"
    }

    private var placeholder: String {
        mode == .journal ? "وش صار اليوم؟ تكلم وأنا أكتب…" : "تكلم، وأنا أكتب…"
    }

    private func saveAsNote() {
        let t = trimmed
        speech.cancel()
        guard !t.isEmpty else { return }
        ctx.insert(Entry(title: t, kind: mode == .journal ? .journal : .idea))
        try? ctx.save()
        dismiss()
    }

    private func convertToTask() {
        let t = trimmed
        speech.cancel()
        dismiss()
        AppState.shared.openAfterDismiss(.add(prefill: t, date: nil, kind: nil))
    }
}
