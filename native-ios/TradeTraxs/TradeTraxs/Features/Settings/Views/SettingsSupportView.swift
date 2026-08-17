import SwiftUI

struct SettingsSupportView: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.openURL) private var openURL

    private let supportEmail = URL(string: "mailto:support@tradetraxs.com")
    private let helpURL = URL(string: "https://www.tradetraxs.com/help")
    private let supportURL = URL(string: "https://www.tradetraxs.com/support")
    private let feedbackURL = URL(string: "https://www.tradetraxs.com/feedback")

    var body: some View {
        List {
            Section {
                if let helpURL {
                    Button {
                        openURL(helpURL)
                    } label: {
                        SettingsNavigationRow(title: "Help Center", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                }
                if let supportURL {
                    Button {
                        openURL(supportURL)
                    } label: {
                        SettingsNavigationRow(title: "Contact Support", systemImage: "envelope")
                    }
                    .buttonStyle(.plain)
                }
                if let feedbackURL {
                    Button {
                        openURL(feedbackURL)
                    } label: {
                        SettingsNavigationRow(title: "Send Feedback", systemImage: "text.bubble")
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Help")
            } footer: {
                Text("Get answers or reach the TradeTraxs team.")
            }

            Section {
                if let supportEmail {
                    Button {
                        openURL(supportEmail)
                    } label: {
                        SettingsNavigationRow(
                            title: "Email Support",
                            subtitle: "support@tradetraxs.com",
                            systemImage: "envelope.open"
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Email")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Help & Support")
        .accessibilityIdentifier("settings.support")
    }
}
