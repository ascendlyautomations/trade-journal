import SwiftUI

enum AdminContentInspectViews {
    @ViewBuilder
    static func destination(
        route: AdminRoute,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore?
    ) -> some View {
        switch route {
        case .inspectTrade(let tradeID):
            SocialTradeDetailView(
                tradeID: tradeID,
                data: data,
                navigationCoordinator: navigationCoordinator
            )
            .adminExperienceChrome()
        case .inspectPost(let postID):
            PostDetailView(
                postID: postID,
                data: data,
                navigationCoordinator: navigationCoordinator
            )
            .adminExperienceChrome()
        case .inspectReel(let reelID):
            ClipDetailView(
                reelID: reelID,
                data: data,
                navigationCoordinator: navigationCoordinator
            )
            .adminExperienceChrome()
        case .inspectAchievement(let achievementID):
            AchievementDetailView(
                achievementID: achievementID,
                data: data,
                navigationCoordinator: navigationCoordinator
            )
            .adminExperienceChrome()
        case .inspectProfile(let profileID):
            if let store = currentUserProfile {
                ProfileView(
                    profileID: profileID,
                    currentUserProfile: store,
                    navigationCoordinator: navigationCoordinator,
                    data: data
                )
                .adminExperienceChrome()
            } else {
                List {
                    SettingsIntroBlock(
                        title: "Profile unavailable",
                        message: "Could not load profile in this session."
                    )
                }
                .experienceInsetGroupedListStyle(pageBackground: true)
                .adminExperienceChrome()
            }
        case .inspectRoom(let roomID):
            RoomConversationView(
                roomID: roomID,
                data: data,
                navigationCoordinator: navigationCoordinator,
                navigationHost: .messages
            )
            .adminExperienceChrome()
        default:
            EmptyView()
        }
    }
}
