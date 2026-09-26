import Foundation

nonisolated enum AnalyticsRevisionRepairReason: String, Sendable {
    case sessionBind
    case foreground
    case networkRegain
    case realtimeReconnect
}

/// Cheap revision RPC + coordinator handoff — not a second reconciliation state machine.
actor AnalyticsRevisionRepairCoordinator {
    static let shared = AnalyticsRevisionRepairCoordinator()

    /// Runtime-only suppression after a successful check (not persisted; not polling).
    static let freshCheckSuppression: Duration = .seconds(2)

    private var viewerID: ProfileID?
    private var viewerGeneration: UInt64 = 0
    private var revisionSeeder: any AnalyticsRevisionSeeding = DefaultAnalyticsRevisionSeeder()
    private var lastSuccessfulCheckAt: Date?
    private var repairTask: Task<Void, Never>?
    private var pendingReasons: Set<AnalyticsRevisionRepairReason> = []
    private var testRevisionLoader: (@Sendable () async throws -> AnalyticsRevisionV1)?

    private init() {}

    func configureForTesting(
        revisionSeeder: any AnalyticsRevisionSeeding,
        revisionLoader: (@Sendable () async throws -> AnalyticsRevisionV1)? = nil
    ) {
        self.revisionSeeder = revisionSeeder
        self.testRevisionLoader = revisionLoader
    }

    func resetTestingOverrides() {
        testRevisionLoader = nil
        revisionSeeder = DefaultAnalyticsRevisionSeeder()
    }

    func bindViewer(_ viewerID: ProfileID) {
        guard AnalyticsRevisionRepairGate.isEnabled else { return }
        if self.viewerID != viewerID {
            viewerGeneration &+= 1
        }
        self.viewerID = viewerID
        Task {
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            requestRepair(.sessionBind, bypassFreshSuppression: true)
        }
    }

    func reset() {
        viewerGeneration &+= 1
        viewerID = nil
        repairTask?.cancel()
        repairTask = nil
        pendingReasons = []
        lastSuccessfulCheckAt = nil
    }

    func requestRepair(
        _ reason: AnalyticsRevisionRepairReason,
        bypassFreshSuppression: Bool = false
    ) {
        guard AnalyticsRevisionRepairGate.isEnabled else { return }
        guard viewerID != nil else { return }

        if Self.isReconnectBurstReason(reason) {
            Task {
                await SupabaseReconnectRepairCoordinator.shared.enqueueRepair(
                    Self.reconnectTrigger(for: reason)
                )
            }
            return
        }

        if !bypassFreshSuppression, shouldSuppressFreshCheck() {
            AnalyticsReconciliationProbe.repairSuppressed(reason: reason.rawValue)
            return
        }

        pendingReasons.insert(reason)
        AnalyticsReconciliationProbe.repairRequest(reason: reason.rawValue)
        scheduleRepairIfNeeded()
    }

    /// Single coalesced analytics repair cycle — invoked by ``SupabaseReconnectRepairCoordinator`` only.
    func performCoalescedRepair(reasons: Set<AnalyticsRevisionRepairReason>) async {
        guard AnalyticsRevisionRepairGate.isEnabled else { return }
        guard let viewer = viewerID else { return }

        if repairTask != nil {
            SupabasePressureLog.repairCoalesced(domain: "analytics", detail: "repair_task_active")
            pendingReasons.formUnion(reasons)
            return
        }

        if shouldSuppressFreshCheck() {
            AnalyticsReconciliationProbe.repairSuppressed(
                reason: reasons.map(\.rawValue).sorted().joined(separator: ",")
            )
            return
        }

        let generation = viewerGeneration
        await performRepair(viewerID: viewer, generation: generation, reasons: reasons)
    }

    /// Shared reconnect coordinator — communication domains only (Phase 3).
    private static func isReconnectBurstReason(_ reason: AnalyticsRevisionRepairReason) -> Bool {
        switch reason {
        case .networkRegain, .realtimeReconnect:
            return true
        case .foreground, .sessionBind:
            return false
        }
    }

    private static func reconnectTrigger(for reason: AnalyticsRevisionRepairReason) -> SupabaseReconnectRepairCoordinator.Trigger {
        switch reason {
        case .foreground:
            return .foreground
        case .networkRegain:
            return .networkRegain
        case .realtimeReconnect:
            return .realtimeReconnect
        case .sessionBind:
            return .foreground
        }
    }

    func snapshotForTesting() -> (viewerID: ProfileID?, generation: UInt64) {
        (viewerID, viewerGeneration)
    }

    func awaitIdleForTesting(timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if repairTask == nil, pendingReasons.isEmpty {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func shouldSuppressFreshCheck() -> Bool {
        guard let lastSuccessfulCheckAt else { return false }
        return Date().timeIntervalSince(lastSuccessfulCheckAt)
            < Self.durationSeconds(Self.freshCheckSuppression)
    }

    private func scheduleRepairIfNeeded() {
        guard repairTask == nil else { return }
        repairTask = Task { [weak self] in
            guard let self else { return }
            await self.runRepairLoop()
        }
    }

    private func runRepairLoop() async {
        defer { repairTask = nil }
        repeat {
            guard !pendingReasons.isEmpty else { return }
            let reasons = pendingReasons
            pendingReasons = []
            let generation = viewerGeneration
            guard let viewer = viewerID else { return }
            await performRepair(viewerID: viewer, generation: generation, reasons: reasons)
        } while !pendingReasons.isEmpty
    }

    private func performRepair(
        viewerID: ProfileID,
        generation: UInt64,
        reasons: Set<AnalyticsRevisionRepairReason>
    ) async {
        guard self.viewerGeneration == generation, self.viewerID == viewerID else { return }
        guard let rpc = AnalyticsReconciliationRuntime.rpc else {
            AnalyticsReconciliationProbe.repairFailure(reason: "missing_rpc")
            return
        }

        let localAuthority: LocalAnalyticsRevisionAuthority
        if let seeder = revisionSeeder as? DefaultAnalyticsRevisionSeeder {
            localAuthority = await seeder.localRevisionAuthority(viewerID: viewerID)
        } else {
            let seed = await revisionSeeder.seedHighWaterRevision(viewerID: viewerID)
            localAuthority = seed.source == "unknown_zero"
                ? .unknown(source: seed.source)
                : .known(revision: seed.highWaterRevision, source: seed.source)
        }

        let coordinatorSnap = await AnalyticsReconciliationCoordinator.shared.snapshotForTesting()
        let localRevision = localAuthority.revisionIfKnown
            ?? coordinatorSnap.lastAppliedRevision

        AnalyticsReconciliationProbe.repairStart(
            reasons: reasons.map(\.rawValue).sorted().joined(separator: ","),
            localRevision: localRevision,
            localSource: localAuthority.sourceLabel
        )

        let uid = viewerID.rawValue
        let flightKey = BackendV2FlightKeys.analyticsRevision(viewerID: uid)
        let started = Date()

        do {
            let testLoader = testRevisionLoader
            let encoded = try await BackendV2SingleFlight.shared.coalesce(key: flightKey) {
                if let testLoader {
                    let response = try await testLoader()
                    return try JSONEncoder().encode(response)
                }
                let repo = AnalyticsRevisionRepository(rpc: rpc)
                let response = try await repo.loadRevision()
                return try JSONEncoder().encode(response)
            }
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            AnalyticsReconciliationProbe.repairRPC(
                bytes: encoded.count,
                elapsedMs: elapsedMs
            )

            guard self.viewerGeneration == generation, self.viewerID == viewerID else { return }

            let server = try JSONDecoder().decode(AnalyticsRevisionV1.self, from: encoded)
            let serverRevision = server.revisionInt

            let decision = compare(
                localAuthority: localAuthority,
                localRevision: localRevision,
                serverRevision: serverRevision
            )

            switch decision {
            case .current:
                lastSuccessfulCheckAt = Date()
                await AnalyticsReconciliationCoordinator.shared.noteAuthoritativeDashboardRevision(
                    serverRevision,
                    viewerID: viewerID
                )
                AnalyticsReconciliationProbe.repairCurrent(
                    localRevision: localRevision,
                    serverRevision: serverRevision
                )
            case .anomaly(let server, let local):
                lastSuccessfulCheckAt = Date()
                AnalyticsReconciliationProbe.repairAnomaly(
                    localRevision: local,
                    serverRevision: server
                )
            case .reconcile(let target):
                AnalyticsReconciliationProbe.repairStale(
                    localRevision: localRevision,
                    serverRevision: target
                )
                await AnalyticsReconciliationCoordinator.shared.receive(
                    .remoteRevision(serverRevision: target)
                )
                lastSuccessfulCheckAt = Date()
            }
        } catch {
            AnalyticsReconciliationProbe.repairFailure(reason: String(describing: error))
        }
    }

    private enum RepairDecision {
        case current
        case anomaly(server: Int64, local: Int64)
        case reconcile(serverRevision: Int64)
    }

    private func compare(
        localAuthority: LocalAnalyticsRevisionAuthority,
        localRevision: Int64,
        serverRevision: Int64
    ) -> RepairDecision {
        if case .unknown = localAuthority, serverRevision > 0 {
            return .reconcile(serverRevision: serverRevision)
        }
        if serverRevision > localRevision {
            return .reconcile(serverRevision: serverRevision)
        }
        if serverRevision < localRevision {
            return .anomaly(server: serverRevision, local: localRevision)
        }
        return .current
    }

    private static func durationSeconds(_ duration: Duration) -> TimeInterval {
        TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }
}

nonisolated enum AnalyticsRevisionRepairGate {
    static var isEnabled: Bool {
        BackendV2FeatureFlags.isEnabled(.analyticsRevisionRepair)
            && AnalyticsReconciliationGate.isEnabled
    }
}
