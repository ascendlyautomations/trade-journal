import Foundation

/// Backend V2 feature flags.
///
/// Shipped production flags default ON so Release/TestFlight archives match Debug
/// without relying on Xcode scheme environment variables.
///
/// Runtime override (iOS):
///   1. Process env `BACKEND_V2_SESSION=1` (Xcode Scheme / CI)
///   2. UserDefaults `backendV2.session` = true
///   3. Test-only: `setFlagForTests(.session, enabled: true)`
///
/// Priority: test > processEnvironment > userDefaults > productionDefault
nonisolated enum BackendV2FeatureFlag: String, CaseIterable, Sendable {
    case session
    case dashboard
    case feed
    case profile
    case messages
    case messageThreads
    case rooms
    case roomPresence
    case activity
    case calendar
    /// Aggregate-first Calendar (trade_daily_stats) — rollback via flag OFF.
    case calendarAnalyticsV2
    /// Calendar V2 reads prefer GRDB over JSON (Phase 5E) — Release default OFF.
    case calendarAnalyticsGRDB
    /// Aggregate-first Dashboard analytics — rollback via flag OFF.
    case dashboardAnalyticsV3
    /// Dashboard V3 reads prefer GRDB over JSON (Phase 5F) — Release default OFF.
    case dashboardAnalyticsGRDB
    case explore
    case leaderboard
    case tradeDetail
    case settings
    case propFirm
    case tradesList
    /// Phase 8D — Journal list TradeSummary V2 RPC (Release default OFF).
    case tradeJournalSummaryV2
    /// Phase 8E — Profile Trades tab TradeSummary V2 RPC (Release default OFF).
    case profileTradesSummaryV2
    case gettingStarted
    /// Lightweight cache reconciliation RPC — enable only after `rpc_v1_viewer_sync_state` is deployed.
    case viewerSyncState
    /// Phase 6D — `user_analytics_state` Realtime revision signal (Release default OFF).
    case analyticsRealtime
    /// Phase 6E — cheap revision RPC repair on lifecycle/connectivity (Release default OFF).
    case analyticsRevisionRepair
    /// Phase 7D — Profile Analytics V2 shadow fetch + parity only (Release default OFF).
    case profileAnalyticsV2Shadow
    /// Phase 7E — Profile Statistics presentation via Analytics V2 (Release default OFF).
    case profileAnalyticsV2
    /// Phase 7E — Profile Statistics GRDB cache (Release default OFF).
    case profileAnalyticsGRDB

    var dottedName: String { "backendV2.\(rawValue)" }

    var processEnvKey: String {
        switch self {
        case .tradeDetail: return "BACKEND_V2_TRADE_DETAIL"
        case .messageThreads: return "BACKEND_V2_MESSAGE_THREADS"
        case .propFirm: return "BACKEND_V2_PROP_FIRM"
        case .tradesList: return "BACKEND_V2_TRADES_LIST"
        case .tradeJournalSummaryV2: return "BACKEND_V2_TRADE_JOURNAL_SUMMARY_V2"
        case .profileTradesSummaryV2: return "BACKEND_V2_PROFILE_TRADES_SUMMARY_V2"
        case .calendarAnalyticsV2: return "BACKEND_V2_CALENDAR_ANALYTICS_V2"
        case .calendarAnalyticsGRDB: return "BACKEND_V2_CALENDAR_ANALYTICS_GRDB"
        case .dashboardAnalyticsV3: return "BACKEND_V2_DASHBOARD_ANALYTICS_V3"
        case .dashboardAnalyticsGRDB: return "BACKEND_V2_DASHBOARD_ANALYTICS_GRDB"
        case .analyticsRealtime: return "BACKEND_V2_ANALYTICS_REALTIME"
        case .analyticsRevisionRepair: return "BACKEND_V2_ANALYTICS_REVISION_REPAIR"
        case .profileAnalyticsV2Shadow: return "BACKEND_V2_PROFILE_ANALYTICS_V2_SHADOW"
        case .profileAnalyticsV2: return "BACKEND_V2_PROFILE_ANALYTICS_V2"
        case .profileAnalyticsGRDB: return "BACKEND_V2_PROFILE_ANALYTICS_GRDB"
        default: return "BACKEND_V2_\(rawValue.uppercased())"
        }
    }
}

