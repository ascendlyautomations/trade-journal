import AVFoundation
import Combine
import Foundation

@MainActor
final class VoiceMessageRecorder: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case denied
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var completedRecording: (url: URL, duration: TimeInterval)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    func start() async -> Bool {
        guard phase == .idle else { return false }
        let granted = await requestPermission()
        guard granted else {
            phase = .denied
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            self.recorder = recorder
            outputURL = url
            elapsed = 0
            phase = .recording
            startTimer()
            return true
        } catch {
            cleanupRecording()
            return false
        }
    }

    func cancel() {
        cleanupRecording()
        phase = .idle
        elapsed = 0
    }

    func finish() -> (url: URL, duration: TimeInterval)? {
        guard phase == .recording, let url = outputURL else { return nil }
        stopTimer()
        recorder?.stop()
        recorder = nil
        let duration = elapsed
        outputURL = nil
        phase = .idle
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, duration)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.elapsed += 0.1
                if self.elapsed >= VoiceMessageSupport.maxRecordingDuration {
                    if let result = self.finish() {
                        self.completedRecording = result
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cleanupRecording() {
        stopTimer()
        recorder?.stop()
        recorder = nil
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
