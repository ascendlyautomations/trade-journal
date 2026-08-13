import Foundation

/// Single-flight coalescing for `profiles.profile` / `profiles.stats`.
///
/// Thin typed façade over ``RepositoryRequestFlight`` so existing call sites and tests
/// keep a stable API. Concurrent callers for the same profile ID share one in-flight Task.
final class ProfileRequestFlight: @unchecked Sendable {
    static let shared = ProfileRequestFlight()

    private init() {}

    func profile(
        id: ProfileID,
        fetch: @escaping @Sendable () async throws -> Profile
    ) async throws -> Profile {
        try await RepositoryRequestFlight.shared.coalesce(
            key: "profiles.profile:\(id.rawValue)",
            resource: "profiles.profile",
            fetch: fetch
        )
    }

    func stats(
        for id: ProfileID,
        fetch: @escaping @Sendable () async throws -> ProfileStats
    ) async throws -> ProfileStats {
        try await RepositoryRequestFlight.shared.coalesce(
            key: "profiles.stats:\(id.rawValue)",
            resource: "profiles.stats",
            fetch: fetch
        )
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            RepositoryRequestFlight.shared.invalidate(prefix: "profiles.profile:\(profileID.rawValue)")
            RepositoryRequestFlight.shared.invalidate(prefix: "profiles.stats:\(profileID.rawValue)")
        } else {
            RepositoryRequestFlight.shared.invalidate(prefix: "profiles.profile:")
            RepositoryRequestFlight.shared.invalidate(prefix: "profiles.stats:")
        }
    }
}
