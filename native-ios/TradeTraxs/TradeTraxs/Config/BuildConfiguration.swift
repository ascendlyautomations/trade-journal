import Foundation

/// Compile-time / scheme-selected deployment lane.
///
/// Staging is activated with the `STAGING` active compilation condition
/// (add via an Xcode scheme / xcconfig when that lane is wired).
enum BuildConfiguration: String, Sendable, CaseIterable {
    case debug
    case staging
    case production

    /// Resolves the active lane for this binary.
    static var current: BuildConfiguration {
        #if STAGING
        return .staging
        #elseif DEBUG
        return .debug
        #else
        return .production
        #endif
    }

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}
