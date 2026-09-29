import SwiftUI

struct AdminPlaceholderView: View {
    let route: AdminRoute

    @Environment(\.themeColors) private var colors

    private var title: String {
        switch route {
        case .contentReports: return "Content Reports"
        default: return "Admin"
        }
    }

    var body: some View {
        List {
            Section {
                SettingsIntroBlock(
                    title: "Coming in the next phase",
                    message: "This queue will match the web Admin module. Users is available now."
                )
            }
        }
        .adminScreenHeading(title)
        .experienceInsetGroupedListStyle(pageBackground: true)
        .adminExperienceChrome()
    }
}
