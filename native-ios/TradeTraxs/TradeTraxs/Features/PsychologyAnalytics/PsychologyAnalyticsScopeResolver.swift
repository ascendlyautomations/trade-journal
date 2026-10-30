import Foundation

/// Resolves dashboard-equivalent scope for psychology analytics when Dashboard is not hydrated.
nonisolated enum PsychologyAnalyticsScopeResolver {
    struct Resolved: Sendable, Equatable {
        var filter: DashboardClientScopeFilter
        var label: String
        var fingerprint: String
    }

    /// Default when no persisted dashboard filters exist — matches ``DashboardScopeFilterDraft.defaults``.
    static func defaultScope(linkedAccountModes: [TradingAccountID: TradingAccountMode]) -> Resolved {
        resolve(
            stored: nil,
            linkedAccountModes: linkedAccountModes
        )
    }

    static func resolve(
        profileID: ProfileID,
        linkedAccountModes: [TradingAccountID: TradingAccountMode]
    ) -> Resolved {
        resolve(
            stored: DashboardScopeFilterPersistence.load(profileID: profileID),
            linkedAccountModes: linkedAccountModes
        )
    }

    static func resolve(
        stored: DashboardScopeFilterPersistence.Stored?,
        linkedAccountModes: [TradingAccountID: TradingAccountMode]
    ) -> Resolved {
        var dateRange = DashboardDateRange.thirtyDays
        var customInterval: DateInterval?
        var accountMode = ProfileStatisticsMetrics.Mode.all
        var showPublicOnly = false

        if let stored {
            if let raw = stored.dateRangeRaw {
                if raw == DashboardDateRange.ytd.rawValue {
                    dateRange = .oneYear
                } else if let range = DashboardDateRange(rawValue: raw) {
                    dateRange = range
                }
            }
            if let start = stored.customStart, let end = stored.customEnd {
                customInterval = DashboardScopeFilterSupport.normalizedCustomInterval(start: start, end: end)
            }
            if let modeRaw = stored.accountModeRaw,
               DashboardScopeFilterSupport.dashboardAccountTypeCases.contains(where: { $0.rawValue == modeRaw }),
               let mode = ProfileStatisticsMetrics.Mode(rawValue: modeRaw)
            {
                accountMode = mode
            }
            if let publicOnly = stored.showPublicOnly {
                showPublicOnly = publicOnly
            }
        }

        let filter = DashboardClientScopeFilter(
            accountFilter: .all,
            dateRange: dateRange,
            customInterval: customInterval,
            accountMode: accountMode,
            showPublicOnly: showPublicOnly,
            linkedAccountModes: linkedAccountModes
        )
        let label = scopeLabel(for: filter)
        let fingerprint = fingerprint(scope: filter)
        return Resolved(filter: filter, label: label, fingerprint: fingerprint)
    }

    static func resolve(filter: DashboardClientScopeFilter, profileID: ProfileID) -> Resolved {
        let label = scopeLabel(for: filter)
        let fingerprint = fingerprint(profileID: profileID, scope: filter)
        return Resolved(filter: filter, label: label, fingerprint: fingerprint)
    }

    static func scopeLabel(for scope: DashboardClientScopeFilter) -> String {
        let timeframe = DashboardScopeFilterSupport.compactTimeLabel(
            dateRange: scope.dateRange,
            customInterval: scope.customInterval
        )
        let account = scope.accountFilter == .all ? "All accounts" : "Filtered accounts"
        return "\(timeframe) · \(account)"
    }

    static func fingerprint(scope: DashboardClientScopeFilter) -> String {
        let custom = scope.customInterval.map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" } ?? ""
        return [
            scope.accountFilter.storageKey,
            scope.dateRange.rawValue,
            custom,
            scope.accountMode.rawValue,
            scope.showPublicOnly ? "public" : "allVis",
        ].joined(separator: "|")
    }

    static func fingerprint(profileID: ProfileID, scope: DashboardClientScopeFilter) -> String {
        "\(profileID.rawValue)|\(fingerprint(scope: scope))"
    }
}

private extension DashboardAccountFilter {
    nonisolated var storageKey: String {
        switch self {
        case .all: return "all"
        case .account(let id): return "acct:\(id.rawValue)"
        }
    }
}
