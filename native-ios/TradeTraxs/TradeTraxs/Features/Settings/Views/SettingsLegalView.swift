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
                        SettingsPrimaryActionLabel(
                            title: "View \(route.title)",
                            systemImage: "safari"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    SettingsIntroBlock(
                        title: "Not available",
                        message: "This document isn’t available in the app yet."
                    )
                }
            } footer: {
                Text("Opens the latest version on the TradeTraxs website.")
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
