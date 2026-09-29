import SwiftUI

/// Help hub for Profile → Help and legacy deep links (Settings home opens support forms directly).
struct SettingsSupportView: View {
    @Environment(\.stackNavigation) private var stackNavigation

    var body: some View {
        List {
            Section {
                Button {
                    ExperienceHaptics.play(.selection)
                    stackNavigation?.pushSettings(.support)
                } label: {
                    SettingsNavigationRow(title: "Help & Support", systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.support.row.contact")

                Button {
                    ExperienceHaptics.play(.selection)
                    stackNavigation?.pushSettings(.productFeedback)
                } label: {
                    SettingsNavigationRow(title: "Product Feedback", systemImage: "text.bubble")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.support.row.feedback")

                Button {
                    ExperienceHaptics.play(.selection)
                    stackNavigation?.pushSettings(.supportBugReport)
                } label: {
                    SettingsNavigationRow(title: "Report a Bug", systemImage: "ladybug")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.support.row.bug")
            } header: {
                Text("Help Center")
            } footer: {
                Text("Reach the TradeTraxs team without leaving the app.")
            }
        }
        .experienceInsetGroupedListStyle(pageBackground: true)
        .experienceNavigationTitle("Help Center")
        .accessibilityIdentifier("settings.support.hub")
    }
}
