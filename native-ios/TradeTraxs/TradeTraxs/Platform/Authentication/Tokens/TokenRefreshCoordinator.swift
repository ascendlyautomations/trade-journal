import Foundation

/// Schedules proactive refresh before access-token expiry.
final class TokenRefreshCoordinator: @unchecked Sendable {
    private let sessionManager: SessionManager
    private let emailProvider: any AuthenticationProviding
    private let expiration: SessionExpiration
    private let lock = NSLock()
    private var refreshTask: Task<Void, Never>?
    private var onRefreshed: ((AuthenticationSession) -> Void)?
    private var onFailed: ((AuthenticationError) -> Void)?

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
        lock.lock()
        self.onRefreshed = onRefreshed
        self.onFailed = onFailed
        lock.unlock()
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
        lock.lock(); refreshTask = task; lock.unlock()
    }

    func refreshNow() async {
        guard let session = sessionManager.currentSession else { return }
        do {
            let refreshed = try await emailProvider.refresh(session: session)
            try sessionManager.install(refreshed)
            lock.lock(); let handler = onRefreshed; lock.unlock()
            handler?(refreshed)
            schedule(for: refreshed)
        } catch let error as AuthenticationError {
            lock.lock(); let handler = onFailed; lock.unlock()
            handler?(error)
        } catch {
            lock.lock(); let handler = onFailed; lock.unlock()
            handler?(.refreshFailed)
        }
    }

    func cancel() {
        lock.lock()
        refreshTask?.cancel()
        refreshTask = nil
        lock.unlock()
    }
}
