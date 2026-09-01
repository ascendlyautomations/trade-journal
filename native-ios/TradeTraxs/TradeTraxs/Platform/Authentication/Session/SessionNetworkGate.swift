import Foundation

/// Gates authenticated network only while a token refresh is actively in flight.
///
/// RPC/bootstrap must not wait for Session enrichment — only for refresh completion.
actor SessionNetworkGate {
    static let shared = SessionNetworkGate()

    private var refreshInFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markUnauthenticated() {
        refreshInFlight = false
        resumeAll()
    }

    func beginRefresh() {
        refreshInFlight = true
    }

    func markReady() {
        refreshInFlight = false
        resumeAll()
    }

    /// Blocks only during an active refresh — never for Session/Dashboard bootstrap pending.
    func awaitReady() async {
        guard refreshInFlight else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    var isRefreshInFlight: Bool {
        refreshInFlight
    }

    private func resumeAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
