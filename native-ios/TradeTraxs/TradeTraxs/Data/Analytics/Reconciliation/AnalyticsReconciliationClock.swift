import Foundation

nonisolated protocol AnalyticsReconciliationClock: Sendable {
    func sleep(for duration: Duration) async throws
}

nonisolated struct ImmediateAnalyticsReconciliationClock: AnalyticsReconciliationClock {
    func sleep(for duration: Duration) async throws {
        guard duration > .zero else { return }
        try await Task.sleep(for: duration)
    }
}

nonisolated final class TestAnalyticsReconciliationClock: AnalyticsReconciliationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<Void, Error>] = []

    func sleep(for duration: Duration) async throws {
        guard duration > .zero else { return }
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending.append(continuation)
            lock.unlock()
        }
    }

    func advance() {
        lock.lock()
        let batch = pending
        pending = []
        lock.unlock()
        for continuation in batch {
            continuation.resume()
        }
    }
}
