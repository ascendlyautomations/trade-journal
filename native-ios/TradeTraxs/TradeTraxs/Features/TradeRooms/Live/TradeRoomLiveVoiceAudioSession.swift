import AVFoundation
import Foundation
import LiveKit

enum TradeRoomLiveVoiceSessionRequirement {
    static func forLiveVoice(requiresRecording: Bool) -> SessionRequirement {
        requiresRecording ? .playbackAndRecording : .playbackOnly
    }
}

/// LiveKit-backed audio session for Trade Room General Voice (background + Bluetooth).
@MainActor
final class TradeRoomLiveVoiceAudioSession {
    static let shared = TradeRoomLiveVoiceAudioSession()

    struct Diagnostics: Equatable, Sendable {
        var isActive: Bool
        var requiresRecording: Bool
        var canPlaybackAudio: Bool
        var lastInterruptionReason: String?
        var lastRouteSummary: String?
    }

    private(set) var diagnostics = Diagnostics(
        isActive: false,
        requiresRecording: false,
        canPlaybackAudio: false,
        lastInterruptionReason: nil,
        lastRouteSummary: nil
    )

    var isActive: Bool { sessionHandle != nil }

    private var sessionHandle: SessionRequirementHandle?
    private var requiresRecording = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    private init() {}

    func activate(requiresRecording: Bool) throws {
        if isActive, self.requiresRecording == requiresRecording {
            refreshDiagnostics()
            return
        }
        if isActive {
            deactivate()
        }

        AudioManager.prepare()
        AudioManager.shared.isSpeakerOutputPreferred = true
        AudioManager.shared.sessionConfiguration = .playAndRecordSpeaker

        self.requiresRecording = requiresRecording
        sessionHandle = try AudioManager.shared.acquireSessionRequirement(
            TradeRoomLiveVoiceSessionRequirement.forLiveVoice(requiresRecording: requiresRecording)
        )
        registerObservers()
        refreshDiagnostics()
    }

    func updateRequiresRecording(_ requiresRecording: Bool) throws {
        try activate(requiresRecording: requiresRecording)
    }

    func deactivate() {
        unregisterObservers()
        try? sessionHandle?.release()
        sessionHandle = nil
        requiresRecording = false
        diagnostics = Diagnostics(
            isActive: false,
            requiresRecording: false,
            canPlaybackAudio: false,
            lastInterruptionReason: diagnostics.lastInterruptionReason,
            lastRouteSummary: diagnostics.lastRouteSummary
        )
    }

    func refreshDiagnostics() {
        let session = AVAudioSession.sharedInstance()
        diagnostics = Diagnostics(
            isActive: isActive,
            requiresRecording: requiresRecording,
            canPlaybackAudio: session.isOtherAudioPlaying == false || isActive,
            lastInterruptionReason: diagnostics.lastInterruptionReason,
            lastRouteSummary: routeSummary(session)
        )
    }

    private func registerObservers() {
        unregisterObservers()
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleInterruption(note)
            }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDiagnostics()
            }
        }
    }

    private func unregisterObservers() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            diagnostics.lastInterruptionReason = "began"
        case .ended:
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            diagnostics.lastInterruptionReason = options.contains(.shouldResume)
                ? "ended_should_resume"
                : "ended"
            if options.contains(.shouldResume), isActive {
                try? activate(requiresRecording: requiresRecording)
            }
        @unknown default:
            diagnostics.lastInterruptionReason = "unknown"
        }
        refreshDiagnostics()
    }

    private func routeSummary(_ session: AVAudioSession) -> String {
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        return outputs.isEmpty ? "none" : outputs
    }
}
