import Foundation

enum SettingsFixtures {
    static let viewerID = ProfileID("dev.settings.viewer")

    static func profile(owner: ProfileID = viewerID) -> Profile {
        Profile(
            id: owner,
            userID: UserID(owner.rawValue),
            username: "settings_trader",
            displayName: "Settings Trader",
            bio: "Native Settings fixtures",
            avatar: nil,
            traderType: .futures,
            tradingStyle: "Discretionary",
            primaryMarket: "ES",
            startedTradingAt: Date(timeIntervalSince1970: 1_640_995_200),
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func preferences(userID: ProfileID = viewerID) -> NotificationPreferences {
        var prefs = NotificationPreferences.defaults(for: userID)
        prefs.set(.directMessagesEnabled, enabled: true)
        prefs.set(.productUpdatesEnabled, enabled: false)
        return prefs
    }

    static func billingStatus(profileID: ProfileID = viewerID) -> BillingStatus {
        BillingStatus(
            profileID: profileID,
            plan: .pro,
            lifecycle: .trialing,
            isProEntitled: true,
            dailyTradeLimit: nil,
            dailyPostLimit: nil,
            dailyMessageLimit: nil,
            maxTradeEntryAccounts: nil,
            trialEndsAt: Date().addingTimeInterval(86_400 * 5),
            currentPeriodEndsAt: Date().addingTimeInterval(86_400 * 30),
            billingInterval: .monthly,
            cancelAtPeriodEnd: false
        )
    }

    static func accounts(owner: ProfileID = viewerID) -> [TradingAccount] {
        [
            TradingAccount(
                id: TradingAccountID("dev.settings.personal"),
                ownerProfileID: owner,
                name: "Personal Sim",
                category: .personal,
                mode: .sim,
                size: Money(amount: 25_000, currencyCode: "USD"),
                isActive: true,
                canAddTrades: true
            ),
            TradingAccount(
                id: TradingAccountID("dev.settings.prop"),
                ownerProfileID: owner,
                name: "Alpha Futures 50K PROP",
                category: .propFirm,
                mode: .evaluation,
                size: Money(amount: 50_000, currencyCode: "USD"),
                isActive: true,
                canAddTrades: true,
                propFirmRules: PropFirmAccountRules(
                    consistencyPercent: 40,
                    maxDrawdown: 2_000,
                    dailyDrawdown: 1_000,
                    profitTarget: 3_000
                )
            ),
        ]
    }

    static func referral(owner: ProfileID = viewerID) -> Referral {
        Referral(
            id: ReferralID(owner.rawValue),
            referrerProfileID: owner,
            code: "TRADETRAXS",
            inviteeProfileID: nil,
            rewardDescription: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: nil
        )
    }
}
