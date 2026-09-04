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
    case explore
    case leaderboard
    case tradeDetail
    case settings
    case propFirm
    case tradesList
    case gettingStarted

    var dottedName: String { "backendV2.\(rawValue)" }

    var processEnvKey: String {
        switch self {
        case .tradeDetail: return "BACKEND_V2_TRADE_DETAIL"
        case .messageThreads: return "BACKEND_V2_MESSAGE_THREADS"
        case .propFirm: return "BACKEND_V2_PROP_FIRM"
        case .tradesList: return "BACKEND_V2_TRADES_LIST"
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
