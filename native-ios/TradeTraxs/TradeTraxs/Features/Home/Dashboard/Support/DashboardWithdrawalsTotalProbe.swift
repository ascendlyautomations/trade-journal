#if DEBUG
import Foundation
import OSLog

/// Compares Withdrawals home total vs Dashboard Payouts card binding.
@MainActor
enum DashboardWithdrawalsTotalProbe {
    private static let logger = Logger(
        subsystem: AppLog.subsystem,
        category: "DashboardWithdrawalsTotal"
    )

    static func log(
        withdrawalsPageTotal: Decimal,
        dashboardComputedTotal: Decimal?,
        dashboardUIBoundTotal: Decimal?,
        ledgerRows: Int,
        completedPropCycles: Int,
        achievementExtraRows: Int,
        hydrationComplete: Bool,
        accountFilter: String,
        dateScope: String
    ) {
        let computed = dashboardComputedTotal.map { "\($0)" } ?? "nil"
        let bound = dashboardUIBoundTotal.map { "\($0)" } ?? "nil"
        logger.info(
            """
            [DashboardWithdrawalsTotal] withdrawalsPage=\(withdrawalsPageTotal, privacy: .public) \
            dashboardComputed=\(computed, privacy: .public) uiBound=\(bound, privacy: .public) \
            ledgerRows=\(ledgerRows) propCycles=\(completedPropCycles) achievementExtras=\(achievementExtraRows) \
            hydrationComplete=\(hydrationComplete) accountFilter=\(accountFilter, privacy: .public) \
            dateScope=\(dateScope, privacy: .public)
            """
        )
    }
}
#else
import Foundation

@MainActor
enum DashboardWithdrawalsTotalProbe {
    static func log(
        withdrawalsPageTotal: Decimal,
        dashboardComputedTotal: Decimal?,
        dashboardUIBoundTotal: Decimal?,
        ledgerRows: Int,
        completedPropCycles: Int,
        achievementExtraRows: Int,
        hydrationComplete: Bool,
        accountFilter: String,
        dateScope: String
    ) {}
}
#endif