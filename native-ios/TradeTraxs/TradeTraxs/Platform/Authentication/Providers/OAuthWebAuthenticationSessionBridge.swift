@preconcurrency import AuthenticationServices
import Foundation
import OSLog
import Synchronization

/// Single-resume bridge for ``ASWebAuthenticationSession`` completion races.
///
/// iOS may invoke the session completion handler more than once (success URL, then
/// cancellation on dismiss). The continuation must resume exactly once.
nonisolated final class OAuthWebAuthenticationSessionBridge: @unchecked Sendable {
    enum FinishSource: String, Sendable {
        case callbackSuccess
        case userCancellation
        case sessionError
        case missingCallbackURL
        case invalidCallbackURL
        case startFailed
        case taskCancellation
    }

    private struct State {
        var continuation: CheckedContinuation<URL, Error>?
        var finished = false
    }

    private let state = Mutex(State())
    private nonisolated(unsafe) var activeSession: ASWebAuthenticationSession?

    func bind(continuation: CheckedContinuation<URL, Error>) {
        state.withLock { state in
            state.continuation = continuation
            state.finished = false
        }
    }

    func attach(session: ASWebAuthenticationSession) {
        activeSession = session
    }

    func cancelSession() {
        DispatchQueue.main.async { [weak self] in
            self?.activeSession?.cancel()
            self?.activeSession = nil
        }
    }

    /// Returns `true` when the continuation was resumed; `false` when already completed.
    @discardableResult
    func finishOnce(with result: Result<URL, Error>, source: FinishSource) -> Bool {
        let continuation = state.withLock { state -> CheckedContinuation<URL, Error>? in
            guard !state.finished, let continuation = state.continuation else {
                return nil
            }
            state.finished = true
            state.continuation = nil
            return continuation
        }

        guard let continuation else {
            AppLog.authentication.info(
                "OAuth: \(source.rawValue, privacy: .public) ignored because already completed"
            )
            return false
        }

        switch result {
        case .success(let url):
            AppLog.authentication.info("OAuth: callback won")
            continuation.resume(returning: url)
            DispatchQueue.main.async { [weak self] in
                self?.activeSession?.cancel()
                self?.activeSession = nil
            }
        case .failure(let error):
            if source == .userCancellation || source == .taskCancellation {
                AppLog.authentication.info("OAuth: cancelled by user")
            } else if source == .startFailed {
                AppLog.authentication.error("OAuth: ASWebAuthenticationSession failed to start")
            }
            continuation.resume(throwing: error)
            if source == .taskCancellation {
                cancelSession()
            }
        }

        return true
    }
}
