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
    static let sections: [SettingsHomeSection] = [
        SettingsHomeSection(
            id: "account",
            title: "Account",
            items: [
                SettingsHomeItem(route: .account, systemImage: "person.crop.circle"),
                SettingsHomeItem(route: .profile, systemImage: "person.text.rectangle"),
                SettingsHomeItem(route: .privacy, systemImage: "hand.raised"),
                SettingsHomeItem(route: .notifications, systemImage: "bell"),
            ]
        ),
        SettingsHomeSection(
            id: "tradetraxs",
            title: "TradeTraxs",
            items: [
                SettingsHomeItem(
                    route: .subscription,
                    systemImage: "creditcard",
                    displayTitle: "Subscription"
                ),
                SettingsHomeItem(
                    route: .tradingAccounts,
                    systemImage: "chart.bar.doc.horizontal",
                    displayTitle: "Trading Accounts"
                ),
                SettingsHomeItem(route: .payouts, systemImage: "building.columns"),
                SettingsHomeItem(route: .affiliate, systemImage: "gift"),
            ]
        ),
        SettingsHomeSection(
            id: "personal",
            title: "Personal",
            items: [
                SettingsHomeItem(route: .vault, systemImage: "hexagon.fill"),
                SettingsHomeItem(route: .appearance, systemImage: "circle.lefthalf.filled"),
            ]
        ),
        SettingsHomeSection(
            id: "support",
            title: "Support",
            items: [
                SettingsHomeItem(route: .support, systemImage: "questionmark.circle"),
                SettingsHomeItem(route: .about, systemImage: "info.circle"),
            ]
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
