import Foundation

/// One OAuth provider sign-in (credential + Supabase token exchange) at a time.
actor OAuthSignInSingleFlight {
    static let shared = OAuthSignInSingleFlight()

    private enum ActiveProvider: Sendable {
        case apple
        case google
    }

    private var active: ActiveProvider?

    private init() {}

    /// Returns false when the same or another provider sign-in is already in flight.
    func tryBegin(_ provider: AuthenticationProviderKind) -> Bool {
        let mapped: ActiveProvider
        switch provider {
        case .apple: mapped = .apple
        case .google: mapped = .google
        default: return true
        }
        if active != nil { return false }
        active = mapped
        return true
    }

    func end(_ provider: AuthenticationProviderKind) {
        switch provider {
        case .apple:
            if active == .apple { active = nil }
        case .google:
            if active == .google { active = nil }
        default:
            break
        }
    }
}
