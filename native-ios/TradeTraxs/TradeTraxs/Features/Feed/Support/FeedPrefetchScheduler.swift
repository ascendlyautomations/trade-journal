import Foundation

/// Prefetch waits for background network capacity — no speculative storm while slots are full.
enum FeedPrefetchScheduler {
    static func waitForBackgroundCapacity() async {
        let limit = NetworkConcurrencyCoordinator.maxBackgroundConcurrent
        while !Task.isCancelled {
            let snapshot = await NetworkConcurrencyCoordinator.shared.snapshot()
            if snapshot.background < limit {
                return
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }
}
