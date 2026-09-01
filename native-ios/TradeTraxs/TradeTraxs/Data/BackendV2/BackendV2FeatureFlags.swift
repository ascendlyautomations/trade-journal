import Foundation
import OSLog

/// Backend V2 feature flags — all default OFF.
///
/// Runtime enable (iOS):
///   1. Process env `BACKEND_V2_SESSION=1` (Xcode Scheme)
///   2. UserDefaults `backendV2.session` = true
///   3. Test-only: `setFlagForTests(.session, enabled: true)`
///
/// Priority: test > processEnvironment > userDefaults > default(false)
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
    private static let defaults: [BackendV2FeatureFlag: Bool] = Dictionary(
        uniqueKeysWithValues: BackendV2FeatureFlag.allCases.map { ($0, false) }
    )

    nonisolated(unsafe) private static var testOverrides: [BackendV2FeatureFlag: Bool] = [:]
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
        return (defaults[flag] ?? false, "default")
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
        didLogStartup = false
    }

    /// DEBUG-only — logs N1 flags without printing other environment variables.
    static func logStartupFlags() {
        #if DEBUG
        guard !didLogStartup else { return }
        didLogStartup = true
        let logger = Logger(subsystem: AppLog.subsystem, category: "BackendV2.Flags")
        for flag in [BackendV2FeatureFlag.session, BackendV2FeatureFlag.dashboard] {
            let resolved = resolve(flag)
            logger.debug(
                "\(flag.dottedName, privacy: .public) enabled=\(resolved.enabled, privacy: .public) source=\(resolved.source, privacy: .public)"
            )
        }
        #endif
    }
}
