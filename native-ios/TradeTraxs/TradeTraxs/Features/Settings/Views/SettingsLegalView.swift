import SwiftUI

/// Opens verified TradeTraxs legal URLs — does not hardcode document text.
struct SettingsLegalView: View {
    let route: SettingsRoute

    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                if let url = legalURL {
                    Button {
                        openURL(url)
                    } label: {
                        SettingsNavigationRow(
                            title: "Open \(route.title)",
                            subtitle: url.host.map { "\($0)\(url.path)" },
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Legal content for this page is not available yet.")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            } footer: {
                Text("Documents are loaded from the live TradeTraxs site so native Settings never ships stale legal copy.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle(route.title)
        .accessibilityIdentifier("settings.legal.\(route.rawValue)")
    }

    private var legalURL: URL? {
        switch route {
        case .legalTerms:
            return URL(string: "https://www.tradetraxs.com/terms")
        case .legalPrivacy:
            return URL(string: "https://www.tradetraxs.com/privacy")
        case .legalCommunityGuidelines:
            return URL(string: "https://www.tradetraxs.com/community-guidelines")
        case .legalRefund:
            return URL(string: "https://www.tradetraxs.com/refund-policy")
        default:
            return nil
        }
    }
}
