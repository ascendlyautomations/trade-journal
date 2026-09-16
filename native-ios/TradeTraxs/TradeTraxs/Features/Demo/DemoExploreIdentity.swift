import Foundation

/// Canonical Explore Mode local journal identity (not a Supabase user).
nonisolated enum DemoExploreIdentity {
    static let profileID = DemoExperienceSupport.profileID

    /// Same asset as ``LoginView`` branding (`Image("AppLogo")`).
    static let appLogoAssetName = "AppLogo"

    static let username = "tradetraxs"
    static let displayName = "TradeTraxs Test"
    static var handle: String { "@\(username)" }

    static let bio =
        "Explore Mode demo journal · futures & index day trading with TradeTraxs."

    static func avatarReference() -> MediaReference {
        DemoExploreBundledAvatar.reference(assetName: appLogoAssetName)
    }

    static func profile(now: Date = Date()) -> Profile {
        let started = Calendar.current.date(byAdding: .year, value: -2, to: now)
        return Profile(
            id: profileID,
            userID: UserID(profileID.rawValue),
            username: username,
            displayName: displayName,
            bio: bio,
            avatar: avatarReference(),
            traderType: .futures,
            tradingStyle: "Session structure",
            primaryMarket: "NQ",
            startedTradingAt: started,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_740_000_000)
        )
    }
}
