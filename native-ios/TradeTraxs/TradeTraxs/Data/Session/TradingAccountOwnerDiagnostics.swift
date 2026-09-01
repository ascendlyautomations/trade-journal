import Foundation
import OSLog

/// DEBUG-only owner-account field presence (never logs numbers, balances, or payloads).
nonisolated enum TradingAccountOwnerDiagnostics {
    enum ClassificationSource: String, Sendable {
        case restSelect = "rest"
        case dashboardRpc = "dashboard"
        case diskCache = "disk"
        case detailCache = "detailCache"
    }

    struct FieldPresence: Sendable {
        var hasAccountNumber: Bool
        var hasAccountSize: Bool
        var hasMode: Bool
        var hasCategory: Bool
        var hasPropFirmRules: Bool
        var hasDropdownVisibility: Bool
        var hasCustomPublicStatus: Bool
    }

    static func fieldPresence(for account: TradingAccount) -> FieldPresence {
        FieldPresence(
            hasAccountNumber: account.accountNumber?.isEmpty == false,
            hasAccountSize: account.size != nil,
            hasMode: true,
            hasCategory: true,
            hasPropFirmRules: account.propFirmRules != nil,
            hasDropdownVisibility: true,
            hasCustomPublicStatus: account.customPublicStatus?.isEmpty == false
        )
    }

    /// Heuristic for legacy session `accounts_summary` stubs persisted before the fix.
    static func looksLikeSessionSummaryStub(_ accounts: [TradingAccount]) -> Bool {
        guard !accounts.isEmpty else { return false }
        return accounts.allSatisfy { $0.size == nil && $0.accountNumber == nil }
    }

    static func logLoadSummary(
        accounts: [TradingAccount],
        source: ClassificationSource
    ) {
        #if DEBUG
        let logger = Logger(subsystem: AppLog.subsystem, category: "OwnerAccounts")
        let sample = accounts.prefix(8).map { account in
            let fields = fieldPresence(for: account)
            return "idPresent=\(!account.id.rawValue.isEmpty) number=\(fields.hasAccountNumber) size=\(fields.hasAccountSize) mode=\(fields.hasMode) category=\(fields.hasCategory) propRules=\(fields.hasPropFirmRules) dropdown=\(fields.hasDropdownVisibility) customStatus=\(fields.hasCustomPublicStatus)"
        }
        logger.debug(
            "ownerAccounts summary source=\(source.rawValue, privacy: .public) count=\(accounts.count, privacy: .public) samples=[\(sample.joined(separator: "; "), privacy: .public)]"
        )
        #else
        _ = (accounts, source)
        #endif
    }
}
