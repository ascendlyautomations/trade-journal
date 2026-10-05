import SwiftUI

/// Admin subdestinations on the Profile `NavigationStack` (no nested admin stack).
enum AdminProfileDestinationView {
    @ViewBuilder
    static func view(
        route: AdminRoute,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore?
    ) -> some View {
        adminDestination(
            route: route,
            data: data,
            navigationCoordinator: navigationCoordinator,
            currentUserProfile: currentUserProfile
        )
        .adminExperienceRootBackground()
        .adminExperienceChrome()
    }

    @ViewBuilder
    private static func adminDestination(
        route: AdminRoute,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore?
    ) -> some View {
        switch route {
        case .charts:
            AdminChartsView(data: data)
        case .users:
            AdminUsersView(data: data, navigationCoordinator: navigationCoordinator)
        case .userDetail(let user):
            AdminUserDetailView(
                data: data,
                user: user,
                navigationCoordinator: navigationCoordinator
            )
        case .contentReports:
            AdminContentReportsView(data: data, navigationCoordinator: navigationCoordinator)
        case .contentReportDetail(let snapshot):
            AdminContentReportDetailView(
                data: data,
                snapshot: snapshot,
                navigationCoordinator: navigationCoordinator,
                currentUserProfile: currentUserProfile
            )
        case .inspectTrade, .inspectPost, .inspectReel, .inspectAchievement, .inspectProfile, .inspectRoom:
            AdminContentInspectViews.destination(
                route: route,
                data: data,
                navigationCoordinator: navigationCoordinator,
                currentUserProfile: currentUserProfile
            )
        case .support:
            AdminSupportTicketsView(data: data, navigationCoordinator: navigationCoordinator)
        case .supportTicketDetail(let snapshot):
            AdminSupportTicketDetailView(
                data: data,
                snapshot: snapshot,
                navigationCoordinator: navigationCoordinator
            )
        case .productFeedback:
            AdminProductFeedbackView(data: data, navigationCoordinator: navigationCoordinator)
        case .productFeedbackDetail(let snapshot):
            AdminProductFeedbackDetailView(
                data: data,
                snapshot: snapshot,
                navigationCoordinator: navigationCoordinator
            )
        case .bugReports:
            AdminBugReportsView(data: data, navigationCoordinator: navigationCoordinator)
        case .bugReportDetail(let snapshot):
            AdminBugReportDetailView(
                data: data,
                snapshot: snapshot,
                navigationCoordinator: navigationCoordinator
            )
        case .updates:
            AdminPlatformUpdatesView(data: data)
        case .demoMode:
            DemoModeAdminView(data: data, navigationCoordinator: navigationCoordinator)
        case .demoBrowse(let kind):
            DemoAdminBrowserView(data: data, navigationCoordinator: navigationCoordinator, kind: kind)
        case .demoEdit(let entity, let recordID, let isNew):
            DemoAdminEditorView(
                data: data,
                navigationCoordinator: navigationCoordinator,
                entity: entity,
                recordID: recordID,
                isNew: isNew
            )
        case .demoHistory:
            DemoAdminHistoryView(data: data)
        }
    }
}
