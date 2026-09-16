import Foundation

/// Local demo viewer id for Profile/Messages UI — never an access token or Supabase session.
nonisolated struct DemoSessionProvider: SessionProviding {
    let profileID: ProfileID

    init(profileID: ProfileID = DemoExperienceSupport.profileID) {
        self.profileID = profileID
    }

    var currentUserID: UserID? {
        get async { UserID(profileID.rawValue) }
    }

    var accessToken: String? {
        get async { nil }
    }
}
