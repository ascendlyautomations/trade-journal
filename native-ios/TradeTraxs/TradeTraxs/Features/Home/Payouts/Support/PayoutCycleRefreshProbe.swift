#if DEBUG
import Foundation

/// DEBUG trace for payout → Dashboard prop-firm cycle refresh.
enum PayoutCycleRefreshProbe {
    static func logAfterPayoutRecorded(
        accountID: TradingAccountID,
        cycleID: String,
        balanceAfterPayout: Decimal,
        dashboardCacheInvalidated: Bool
    ) {
        print(
            """
            [PayoutCycleRefresh] payout recorded \
            accountId=\(accountID.rawValue) \
            newCycleId=\(cycleID) \
            balanceAfterPayout=\(balanceAfterPayout) \
            dashboardCacheInvalidated=\(dashboardCacheInvalidated)
            """
        )
    }

    static func logDashboardReload(
        accountID: TradingAccountID,
        cycles: [AccountPayoutCycle],
        snapshot: PropFirmStatusSnapshot?
    ) {
        let active = PropFirmPayoutCycleSupport.selectActivePayoutCycle(cycles)
        let cycleStart = active.map { ISO8601.string(from: $0.startedAt) } ?? "nil"
        print(
            """
            [PayoutCycleRefresh] dashboard reloaded \
            accountId=\(accountID.rawValue) \
            newCycleId=\(active?.id ?? "nil") \
            balanceAfterPayout=\(active?.cycleStartBalance.description ?? "nil") \
            cycleStart=\(cycleStart) \
            cyclePnL=\(snapshot?.cyclePnL.description ?? "nil") \
            qualifyingDays=\(snapshot?.winningDays.description ?? "nil") \
            payoutReady=\(snapshot?.payoutReady.description ?? "nil") \
            dashboard cache invalidated/reloaded=true
            """
        )
    }
}
#endif
