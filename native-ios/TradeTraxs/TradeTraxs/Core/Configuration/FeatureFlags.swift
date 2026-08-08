import Foundation

/// Local feature-flag surface. Remote flags come later.
///
/// Debug may override; Staging/Production stay conservative until a remote
/// provider exists. No flags are active in Phase 2A.
struct FeatureFlags: Sendable, Equatable {
    /// Reserved for future Debug-only overrides.
    var localOverridesEnabled: Bool

    static func make(for buildConfiguration: BuildConfiguration) -> FeatureFlags {
        FeatureFlags(
            localOverridesEnabled: buildConfiguration == .debug
        )
    }
}
