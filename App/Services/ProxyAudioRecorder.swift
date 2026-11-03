import Foundation
import AVFoundation
import SoNoCore

@MainActor
final class ProxyAudioRecorder: ObservableObject {
    @Published private(set) var recording = false
    private var recorder: AVAudioRecorder?
    private var url: URL?
    func start() async throws {
        discard()
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard granted else { throw LedgerError.unavailable("Cần cho phép Micro trong Cài đặt iPhone.") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement); try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        self.url = url
        let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue])
        self.recorder = recorder
        guard recorder.record(forDuration: 60) else { discard(); throw LedgerError.unavailable("Không thu được âm thanh.") }
        recording = true
    }
    func finish() throws -> Data {
        recorder?.stop(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url else { throw LedgerError.invalid("Chưa có bản ghi âm.") }
        defer { discard() }
        return try Data(contentsOf: url)
    }
    func discard() {
        recorder?.stop(); recorder = nil; recording = false
        if let url { try? FileManager.default.removeItem(at: url) }; url = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
