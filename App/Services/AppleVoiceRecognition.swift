import Foundation
import Speech
import AVFoundation
import SoNoCore

@MainActor
protocol VoiceRecognitionService: AnyObject {
    func start(allowAppleServer: Bool) async throws
    func stop()
    func cancel()
}

@MainActor
final class AppleVoiceRecognition: ObservableObject, VoiceRecognitionService {
    @Published var transcript = ""
    @Published private(set) var recording = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var generation = UUID()
    var onDeviceAvailable: Bool { SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))?.supportsOnDeviceRecognition == true }
    func start(allowAppleServer: Bool) async throws {
        cancel()
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized, microphone else { throw LedgerError.unavailable("Hãy cho phép Micro và Nhận dạng giọng nói trong Cài đặt iPhone.") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")), recognizer.isAvailable else { throw LedgerError.unavailable("Apple Speech tiếng Việt hiện không khả dụng. Bạn có thể sửa văn bản hoặc nhập thủ công.") }
        guard allowAppleServer || recognizer.supportsOnDeviceRecognition else { throw LedgerError.unavailable("iPhone này chưa hỗ trợ nhận dạng tiếng Việt trên thiết bị. Bạn có thể cho phép Apple xử lý trực tuyến hoặc nhập thủ công.") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = !allowAppleServer
        self.request = request
        let generation = UUID(); self.generation = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if let error { self.error = error.localizedDescription; self.stop() }
                if result?.isFinal == true { self.stop() }
            }
        }
        let node = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { cancel(); throw LedgerError.unavailable("Micro không sẵn sàng.") }
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start(); recording = true }
        catch { cancel(); throw error }
    }
    func stop() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func cancel() { generation = UUID(); stop(); task?.cancel(); task = nil; request = nil }
}
