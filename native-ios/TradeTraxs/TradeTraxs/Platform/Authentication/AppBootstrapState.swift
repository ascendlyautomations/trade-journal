import Foundation
import Observation

/// Session-scoped bootstrap progress — independent from authentication validity.
///
/// A valid Supabase session may exist while bootstrap is still loading or failed.
@Observable
@MainActor
final class AppBootstrapState {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failedRecoverable
    }

    private(set) var phase: Phase = .idle
    private(set) var lastErrorMessage: String?

    func beginLoading() {
        phase = .loading
        lastErrorMessage = nil
    }

    func markReady() {
        phase = .ready
        lastErrorMessage = nil
    }

    func markFailedRecoverable(message: String?) {
        phase = .failedRecoverable
        lastErrorMessage = message
    }

    func reset() {
        phase = .idle
        lastErrorMessage = nil
    }
}