nonisolated enum BackendV2FeatureFlags {
    /// Flags intentionally enabled for production Release archives (matches Debug scheme).
    static let productionShippedFlags: Set<BackendV2FeatureFlag> = [
        .session,
        .dashboard,
        .feed,
        .messages,
        .messageThreads,
        .rooms,
        .profile,
        .propFirm,
        .activity,
        .explore,
        .leaderboard,
        .calendar,
        .tradesList,
        .gettingStarted,
    ]

    nonisolated(unsafe) private static var testOverrides: [BackendV2FeatureFlag: Bool] = [:]
    nonisolated(unsafe) private static var suppressProductionDefaultsForTests = false
    nonisolated(unsafe) private static var didLogStartup = false

    static func isEnabled(_ flag: BackendV2FeatureFlag) -> Bool {
        resolve(flag).enabled
    }

    static func resolve(
        _ flag: BackendV2FeatureFlag
    ) -> (enabled: Bool, source: String) {
        if let override = testOverrides[flag] {
            return (override, "test")
        }
        if let env = ProcessInfo.processInfo.environment[flag.processEnvKey] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "on", "yes"].contains(trimmed) {
                return (true, "processEnvironment")
            }
            if ["0", "false", "off", "no"].contains(trimmed) {
                return (false, "processEnvironment")
            }
        }
        if UserDefaults.standard.object(forKey: flag.dottedName) != nil {
            return (UserDefaults.standard.bool(forKey: flag.dottedName), "userDefaults")
        }
        if suppressProductionDefaultsForTests {
            return (false, "default")
        }
#if DEBUG
        // Temporary Phase 3 device QA — not shipped in Release / productionShippedFlags.
        if flag == .calendarAnalyticsV2 {
            return (true, "debugDefault")
        }
        if flag == .calendarAnalyticsGRDB {
            return (true, "debugDefault")
        }
        if flag == .dashboardAnalyticsGRDB {
            return (true, "debugDefault")
        }
        if flag == .analyticsRealtime {
            return (true, "debugDefault")
        }
        if flag == .analyticsRevisionRepair {
            return (true, "debugDefault")
        }
        if flag == .profileAnalyticsV2Shadow {
            return (true, "debugDefault")
        }
        if flag == .profileAnalyticsV2 {
            return (true, "debugDefault")
        }
        if flag == .profileAnalyticsGRDB {
            return (true, "debugDefault")
        }
        if flag == .tradeJournalSummaryV2 {
            return (true, "debugDefault")
        }
        if flag == .profileTradesSummaryV2 {
            return (true, "debugDefault")
        }
#endif
        let enabled = productionShippedFlags.contains(flag)
        return (enabled, "productionDefault")
    }

    static func allFlags() -> [(flag: BackendV2FeatureFlag, name: String, enabled: Bool)] {
        BackendV2FeatureFlag.allCases.map {
            ($0, $0.dottedName, isEnabled($0))
        }
    }

    static func setFlagForTests(_ flag: BackendV2FeatureFlag, enabled: Bool?) {
        if let enabled {
            testOverrides[flag] = enabled
        } else {
            testOverrides.removeValue(forKey: flag)
        }
    }

    static func resetFlagsForTests() {
        testOverrides.removeAll()
        suppressProductionDefaultsForTests = true
        didLogStartup = false
    }

    static func enableProductionDefaultsForTests() {
        suppressProductionDefaultsForTests = false
    }

    /// Startup logging is handled by ``AppConfigurationValidator``; kept for tests.
    static func logStartupFlags() {
        guard !didLogStartup else { return }
        didLogStartup = true
    }
}
