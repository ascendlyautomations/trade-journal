import OSLog
import SwiftUI

/// Settings → Admin entry — root only; deeper admin routes use ``ProfileRoute/admin(_:)``.
struct AdminPortalView: View {
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let currentUserProfile: CurrentUserProfileStore?

    @State private var isAuthorized = SessionBootstrapStore.shared.isPlatformAdmin

    var body: some View {
        Group {
            if isAuthorized {
                AdminHomeView(navigationCoordinator: navigationCoordinator)
            } else {
                List {
                    Section {
                        SettingsIntroBlock(
                            title: "Not authorized",
                            message: "This area is limited to TradeTraxs platform admins."
                        )
                    }
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
            }
        }
        .adminExperienceRootBackground()
        .adminExperienceChrome()
        .onAppear {
            isAuthorized = SessionBootstrapStore.shared.isPlatformAdmin
            #if DEBUG
            AppLog.navigation.debug(
                "admin.portal.appeared isPlatformAdmin=\(SessionBootstrapStore.shared.isPlatformAdmin, privacy: .public)"
            )
            #endif
        }
        .accessibilityIdentifier("admin.portal")
    }
}
