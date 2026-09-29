import SwiftUI

struct AdminHomeView: View {
    let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                adminRow("Users", systemImage: "person.2", route: .users)
                adminRow("Content Reports", systemImage: "flag", route: .contentReports)
            } header: {
                Text("Moderation")
            }

            Section {
                adminRow("Charts", systemImage: "chart.xyaxis.line", route: .charts)
            } header: {
                Text("Analytics")
            }

            Section {
                adminRow("Support", systemImage: "lifepreserver", route: .support)
                adminRow("Bug Reports", systemImage: "ladybug", route: .bugReports)
                adminRow("Product Feedback", systemImage: "bubble.left.and.text.bubble.right", route: .productFeedback)
            } header: {
                Text("Customer Support")
            }
        }
        .adminScreenHeading("Admin")
        .experienceInsetGroupedListStyle(pageBackground: true)
        .listSectionSpacing(ExperienceSpacing.xxs)
        .adminExperienceRootBackground()
        .adminExperienceChrome()
        .accessibilityIdentifier("admin.home")
    }

    private func adminRow(_ title: String, systemImage: String, route: AdminRoute) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            navigationCoordinator.pushAdmin(route)
        } label: {
            SettingsNavigationRow(title: title, systemImage: systemImage)
        }
        .adminListRowInteraction()
        .accessibilityIdentifier("admin.home.row.\(title)")
    }
}
