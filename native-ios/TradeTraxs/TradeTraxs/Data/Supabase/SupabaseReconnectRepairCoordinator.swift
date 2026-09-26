import Foundation

/// Coalesces post-reconnect / foreground / network-regain repair into one bounded cycle.
/// Realtime rejoin must complete before repair work runs (`markRealtimeRejoinCompleted`).
actor SupabaseReconnectRepairCoordinator {
    static let shared = SupabaseReconnectRepairCoordinator()

    enum Trigger: String, Sendable {
        case foreground
        case networkRegain
        case realtimeReconnect
    }

    private var pendingTriggers: Set<Trigger> = []
    private var repairTask: Task<Void, Never>?
    private var lastRejoinSnapshot: SupabasePressureRealtimeSnapshot?
    private var domainInFlight: Set<String> = []

    private init() {}

    func markRealtimeRejoinCompleted(_ snapshot: SupabasePressureRealtimeSnapshot) {
        lastRejoinSnapshot = snapshot
        SupabasePressureLog.rejoinCompleted(snapshot)
    }

    func enqueueRepair(_ trigger: Trigger) {
        if repairTask != nil {
            SupabasePressureLog.repairCoalesced(domain: "cycle", detail: trigger.rawValue)
        }
        pendingTriggers.insert(trigger)
        scheduleIfNeeded()
    }

    func snapshotForTesting() -> (pending: Set<Trigger>, inFlight: Set<String>) {
        (pendingTriggers, domainInFlight)
    }

    func awaitIdleForTesting(timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if repairTask == nil, pendingTriggers.isEmpty, domainInFlight.isEmpty {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func scheduleIfNeeded() {
        guard repairTask == nil else { return }
        repairTask = Task { await self.runRepairCycle() }
    }

    private func runRepairCycle() async {
        defer { repairTask = nil }
        repeat {
            guard !pendingTriggers.isEmpty else { return }
            let batch = pendingTriggers
            pendingTriggers.removeAll()

            await RealtimePressureSnapshotProvider.awaitReconnectCompletionIfInFlight()

            let before: SupabasePressureRealtimeSnapshot
            if let rejoinSnapshot = lastRejoinSnapshot {
                before = rejoinSnapshot
            } else {
                before = await RealtimePressureSnapshotProvider.snapshot()
            }
            let communicationReasons = communicationReasons(from: batch)
            guard !communicationReasons.isEmpty else {
                SupabasePressureLog.repairCoalesced(domain: "cycle", detail: "no_communication_triggers")
                let after = await RealtimePressureSnapshotProvider.snapshot()
                SupabasePressureLog.repairCompleted(before: before, after: after)
                continue
            }

            SupabasePressureLog.repairStarted(domains: "communication", snapshot: before)

            if domainInFlight.contains("communication") {
                SupabasePressureLog.repairCoalesced(domain: "communication", detail: "already_in_flight")
            } else {
                domainInFlight.insert("communication")
                await SocialRealtimeReconciliationCoordinator.shared.performCoalescedRepair(
                    reasons: communicationReasons
                )
                domainInFlight.remove("communication")
            }

            let after = await RealtimePressureSnapshotProvider.snapshot()
            SupabasePressureLog.repairCompleted(before: before, after: after)
        } while !pendingTriggers.isEmpty
    }

    private func communicationReasons(from triggers: Set<Trigger>) -> Set<SocialRealtimeRepairReason> {
        var reasons: Set<SocialRealtimeRepairReason> = []
        if triggers.contains(.networkRegain) { reasons.insert(.networkRegain) }
        if triggers.contains(.realtimeReconnect) { reasons.insert(.realtimeReconnect) }
        return reasons
    }
}

@MainActor
enum RealtimePressureSnapshotProvider {
    private static weak var hub: RealtimeHub?

    static func bind(realtimeHub: RealtimeHub) {
        hub = realtimeHub
    }

    static func snapshot() -> SupabasePressureRealtimeSnapshot {
        hub?.realtimePressureSnapshot()
            ?? SupabasePressureRealtimeSnapshot(
                sessionGeneration: 0,
                activeRoutes: 0,
                joinedTopics: 0,
                logicalConsumers: 0
            )
    }

    static func awaitReconnectCompletionIfInFlight() async {
        await hub?.awaitReconnectCompletionIfInFlight()
    }
}
