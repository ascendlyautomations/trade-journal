import Foundation
import Synchronization

/// Schedules proactive refresh before access-token expiry.
nonisolated final class TokenRefreshCoordinator: @unchecked Sendable {
    private struct CoordinatorState {
        var refreshTask: Task<Void, Never>?
        var onRefreshed: ((AuthenticationSession) -> Void)?
        var onFailed: ((AuthenticationError) -> Void)?
        var sessionGenerationProvider: () -> UInt64 = { 0 }
    }

    private let sessionManager: SessionManager
    private let emailProvider: any AuthenticationProviding
    private let expiration: SessionExpiration
    private let state = Mutex(CoordinatorState())

    init(
        sessionManager: SessionManager,
        emailProvider: any AuthenticationProviding,
        expiration: SessionExpiration
    ) {
        self.sessionManager = sessionManager
        self.emailProvider = emailProvider
        self.expiration = expiration
    }

    func setHandlers(
        onRefreshed: @escaping (AuthenticationSession) -> Void,
        onFailed: @escaping (AuthenticationError) -> Void
    ) {
        state.withLock { coordinator in
            coordinator.onRefreshed = onRefreshed
            coordinator.onFailed = onFailed
        }
    }

    func setSessionGenerationProvider(_ provider: @escaping () -> UInt64) {
        state.withLock { coordinator in
            coordinator.sessionGenerationProvider = provider
        }
    }

    func schedule(for session: AuthenticationSession) {
        cancel()
        guard let delay = expiration.timeUntilRefresh(for: session) else { return }
        let task = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
        }
        state.withLock { coordinator in
            coordinator.refreshTask = task
        }
    }

    func refreshNow() async {
        guard let session = sessionManager.currentSession else { return }
        let generation = state.withLock { $0.sessionGenerationProvider() }
        let fingerprint = SessionFingerprint.make(session)
        do {
            let refreshed = try await AuthRefreshSingleFlight.shared.refresh(
                fingerprint: fingerprint,
                generation: generation
            ) {
                try await self.emailProvider.refresh(session: session)
            }
            try sessionManager.install(refreshed)
            let handler = state.withLock { coordinator -> ((AuthenticationSession) -> Void)? in
                let handler = coordinator.onRefreshed
                return handler
            }
            handler?(refreshed)
            schedule(for: refreshed)
        } catch let error as AuthenticationError {
            let handler = state.withLock { $0.onFailed }
            handler?(error)
        } catch is CancellationError {
            let handler = state.withLock { $0.onFailed }
            handler?(.cancelled)
        } catch AuthBootstrapError.staleSessionResult {
            // Superseded by a newer login — ignore.
        } catch {
            let handler = state.withLock { $0.onFailed }
            handler?(.refreshFailed)
        }
    }

    func cancel() {
        state.withLock { coordinator in
            coordinator.refreshTask?.cancel()
            coordinator.refreshTask = nil
        }
    }
}
