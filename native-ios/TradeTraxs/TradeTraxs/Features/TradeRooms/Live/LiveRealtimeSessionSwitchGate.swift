import Foundation
import Observation

@Observable
@MainActor
final class LiveRealtimeSessionSwitchGate {
    static let shared = LiveRealtimeSessionSwitchGate()

    private(set) var prompt: LiveRealtimeSessionSwitchPrompt?
    private(set) var isSwitching = false

    var showsPrompt: Bool { prompt != nil }

    private var pendingContinuation: CheckedContinuation<Bool, Never>?

    private init() {}

    /// Returns whether the requested connection may proceed (`true`) or was cancelled (`false`).
    func awaitProceed(for intent: LiveRealtimeSessionIntent) async -> Bool {
        guard LiveRealtimeSessionGuard.requiresLeaveConfirmation(for: intent) else {
            return true
        }
        if showsPrompt || isSwitching {
            return false
        }
        prompt = LiveRealtimeSessionGuard.promptModel(for: intent)
        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
        }
    }

    func confirmLeaveAndJoin() {
        let continuation = pendingContinuation
        pendingContinuation = nil
        prompt = nil
        Task { @MainActor in
            isSwitching = true
            await LiveRealtimeSessionGuard.disconnectActiveSessions()
            isSwitching = false
            continuation?.resume(returning: true)
        }
    }

    func cancelPendingSwitch() {
        let continuation = pendingContinuation
        pendingContinuation = nil
        prompt = nil
        continuation?.resume(returning: false)
    }
}