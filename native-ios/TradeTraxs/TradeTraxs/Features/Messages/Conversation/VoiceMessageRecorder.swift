import AVFoundation
import Combine
import Foundation

@MainActor
final class VoiceMessageRecorder: ObservableObject {
    nonisolated enum Phase: Equatable {
        case idle
        case recording
    }

    struct StartResult: Equatable, Sendable {
        var started: Bool
        var showSettings: Bool
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var completedRecording: (url: URL, duration: TimeInterval)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var outputURL: URL?

    /// Recording blocks another start. A denial stays idle so the next tap
    /// re-reads the system permission after the user changes Settings.
    nonisolated static func canStart(from phase: Phase) -> Bool {
        phase != .recording
    }

    nonisolated static func needsSettingsPrompt(permission: AVAudioApplication.recordPermission) -> Bool {
        permission == .denied
    }

    func start() async -> StartResult {
        guard Self.canStart(from: phase) else {
            return StartResult(started: false, showSettings: false)
        }
        let showSettings = Self.needsSettingsPrompt(
            permission: AVAudioApplication.shared.recordPermission
        )
        let granted = await requestPermission()
        guard granted else {
            phase = .idle
            return StartResult(started: false, showSettings: showSettings)
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
            guard recorder.record() else {
                cleanupRecording()
                phase = .idle
                return StartResult(started: false, showSettings: false)
            }
            self.recorder = recorder
            outputURL = url
            elapsed = 0
            phase = .recording
            startTimer()
            return StartResult(started: true, showSettings: false)
        } catch {
            cleanupRecording()
            phase = .idle
            return StartResult(started: false, showSettings: false)
        }
    }

    func cancel() {
        cleanupRecording()
        phase = .idle
        elapsed = 0
    }

    /// The app has no audio background mode, so a suspended recording cannot
    /// keep the microphone. Leave the composer instead of a frozen recording bar.
    func handleEnteredBackground() {
        guard phase == .recording else { return }
        cancel()
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
            Task { @MainActor [weak self] in
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
