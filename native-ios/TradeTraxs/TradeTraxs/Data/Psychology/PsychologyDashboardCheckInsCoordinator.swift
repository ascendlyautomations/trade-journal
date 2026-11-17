import Foundation

/// Single-flight dashboard psychology check-ins (90-day window + optional RPC).
@MainActor
enum PsychologyDashboardCheckInsCoordinator {
    private static var inFlight: [ProfileID: Task<[TraderDailyCheckIn], Error>] = [:]

    static func reset() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    static func mergedSessionCheckIns(
        profileID: ProfileID,
        window: (start: String, end: String)
    ) -> [TraderDailyCheckIn] {
        var merged = SessionDailyCheckInsStore.shared.checkIns
        let history = CheckInHistorySessionStore.shared.checkIns
        merged = TraderDailyCheckInMerge.preferNewer(primary: merged, secondary: history)
        if let today = TraderDailyCheckInStore.shared.todayCheckIn,
           today.ownerProfileID == profileID
        {
            merged = TraderDailyCheckInMerge.preferNewer(primary: merged, secondary: [today])
        }
        if merged.isEmpty { return merged }
        return merged.filter { $0.checkInDate >= window.start && $0.checkInDate <= window.end }
    }

  @discardableResult
    static func load(
        profileID: ProfileID,
        dailyCheckIns: any TraderDailyCheckInRepository,
        rpc: (any RPCClient)?,
        forceNetwork: Bool
    ) async throws -> [TraderDailyCheckIn] {
        let window = PsychologyDashboardCheckInsLoader.dashboardWindow()
        if !forceNetwork,
           !SessionDailyCheckInsStore.shared.needsLoad(
               for: profileID,
               startDate: window.start,
               endDate: window.end
           )
        {
            return mergedSessionCheckIns(profileID: profileID, window: window)
        }

        if let existing = inFlight[profileID] {
            return try await existing.value
        }

        let task = Task<[TraderDailyCheckIn], Error> {
            try await PsychologyDashboardCheckInsLoader.load(
                profileID: profileID,
                dailyCheckIns: dailyCheckIns,
                rpc: rpc
            )
        }
        inFlight[profileID] = task
        defer { inFlight[profileID] = nil }
        return try await task.value
    }
}