import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Owner-only account dropdown resolution + DEBUG presence diagnostics (never logs numbers).
@MainActor
enum OwnerAccountDropdownSupport {
    enum Boundary: String, Sendable {
        case dashboard = "dashboard.accountMenu"
        case trades = "trades.accountMenu"
        case calendar = "calendar.accountMenu"
        case addTrade = "addTrade.accountPicker"
        case csvImport = "csvImport.accountPicker"
        case achievement = "createAchievement.accountPicker"
    }

    struct Presence: Sendable {
        var accountCount: Int
        var modeAvailableCount: Int
        var numberAvailableCount: Int
        var sourceKind: String
    }

    static func menuAccounts(
        profileID: ProfileID?,
        fallback: [TradingAccount],
        preservingSelection selectedID: TradingAccountID?
    ) -> [TradingAccount] {
        let resolved = resolvedAccounts(profileID: profileID, fallback: fallback)
        return TradingAccountDropdownFilter.menuAccounts(
            from: resolved,
            preservingSelection: selectedID
        )
    }

    /// Prefer full REST owner snapshot from ``SessionAccountsStore`` over partial dashboard/bootstrap rows.
    static func resolvedAccounts(profileID: ProfileID?, fallback: [TradingAccount]) -> [TradingAccount] {
        guard let profileID else { return fallback }
        guard let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty else {
            return fallback
        }
        let kind = SessionAccountsStore.shared.snapshotKind(for: profileID)
        if kind == .rest {
            return cached
        }
        return mergePreferringOwnerFields(primary: cached, secondary: fallback)
    }

    static func snapshotKindLabel(for profileID: ProfileID?) -> String {
        guard let profileID else { return "unknown" }
        return SessionAccountsStore.shared.snapshotKind(for: profileID)?.rawValue ?? "unknown"
    }

    /// Menu panel width — 80% of screen, clamped to leave 16pt margins on each edge.
    static func filterMenuPanelWidth(screenWidth: CGFloat? = nil) -> CGFloat {
        let screen = screenWidth ?? currentScreenWidth()
        return min(screen * 0.80, screen - 32)
    }

    static let filterMenuPanelSpacingBelowAnchor: CGFloat = 6
    static let filterMenuPanelEdgeMargin: CGFloat = 16

    static let filterMenuAllAccountsRowHeight: CGFloat = 44
    static let filterMenuAccountRowHeight: CGFloat = 44
    static let filterMenuManageAccountsRowHeight: CGFloat = 48
    static let filterMenuMaxScrollHeightFraction: CGFloat = 0.55

    /// Scroll only when account rows exceed ~55% of screen height.
    static func filterMenuMaxAccountsScrollHeight(screenHeight: CGFloat) -> CGFloat {
        screenHeight * filterMenuMaxScrollHeightFraction
    }

    static func filterMenuIntrinsicHeight(accountCount: Int, dividerHeight: CGFloat = 1) -> CGFloat {
        filterMenuAllAccountsRowHeight
            + dividerHeight
            + CGFloat(accountCount) * filterMenuAccountRowHeight
            + dividerHeight
            + filterMenuManageAccountsRowHeight
    }

    /// Aligns the panel to the selector's leading edge, clamped inside screen margins.
    static func clampedPanelOriginX(
        anchorMinX: CGFloat,
        panelWidth: CGFloat,
        screenWidth: CGFloat? = nil
    ) -> CGFloat {
        let screen = screenWidth ?? currentScreenWidth()
        let margin = filterMenuPanelEdgeMargin
        let maxOrigin = screen - margin - panelWidth
        return min(max(anchorMinX, margin), maxOrigin)
    }

    static func presence(for accounts: [TradingAccount], sourceKind: String) -> Presence {
        Presence(
            accountCount: accounts.count,
            modeAvailableCount: accounts.count,
            numberAvailableCount: accounts.filter { $0.accountNumber?.isEmpty == false }.count,
            sourceKind: sourceKind
        )
    }

    static func logBoundary(_ boundary: Boundary, accounts: [TradingAccount], profileID: ProfileID?) {
        #if DEBUG
        let kind = snapshotKindLabel(for: profileID)
        let stats = presence(for: accounts, sourceKind: kind)
        Logger(subsystem: AppLog.subsystem, category: "OwnerAccountDropdown").debug(
            """
            ownerAccountDropdown boundary=\(boundary.rawValue, privacy: .public) \
            accountCount=\(stats.accountCount, privacy: .public) \
            modeAvailableCount=\(stats.modeAvailableCount, privacy: .public) \
            numberAvailableCount=\(stats.numberAvailableCount, privacy: .public) \
            sourceKind=\(stats.sourceKind, privacy: .public)
            """
        )
        #else
        _ = (boundary, accounts, profileID)
        #endif
    }

    private static func mergePreferringOwnerFields(
        primary: [TradingAccount],
        secondary: [TradingAccount]
    ) -> [TradingAccount] {
        let secondaryByID = Dictionary(uniqueKeysWithValues: secondary.map { ($0.id, $0) })
        return primary.map { enrich($0, with: secondaryByID[$0.id]) }
    }

    private static func currentScreenWidth() -> CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.width
        #else
        390
        #endif
    }

    private static func enrich(_ account: TradingAccount, with other: TradingAccount?) -> TradingAccount {
        guard let other else { return account }
        var merged = account
        if merged.accountNumber == nil { merged.accountNumber = other.accountNumber }
        if merged.size == nil { merged.size = other.size }
        if merged.propFirmRules == nil { merged.propFirmRules = other.propFirmRules }
        if merged.customPublicStatus == nil { merged.customPublicStatus = other.customPublicStatus }
        return merged
    }
}

extension OwnerAccountsSnapshotKind {
    fileprivate var rawValue: String {
        switch self {
        case .rest: return "rest"
        case .dashboard: return "dashboard"
        }
    }
}
