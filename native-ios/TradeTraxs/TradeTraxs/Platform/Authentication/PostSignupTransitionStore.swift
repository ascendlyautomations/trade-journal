import Foundation
import Observation

/// Full-screen post-registration bootstrap — shown after auth succeeds, before onboarding/shell.
@Observable
@MainActor
final class PostSignupTransitionStore {
    enum Phase: Equatable, Sendable {
        case inactive
        case creatingAccount
        case bootstrapFailed(message: String)
    }

    private(set) var phase: Phase = .inactive
    private(set) var bootstrapAttemptID: UInt64 = 0

    static let defaultBootstrapFailureMessage =
        "Unable to finish setting up your account. Please try again."

    var isObscuringAuthRoot: Bool {
        switch phase {
        case .creatingAccount, .bootstrapFailed:
            return true
        case .inactive:
            return false
        }
    }

    func beginCreatingAccount() {
        phase = .creatingAccount
    }

    /// Drops the cover when onboarding or the main shell is already the routing destination.
    func releaseCoverIfAuthenticatedDestinationReady(gatePhase: ProfileOnboardingGateStore.Phase) {
        guard phase == .creatingAccount else { return }
        guard gatePhase.presentsAuthenticatedDestination else { return }
        finishBootstrapTransition()
    }

    func finishBootstrapTransition() {
        phase = .inactive
        bootstrapAttemptID = 0
    }

    func failBootstrap(message: String) {
        phase = .bootstrapFailed(message: message)
    }

    func retryBootstrap() {
        bootstrapAttemptID &+= 1
        phase = .creatingAccount
    }

    func reset() {
        phase = .inactive
        bootstrapAttemptID = 0
    }
}
