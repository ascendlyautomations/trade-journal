import Foundation
import OSLog

/// Provider-agnostic post-authentication setup: profile shell + first-login metadata.
nonisolated struct AuthenticatedSessionBootstrap: Sendable {
    private let profiles: any ProfileRepository
    private let backend: any AuthenticationBackend

    init(profiles: any ProfileRepository, backend: any AuthenticationBackend) {
        self.profiles = profiles
        self.backend = backend
    }

    func finalize(
        session: AuthenticationSession,
        firstLoginHint: OAuthFirstLoginHint?
    ) async throws {
        let profileID = ProfileID(session.userID.rawValue)
        let profile = try await profiles.ensureProfileExists(for: profileID)

        guard let fullName = ProfileDisplayNamePolicy.normalized(firstLoginHint?.fullName) else {
            return
        }

        if !ProfileDisplayNamePolicy.isPlaceholder(profile.displayName) {
            return
        }

        try await backend.updateUserMetadata(
            accessToken: session.accessToken,
            metadata: ["full_name": fullName]
        )

        var updated = profile
        updated.displayName = fullName
        _ = try await profiles.updateProfile(updated)
    }
}

nonisolated struct OAuthFirstLoginHint: Sendable, Equatable {
    var fullName: String?
    var email: String?

    var hasContent: Bool {
        ProfileDisplayNamePolicy.normalized(fullName) != nil
            || ProfileDisplayNamePolicy.normalized(email) != nil
    }

    static func normalized(fullName: String?, email: String?) -> OAuthFirstLoginHint {
        OAuthFirstLoginHint(
            fullName: ProfileDisplayNamePolicy.normalized(fullName),
            email: ProfileDisplayNamePolicy.normalized(email)
        )
    }
}
