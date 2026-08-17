import Foundation

/// Directory row on Settings home.
struct SettingsHomeItem: Identifiable, Hashable, Sendable {
    var id: SettingsRoute { route }
    let route: SettingsRoute
    let systemImage: String
    var subtitle: String? = nil
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
                SettingsHomeItem(route: .security, systemImage: "lock.shield"),
            ]
        ),
        SettingsHomeSection(
            id: "preferences",
            title: "Preferences",
            items: [
                SettingsHomeItem(route: .notifications, systemImage: "bell"),
                SettingsHomeItem(route: .appearance, systemImage: "circle.lefthalf.filled"),
            ]
        ),
        SettingsHomeSection(
            id: "tradetraxs",
            title: "TradeTraxs",
            items: [
                SettingsHomeItem(route: .subscription, systemImage: "creditcard"),
                SettingsHomeItem(route: .tradingAccounts, systemImage: "chart.bar.doc.horizontal"),
                SettingsHomeItem(
                    route: .propFirm,
                    systemImage: "building.columns",
                    subtitle: "Rules & limits"
                ),
                SettingsHomeItem(route: .affiliate, systemImage: "gift"),
            ]
        ),
        SettingsHomeSection(
            id: "privacy",
            title: "Privacy & Safety",
            items: [
                SettingsHomeItem(route: .privacy, systemImage: "hand.raised"),
            ]
        ),
        SettingsHomeSection(
            id: "support",
            title: "Support & Information",
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
                SettingsHomeItem(route: .legalRefund, systemImage: "arrow.uturn.backward"),
            ]
        ),
    ]
}
