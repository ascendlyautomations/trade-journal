import Foundation

actor AnalyticsReconciliationCoordinator {
    static let shared = AnalyticsReconciliationCoordinator()

    struct Snapshot: Sendable, Equatable {
        var viewerID: ProfileID?
        var viewerGeneration: UInt64
        var lastAppliedRevision: Int64
        var maxPendingRevision: Int64?
        var reconcilingRevision: Int64?
        var dashboardIntent: DashboardReconcileIntent?
        var calendarIntents: [AnalyticsCalendarRangeIntent]
        var accountChartIntents: [AccountChartsReconcileIntent]
    }

    private var executor: any AnalyticsReconciliationExecuting
    private var revisionSeeder: any AnalyticsRevisionSeeding
    private var coalescingPolicy: AnalyticsSignalCoalescingPolicy
    private var clock: any AnalyticsReconciliationClock

    private var viewerID: ProfileID?
    private var viewerGeneration: UInt64 = 0
    private var lastAppliedRevision: Int64 = 0
    private var maxPendingRevision: Int64?
    private var reconcilingRevision: Int64?

    private var dashboardIntent: DashboardReconcileIntent?
    private var calendarIntents: [AnalyticsCalendarRangeIntent] = []
    private var accountChartIntents: [AccountChartsReconcileIntent] = []

    private var processTask: Task<Void, Never>?
    private var debounceAnchor: Date?

    init(
        executor: any AnalyticsReconciliationExecuting = NoOpAnalyticsReconciliationExecutor(),
        revisionSeeder: any AnalyticsRevisionSeeding = DefaultAnalyticsRevisionSeeder(),
        coalescingPolicy: AnalyticsSignalCoalescingPolicy = .immediate,
        clock: any AnalyticsReconciliationClock = ImmediateAnalyticsReconciliationClock()
    ) {
        self.executor = executor
        self.revisionSeeder = revisionSeeder
        self.coalescingPolicy = coalescingPolicy
        self.clock = clock
    }

    func configureForTesting(
        executor: any AnalyticsReconciliationExecuting,
        revisionSeeder: any AnalyticsRevisionSeeding,
        coalescingPolicy: AnalyticsSignalCoalescingPolicy,
        clock: any AnalyticsReconciliationClock
    ) {
        self.executor = executor
        self.revisionSeeder = revisionSeeder
        self.coalescingPolicy = coalescingPolicy
        self.clock = clock
    }

    func installProductionExecutor() {
        executor = LiveAnalyticsReconciliationExecutor()
    }

    func bindViewer(_ newViewerID: ProfileID) async {
        let oldViewer = viewerID?.rawValue
        if viewerID != newViewerID {
            viewerGeneration &+= 1
            lastAppliedRevision = 0
            maxPendingRevision = nil
            reconcilingRevision = nil
            dashboardIntent = nil
            calendarIntents = []
            accountChartIntents = []
            AnalyticsReconciliationProbe.viewerReset(
                oldViewer: oldViewer,
                newViewer: newViewerID.rawValue,
                generation: viewerGeneration
            )
        }
        viewerID = newViewerID

        let seed = await revisionSeeder.seedHighWaterRevision(viewerID: newViewerID)
        lastAppliedRevision = max(lastAppliedRevision, seed.highWaterRevision)
    }

    func reset() async {
        let oldViewer = viewerID?.rawValue
        processTask?.cancel()
        processTask = nil
        debounceAnchor = nil
        viewerGeneration &+= 1
        viewerID = nil
        lastAppliedRevision = 0
        maxPendingRevision = nil
        reconcilingRevision = nil
        dashboardIntent = nil
        calendarIntents = []
        accountChartIntents = []
        AnalyticsReconciliationProbe.viewerReset(
            oldViewer: oldViewer,
            newViewer: nil,
            generation: viewerGeneration
        )
    }

    func receive(_ source: AnalyticsReconcileSource) async {
        switch source {
        case .localMutation(let scope):
            ingestLocalMutation(scope)
            scheduleProcessing()
        case .remoteRevision(let serverRevision):
            guard let viewerID else { return }
            ingestRevision(serverRevision, sourceLabel: "remoteRevision", viewerID: viewerID)
            refreshDashboardIntent(viewerID: viewerID)
            enqueueRemoteAccountChartInvalidation(viewerID: viewerID)
            await mergeRemoteVisibleMonthCalendarIntents(
                viewerID: viewerID,
                pendingRevision: serverRevision
            )
            let generation = viewerGeneration
            await enqueueBoundedStaleCalendarCoverages(
                viewerID: viewerID,
                pendingRevision: serverRevision,
                generation: generation
            )
            scheduleProcessing()
        case .repair(let reason):
            AnalyticsReconciliationProbe.repair(
                reason: reason.rawValue,
                localRevision: lastAppliedRevision,
                serverRevision: maxPendingRevision
            )
        }
    }

    func requestRepair(reason: AnalyticsRepairReason) async {
        await receive(.repair(reason))
    }

    func snapshotForTesting() -> Snapshot {
        Snapshot(
            viewerID: viewerID,
            viewerGeneration: viewerGeneration,
            lastAppliedRevision: lastAppliedRevision,
            maxPendingRevision: maxPendingRevision,
            reconcilingRevision: reconcilingRevision,
            dashboardIntent: dashboardIntent,
            calendarIntents: calendarIntents,
            accountChartIntents: accountChartIntents
        )
    }

    func awaitIdleForTesting(timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if processTask == nil, reconcilingRevision == nil, !needsProcessing() {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Ingest

    private func ingestLocalMutation(_ scope: AnalyticalMutationScope) {
        guard ensureActiveViewer(scope.viewerID) else { return }

        if !scope.calendarRanges.isEmpty {
            calendarIntents = AnalyticsCalendarRangeCoalescing.merge(calendarIntents + scope.calendarRanges)
        }

        if scope.requestsDashboardBootstrap {
            dashboardIntent = DashboardReconcileIntent(
                viewerID: scope.viewerID,
                targetRevision: nil
            )
        }

        let chartAccounts = Set(
            scope.accountChartAccountIDs.map {
                DashboardAnalyticsAccountMetricsLookup.normalizedAccountID($0)
            }
        )
        for accountID in chartAccounts {
            mergeAccountChartIntent(
                AccountChartsReconcileIntent(
                    viewerID: scope.viewerID,
                    accountID: accountID,
                    targetRevision: nil
                )
            )
        }
    }

    private func ingestRevision(_ revision: Int64, sourceLabel: String, viewerID: ProfileID) {
        AnalyticsReconciliationProbe.signal(
            source: sourceLabel,
            viewer: viewerID.rawValue,
            revision: revision
        )
        if revision <= lastAppliedRevision {
            let reason = revision == lastAppliedRevision ? "already_applied_local" : "stale_or_duplicate"
            AnalyticsReconciliationProbe.coalesced(
                domain: "revision",
                revision: revision,
                reason: reason
            )
            return
        }
        maxPendingRevision = max(maxPendingRevision ?? revision, revision)
    }

    private func refreshDashboardIntent(viewerID: ProfileID) {
        guard let pending = maxPendingRevision else { return }
        let existing = dashboardIntent?.targetRevision
        dashboardIntent = DashboardReconcileIntent(
            viewerID: viewerID,
            targetRevision: maxOptionalRevision(existing, pending) ?? pending
        )
    }

    private func enqueueRemoteAccountChartInvalidation(viewerID: ProfileID) {
        _ = viewerID
        Task {
            await MainActor.run {
                DashboardAnalyticsAccountChartsStore.shared.invalidate()
            }
        }
    }

    private func mergeRemoteVisibleMonthCalendarIntents(
        viewerID: ProfileID,
        pendingRevision: Int64
    ) async {
        let visible = await MainActor.run {
            AnalyticsCalendarReconciliationContext.shared.visibleMonthBounds
        }
        guard let visible else { return }
        let intents = AnalyticsRemoteCalendarRepair.intents(
            viewerID: viewerID,
            pendingRevision: pendingRevision,
            visibleMonth: visible,
            staleCoverages: [],
            maxStaleRanges: 0
        )
        calendarIntents = AnalyticsCalendarRangeCoalescing.merge(calendarIntents + intents)
    }

    private func enqueueBoundedStaleCalendarCoverages(
        viewerID: ProfileID,
        pendingRevision: Int64,
        generation: UInt64
    ) async {
        guard Self.shouldQueryLocalStaleCalendarCoverages else { return }
        guard viewerGeneration == generation, self.viewerID == viewerID else { return }
        let stale = (try? await AnalyticsLocalStore.sharedStore().calendarCoveragesBelowRevision(
            viewerID: viewerID,
            revision: pendingRevision,
            limit: AnalyticsRemoteCalendarRepair.defaultMaxStaleRanges
        )) ?? []
        guard viewerGeneration == generation, self.viewerID == viewerID else { return }
        let intents = AnalyticsRemoteCalendarRepair.intents(
            viewerID: viewerID,
            pendingRevision: pendingRevision,
            visibleMonth: nil as (start: String, end: String)?,
            staleCoverages: stale,
            maxStaleRanges: AnalyticsRemoteCalendarRepair.defaultMaxStaleRanges
        )
        calendarIntents = AnalyticsCalendarRangeCoalescing.merge(calendarIntents + intents)
    }

    private func mergeAccountChartIntent(_ intent: AccountChartsReconcileIntent) {
        let normalized = intent.normalizedAccountID
        if let index = accountChartIntents.firstIndex(where: {
            $0.normalizedAccountID == normalized && $0.viewerID == intent.viewerID
        }) {
            accountChartIntents[index].targetRevision = maxOptionalRevision(
                accountChartIntents[index].targetRevision,
                intent.targetRevision
            )
        } else {
            accountChartIntents.append(
                AccountChartsReconcileIntent(
                    viewerID: intent.viewerID,
                    accountID: normalized,
                    targetRevision: intent.targetRevision
                )
            )
        }
    }

    private func maxOptionalRevision(_ lhs: Int64?, _ rhs: Int64?) -> Int64? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (nil, let r?): return r
        case (let l?, nil): return l
        case (let l?, let r?): return max(l, r)
        }
    }

    private func adoptServerRevision(_ revision: Int64) {
        guard revision > lastAppliedRevision else { return }
        lastAppliedRevision = revision
        if maxPendingRevision.map({ revision >= $0 }) == true {
            maxPendingRevision = nil
        }
    }

    private func needsProcessing() -> Bool {
        if dashboardIntent != nil { return true }
        if !calendarIntents.isEmpty { return true }
        if !accountChartIntents.isEmpty { return true }
        if let pending = maxPendingRevision, pending > lastAppliedRevision { return true }
        return false
    }

    private func ensureActiveViewer(_ expected: ProfileID) -> Bool {
        viewerID == expected
    }

    private static var shouldQueryLocalStaleCalendarCoverages: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    // MARK: - Processing

    private func scheduleProcessing() {
        guard coalescingPolicy.debounce > .zero else {
            startProcessingIfNeeded()
            return
        }
        if debounceAnchor == nil {
            debounceAnchor = Date()
        }
        processTask?.cancel()
        processTask = Task { [weak self] in
            guard let self else { return }
            await self.runDebouncedProcessing()
        }
    }

    private func runDebouncedProcessing() async {
        let anchor = debounceAnchor ?? Date()
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(anchor)
            if elapsed >= coalescingPolicy.maxDebounceSeconds {
                break
            }
            try? await clock.sleep(for: coalescingPolicy.debounce)
            if Date().timeIntervalSince(anchor) >= coalescingPolicy.debounceSeconds {
                break
            }
        }
        debounceAnchor = nil
        guard !Task.isCancelled else { return }
        await runProcessingLoop()
    }

    private func startProcessingIfNeeded() {
        guard processTask == nil else { return }
        processTask = Task { [weak self] in
            guard let self else { return }
            await self.runProcessingLoop()
        }
    }

    private func runProcessingLoop() async {
        defer { processTask = nil }

        while !Task.isCancelled {
            guard let viewer = viewerID else { return }
            guard needsProcessing() else { return }

            let generation = viewerGeneration
            let remoteHint = maxPendingRevision.flatMap { $0 > lastAppliedRevision ? $0 : nil }
            reconcilingRevision = remoteHint ?? dashboardIntent?.targetRevision ?? lastAppliedRevision + 1

            var adoptedRevision: Int64?
            var succeeded = true

            if let dash = dashboardIntent {
                let effectiveHint = maxOptionalRevision(
                    dash.targetRevision,
                    maxOptionalRevision(maxPendingRevision, remoteHint)
                )
                let revisionLabel = effectiveHint ?? remoteHint ?? -1
                AnalyticsReconciliationProbe.reconcileStart(
                    domain: "dashboardBootstrap",
                    revision: revisionLabel,
                    scope: "viewer=\(viewer.rawValue)"
                )
                do {
                    let result = try await executor.reconcileDashboard(
                        viewerID: viewer,
                        hintRevision: effectiveHint ?? remoteHint,
                        generation: generation
                    )
                    guard viewerGeneration == generation, viewerID == viewer else { return }
                    adoptedRevision = max(adoptedRevision ?? 0, result.serverRevision)
                    AnalyticsReconciliationProbe.reconcileCommit(
                        domain: "dashboardBootstrap",
                        revision: result.serverRevision,
                        elapsedMs: result.elapsedMs
                    )
                    dashboardIntent = nil
                } catch {
                    succeeded = false
                }
            }

            if succeeded {
                let calendarBatch = calendarIntents
                calendarIntents = []
                for intent in calendarBatch {
                    guard viewerGeneration == generation, viewerID == viewer else { return }
                    let scope = "\(intent.startDate)...\(intent.endDate)|account=\(intent.accountScope)|mode=\(intent.modeScope)"
                    let revisionLabel = intent.targetRevision ?? remoteHint ?? -1
                    AnalyticsReconciliationProbe.reconcileStart(
                        domain: "calendar",
                        revision: revisionLabel,
                        scope: scope
                    )
                    do {
                        let result = try await executor.reconcileCalendar(
                            intent: intent,
                            generation: generation
                        )
                        adoptedRevision = max(adoptedRevision ?? 0, result.serverRevision)
                        AnalyticsReconciliationProbe.reconcileCommit(
                            domain: "calendar",
                            revision: result.serverRevision,
                            elapsedMs: result.elapsedMs
                        )
                    } catch {
                        calendarIntents.append(intent)
                        succeeded = false
                        break
                    }
                }
            }

            if succeeded {
                let chartBatch = accountChartIntents
                accountChartIntents = []
                for intent in chartBatch {
                    guard viewerGeneration == generation, viewerID == viewer else { return }
                    do {
                        try await executor.reconcileAccountCharts(intent: intent, generation: generation)
                    } catch {
                        accountChartIntents.append(intent)
                        succeeded = false
                        break
                    }
                }
            }

            guard viewerGeneration == generation, viewerID == viewer else { return }
            reconcilingRevision = nil

            if succeeded, let adoptedRevision {
                adoptServerRevision(adoptedRevision)
                if let viewer = viewerID,
                   maxPendingRevision.map({ $0 > lastAppliedRevision }) == true {
                    refreshDashboardIntent(viewerID: viewer)
                }
                continue
            }
            if succeeded, remoteHint == nil, dashboardIntent == nil, calendarIntents.isEmpty {
                continue
            }
            break
        }
    }
}

