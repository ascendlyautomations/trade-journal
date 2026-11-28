import Foundation

/// Directory row on Settings home.
struct SettingsHomeItem: Identifiable, Hashable, Sendable {
    var id: SettingsRoute { route }
    let route: SettingsRoute
    let systemImage: String
    /// Optional home-row label; destination screens keep ``SettingsRoute/title``.
    var displayTitle: String? = nil

    var rowTitle: String { displayTitle ?? route.title }
}

struct SettingsHomeSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let items: [SettingsHomeItem]
}

enum SettingsHomeModel {
    /// Destinations shown on Settings home.
    /// Subscription and Referrals stay out of the 1.0 surface while their release flags are off.
    static var sections: [SettingsHomeSection] {
        [
            SettingsHomeSection(
                id: "account",
                title: "Account",
                items: accountItems
            ),
            SettingsHomeSection(
                id: "personal",
                title: "Personal",
                items: personalItems
            ),
            SettingsHomeSection(
                id: "tradetraxs",
                title: "TRADETRAXS",
                items: tradetraxsItems
            ),
            SettingsHomeSection(
                id: "legal",
                title: "Legal",
                items: [
                    SettingsHomeItem(route: .legalTerms, systemImage: "doc.text"),
                    SettingsHomeItem(route: .legalPrivacy, systemImage: "doc.plaintext"),
                    SettingsHomeItem(route: .legalCommunityGuidelines, systemImage: "person.3"),
                ]
            ),
        ]
    }

    private static var accountItems: [SettingsHomeItem] {
        var items: [SettingsHomeItem] = [
            SettingsHomeItem(route: .account, systemImage: "person.crop.circle"),
            SettingsHomeItem(route: .profile, systemImage: "person.text.rectangle"),
        ]
        if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled {
            items.append(
                SettingsHomeItem(
                    route: .subscription,
                    systemImage: "creditcard",
                    displayTitle: "Subscription"
                )
            )
        }
        items.append(SettingsHomeItem(route: .privacy, systemImage: "hand.raised"))
        items.append(SettingsHomeItem(route: .notifications, systemImage: "bell"))
        return items
    }

    /// Trading, vault, and appearance tools, formerly the TradeTraxs section plus vault/appearance.
    private static var personalItems: [SettingsHomeItem] {
        var items: [SettingsHomeItem] = [
            SettingsHomeItem(
                route: .tradingAnalytics,
                systemImage: "slider.horizontal.3",
                displayTitle: "Trading Rules"
            ),
            SettingsHomeItem(
                route: .tradingAccounts,
                systemImage: "chart.bar.doc.horizontal",
                displayTitle: "Trading Accounts"
            ),
            SettingsHomeItem(route: .payouts, systemImage: "building.columns"),
            SettingsHomeItem(
                route: .propFirmExpenses,
                systemImage: "creditcard",
                displayTitle: "Expense Tracker"
            ),
            SettingsHomeItem(route: .vault, systemImage: "hexagon.fill"),
            SettingsHomeItem(route: .storyArchive, systemImage: "clock.arrow.circlepath"),
            SettingsHomeItem(route: .appearance, systemImage: "circle.lefthalf.filled"),
        ]
        if IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled {
            items.append(SettingsHomeItem(route: .affiliate, systemImage: "gift"))
        }
        return items
    }

    /// Product help and walkthrough, formerly Support; App Walkthrough and Leave a Rating are injected in the view.
    private static var tradetraxsItems: [SettingsHomeItem] {
        [
            SettingsHomeItem(route: .whatsNew, systemImage: "sparkles"),
            SettingsHomeItem(route: .support, systemImage: "questionmark.circle"),
            SettingsHomeItem(route: .productFeedback, systemImage: "text.bubble"),
            SettingsHomeItem(route: .about, systemImage: "info.circle"),
        ]
    }
}
