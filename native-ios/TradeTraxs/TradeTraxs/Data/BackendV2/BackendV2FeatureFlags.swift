import Foundation

/// Backend V2 feature flags — all default OFF.
///
/// Runtime enable (iOS):
///   1. Process env `BACKEND_V2_SESSION=1` (scheme / launch)
///   2. UserDefaults `backendV2.session` = true
///   3. Test-only: `setFlagForTests(.session, enabled: true)`
///
/// Priority: test > UserDefaults > process env > default(false)
nonisolated enum BackendV2FeatureFlag: String, CaseIterable, Sendable {
    case session
    case dashboard
    case feed
    case profile
    case messages
    case rooms
    case activity
    case calendar
    case explore
    case leaderboard
    case tradeDetail
    case settings

    var dottedName: String { "backendV2.\(rawValue)" }

    var processEnvKey: String {
        switch self {
        case .tradeDetail: return "BACKEND_V2_TRADE_DETAIL"
        default: return "BACKEND_V2_\(rawValue.uppercased())"
        }
    }
}

nonisolated enum BackendV2FeatureFlags {
    private static let defaults: [BackendV2FeatureFlag: Bool] = Dictionary(
        uniqueKeysWithValues: BackendV2FeatureFlag.allCases.map { ($0, false) }
    )

    nonisolated(unsafe) private static var testOverrides: [BackendV2FeatureFlag: Bool] = [:]

    static func isEnabled(_ flag: BackendV2FeatureFlag) -> Bool {
        resolve(flag).enabled
    }

    static func resolve(
        _ flag: BackendV2FeatureFlag
    ) -> (enabled: Bool, source: String) {
        if let override = testOverrides[flag] {
            return (override, "test")
        }
        if UserDefaults.standard.object(forKey: flag.dottedName) != nil {
            return (UserDefaults.standard.bool(forKey: flag.dottedName), "userDefaults")
        }
        if let env = ProcessInfo.processInfo.environment[flag.processEnvKey] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "on", "yes"].contains(trimmed) {
                return (true, "env")
            }
            if ["0", "false", "off", "no"].contains(trimmed) {
                return (false, "env")
            }
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
    }
}
