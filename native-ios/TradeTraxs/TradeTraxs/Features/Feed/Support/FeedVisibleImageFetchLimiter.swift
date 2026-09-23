import Foundation

/// Caps concurrent **network** fetches for on-screen Feed images (cache hits bypass).
actor FeedVisibleImageFetchLimiter {
    static let shared = FeedVisibleImageFetchLimiter()

    static let maxConcurrentFeedVisibleFetches = 3

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var inFlight = 0
    private var waiters: [Waiter] = []

    private init() {}

    func acquireFeedVisibleFetchSlot() async throws {
        try Task.checkCancellation()
        if inFlight < Self.maxConcurrentFeedVisibleFetches {
            inFlight += 1
            return
        }

        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.removeWaiter(id: waiterID) }
        }

        try Task.checkCancellation()
        inFlight += 1
    }

    func releaseFeedVisibleFetchSlot() {
        inFlight = max(0, inFlight - 1)
        if !waiters.isEmpty {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func removeWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index)
    }
}

nonisolated enum FeedVisibleImageFetchPolicy {
    /// Feed on-screen media at feedDisplay quality — not prefetch, not detail surfaces.
    static func requiresVisibleFetchSlot(for request: ImageRequest) -> Bool {
        !request.isSpeculativePrefetch
            && request.auditSurface == "feed"
            && request.deliveryQuality == .feedDisplay
    }
}
