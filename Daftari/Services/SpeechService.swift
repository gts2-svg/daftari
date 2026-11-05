import Foundation
import Speech
import AVFoundation

/// Speech-to-text in Arabic, on the phone when the device supports it.
@MainActor
final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var level: Float = 0
    @Published var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        errorText = nil
        guard await requestSpeechPermissions() else {
            errorText = "اسمح لدفتري بالمايك والتعرّف على الكلام من الإعدادات."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorText = "التعرّف على الكلام غير متاح الآن."
            return
        }
        cancel()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "تعذر تشغيل المايك."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let onLevel: @Sendable (Float) -> Void = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeTapBlock(request: req, onLevel: onLevel))

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorText = "تعذر تشغيل المايك."
            return
        }
        isRecording = true

        let onResult: @Sendable (String?, Bool) -> Void = { [weak self] text, finished in
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty { self.transcript = text }
                if finished { self.stopAudio() }
            }
        }
        task = recognizer.recognitionTask(with: req, resultHandler: makeResultHandler(onResult))
    }

    /// Stops listening but keeps the text.
    func stop() {
        stopAudio()
        request?.endAudio()
    }

    /// Stops and discards the running recognition.
    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func stopAudio() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// Built outside the main actor: these closures run on audio / recognition threads.

private func makeTapBlock(request: SFSpeechAudioBufferRecognitionRequest,
                          onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
    return { buffer, _ in
        request.append(buffer)
        onLevel(audioLevel(buffer))
    }
}

private func makeResultHandler(_ onResult: @escaping @Sendable (String?, Bool) -> Void)
    -> (SFSpeechRecognitionResult?, Error?) -> Void {
    return { result, error in
        onResult(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
    }
}

private func audioLevel(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let data = buffer.floatChannelData?[0] else { return 0 }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return 0 }
    var sum: Float = 0
    for i in 0..<n { sum += data[i] * data[i] }
    let rms = sqrt(sum / Float(n))
    let db = 20 * log10(max(rms, 0.000_01))
    return max(0, min(1, (db + 50) / 50))
}

func requestSpeechPermissions() async -> Bool {
    let speechOK: Bool = await withCheckedContinuation { cont in
        SFSpeechRecognizer.requestAuthorization { status in
            cont.resume(returning: status == .authorized)
        }
    }
    let micOK = await AVAudioApplication.requestRecordPermission()
    return speechOK && micOK
}
