import Foundation

/// Debounces burst `user_analytics_state` Realtime signals before handing max revision to the coordinator.
actor AnalyticsRevisionRealtimeCoalescer {
    private var pendingMax: Int64?
    private var burstAnchor: Date?
    private var flushTask: Task<Void, Never>?
    private let policy: AnalyticsSignalCoalescingPolicy
    private let clock: any AnalyticsReconciliationClock

    init(
        policy: AnalyticsSignalCoalescingPolicy = .futureBulkImportDefault,
        clock: any AnalyticsReconciliationClock = ImmediateAnalyticsReconciliationClock()
    ) {
        self.policy = policy
        self.clock = clock
    }

    func ingest(
        revision: Int64,
        flush: @escaping @Sendable (Int64) async -> Void
    ) async {
        pendingMax = max(pendingMax ?? revision, revision)
        if burstAnchor == nil {
            burstAnchor = Date()
        }

        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            await self.runFlushLoop(flush: flush)
        }
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pendingMax = nil
        burstAnchor = nil
    }

    func pendingMaxForTesting() -> Int64? {
        pendingMax
    }

    private func runFlushLoop(flush: @escaping @Sendable (Int64) async -> Void) async {
        let anchor = burstAnchor ?? Date()
        while !Task.isCancelled {
            if Date().timeIntervalSince(anchor) >= policy.maxDebounceSeconds {
                break
            }
            if policy.debounce > .zero {
                try? await clock.sleep(for: policy.debounce)
            }
            if Date().timeIntervalSince(anchor) >= policy.debounceSeconds {
                break
            }
        }
        guard !Task.isCancelled else { return }
        guard let revision = pendingMax else { return }
        pendingMax = nil
        burstAnchor = nil
        await flush(revision)
    }
}
