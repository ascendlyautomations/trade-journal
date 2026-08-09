import SwiftUI

/// Production retained 5-tab shell.
///
/// Create is an action tab: selection presents compose UI and does not steal
/// the content tab's retained stack.
struct MainTabShellView: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    @Bindable var currentUserProfile: CurrentUserProfileStore

    var body: some View {
        // `tabBarMinimizeBehavior` is iOS 26+; on iOS 18 the tab bar never minimizes.
        if #available(iOS 26.0, *) {
            tabView.tabBarMinimizeBehavior(.never)
        } else {
            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: tabSelection) {
            Tab(TabIdentifier.home.displayName, systemImage: TabIdentifier.home.systemImage, value: TabIdentifier.home) {
                HomeNavigationStack(store: store, coordinator: coordinator)
            }

            Tab(TabIdentifier.feed.displayName, systemImage: TabIdentifier.feed.systemImage, value: TabIdentifier.feed) {
                FeedNavigationStack(store: store, coordinator: coordinator)
            }

            Tab(TabIdentifier.create.displayName, systemImage: TabIdentifier.create.systemImage, value: TabIdentifier.create) {
                // Action tab — selection is intercepted; keep a real view so the tab bar never blanks.
                CreateTabPlaceholder()
            }

            Tab(TabIdentifier.messages.displayName, systemImage: TabIdentifier.messages.systemImage, value: TabIdentifier.messages) {
                MessagesNavigationStack(store: store, coordinator: coordinator)
            }

            // Profile tab uses a Label so we can swap in the session avatar UIImage
            // (alwaysOriginal + pre-clipped). Falls back to the SF Symbol when unset.
            Tab(value: TabIdentifier.profile) {
                ProfileNavigationStack(
                    store: store,
                    coordinator: coordinator,
                    authenticationCoordinator: authenticationCoordinator,
                    currentUserProfile: currentUserProfile
                )
            } label: {
                Label {
                    Text(TabIdentifier.profile.displayName)
                } icon: {
                    if let avatar = currentUserProfile.tabBarAvatarUIImage {
                        Image(uiImage: avatar)
                    } else {
                        Image(systemName: TabIdentifier.profile.systemImage)
                    }
                }
            }
        }
    }

    private var tabSelection: Binding<TabIdentifier> {
        Binding(
            get: { store.selectedTab },
            set: { newValue in
                coordinator.selectTab(newValue)
            }
        )
    }
}

// MARK: - Per-tab stacks

struct HomeNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator

    var body: some View {
        NavigationStack(path: homePath) {
            NavigationInfrastructurePlaceholder(
                title: "Home",
                subtitle: "Today cockpit root — feature UI arrives later.",
                systemImage: TabIdentifier.home.systemImage
            )
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Activity", systemImage: "bell") {
                        coordinator.open(.profile(.activity))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Trades") {
                        coordinator.open(.home(.trades))
                    }
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                NavigationInfrastructurePlaceholder(
                    title: homeTitle(route),
                    subtitle: String(describing: route),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .navigationTitle(homeTitle(route))
            }
        }
    }

    private var homePath: Binding<[HomeRoute]> {
        Binding(
            get: { store.paths.home },
            set: { store.paths.home = $0 }
        )
    }

    private func homeTitle(_ route: HomeRoute) -> String {
        switch route {
        case .trades: return "Trades"
        case .tradeDetail: return "Trade"
        case .calendar: return "Calendar"
        case .tools: return "Tools"
        case .propFirm: return "Prop Firm"
        case .analyst: return "Analyst"
        case .backtest: return "Backtest"
        case .achievements: return "Achievements"
        case .achievementDetail: return "Achievement"
        case .streaks: return "Streaks"
        case .report: return "Report"
        }
    }
}

struct FeedNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        NavigationStack(path: feedPath) {
            NavigationInfrastructurePlaceholder(
                title: "Feed",
                subtitle: "Social root — Explore, Rooms, Leaderboard push here.",
                systemImage: TabIdentifier.feed.systemImage
            )
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Explore", systemImage: "magnifyingglass") {
                        coordinator.open(.feed(.explore))
                    }
                    Button("Rooms", systemImage: "person.3") {
                        coordinator.open(.feed(.rooms))
                    }
                }
            }
            .navigationDestination(for: FeedRoute.self) { route in
                feedDestination(route)
            }
        }
    }

    private var feedPath: Binding<[FeedRoute]> {
        Binding(
            get: { store.paths.feed },
            set: { store.paths.feed = $0 }
        )
    }

    @ViewBuilder
    private func feedDestination(_ route: FeedRoute) -> some View {
        switch route {
        case .profile(let profileID):
            ProfileView(
                profileID: profileID,
                currentUserProfile: appEnvironment.currentUserProfile,
                navigationCoordinator: coordinator,
                data: appEnvironment.data
            )
        case .rooms:
            TradeRoomsHomeView(
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .feed
            )
        case .room(let roomID):
            RoomConversationView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .feed
            )
        case .roomMembers(let roomID):
            RoomMembersView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .feed
            )
        case .roomInfo(let roomID):
            RoomInfoView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .feed
            )
        default:
            NavigationInfrastructurePlaceholder(
                title: feedTitle(route),
                subtitle: String(describing: route),
                systemImage: "rectangle.stack"
            )
            .navigationTitle(feedTitle(route))
        }
    }

    private func feedTitle(_ route: FeedRoute) -> String {
        switch route {
        case .post: return "Post"
        case .reel: return "Reel"
        case .story: return "Story"
        case .trade: return "Trade"
        case .profile: return "Profile"
        case .explore: return "Explore"
        case .leaderboard: return "Leaderboard"
        case .rooms: return "Trade Rooms"
        case .room: return "Trade Room"
        case .roomMembers: return "Members"
        case .roomInfo: return "Room Info"
        }
    }
}

struct MessagesNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        NavigationStack(path: messagesPath) {
            MessagesHomeView(
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
            .navigationDestination(for: MessagesRoute.self) { route in
                messagesDestination(route)
            }
        }
    }

    private var messagesPath: Binding<[MessagesRoute]> {
        Binding(
            get: { store.paths.messages },
            set: { store.paths.messages = $0 }
        )
    }

    @ViewBuilder
    private func messagesDestination(_ route: MessagesRoute) -> some View {
        switch route {
        case .thread(let conversationID):
            ConversationView(
                conversationID: conversationID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        case .profile(let profileID):
            ProfileView(
                profileID: profileID,
                currentUserProfile: appEnvironment.currentUserProfile,
                navigationCoordinator: coordinator,
                data: appEnvironment.data
            )
        case .room(let roomID):
            RoomConversationView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        case .roomMembers(let roomID):
            RoomMembersView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        case .roomInfo(let roomID):
            RoomInfoView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        default:
            NavigationInfrastructurePlaceholder(
                title: messagesTitle(route),
                subtitle: String(describing: route),
                systemImage: "bubble.left"
            )
            .navigationTitle(messagesTitle(route))
        }
    }

    private func messagesTitle(_ route: MessagesRoute) -> String {
        switch route {
        case .thread: return "Conversation"
        case .sharedTrade: return "Shared Trade"
        case .sharedPost: return "Shared Post"
        case .sharedReel: return "Shared Reel"
        case .profile: return "Profile"
        case .room: return "Trade Room"
        case .roomMembers: return "Members"
        case .roomInfo: return "Room Info"
        }
    }
}

struct ProfileNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    @Bindable var currentUserProfile: CurrentUserProfileStore
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        NavigationStack(path: profilePath) {
            ProfileView(
                store: currentUserProfile,
                navigationCoordinator: coordinator,
                authenticationCoordinator: authenticationCoordinator,
                data: appEnvironment.data
            )
            .navigationDestination(for: ProfileRoute.self) { route in
                profileDestination(route)
            }
        }
    }

    private var profilePath: Binding<[ProfileRoute]> {
        Binding(
            get: { store.paths.profile },
            set: { store.paths.profile = $0 }
        )
    }

    @ViewBuilder
    private func profileDestination(_ route: ProfileRoute) -> some View {
        switch route {
        case .trade(let tradeID):
            TradeDetailView(tradeID: tradeID, data: appEnvironment.data)
        case .post(let postID):
            PostDetailView(postID: postID, data: appEnvironment.data)
        case .reel(let reelID):
            ClipDetailView(reelID: reelID, data: appEnvironment.data)
        case .achievement(let achievementID):
            AchievementDetailView(achievementID: achievementID, data: appEnvironment.data)
        case .followers(let profileID):
            FollowListView(
                kind: .followers,
                listOwnerID: profileID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        case .following(let profileID):
            FollowListView(
                kind: .following,
                listOwnerID: profileID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator
            )
        case .otherProfile(let profileID):
            ProfileView(
                profileID: profileID,
                currentUserProfile: currentUserProfile,
                navigationCoordinator: coordinator,
                data: appEnvironment.data
            )
        case .rooms:
            TradeRoomsHomeView(
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .profile
            )
        case .room(let roomID):
            RoomConversationView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .profile
            )
        case .roomMembers(let roomID):
            RoomMembersView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .profile
            )
        case .roomInfo(let roomID):
            RoomInfoView(
                roomID: roomID,
                data: appEnvironment.data,
                navigationCoordinator: coordinator,
                navigationHost: .profile
            )
        default:
            NavigationInfrastructurePlaceholder(
                title: profileTitle(route),
                subtitle: String(describing: route),
                systemImage: "person"
            )
            .navigationTitle(profileTitle(route))
        }
    }

    private func profileTitle(_ route: ProfileRoute) -> String {
        switch route {
        case .activity: return "Activity"
        case .followers: return "Followers"
        case .following: return "Following"
        case .followRequests: return "Follow Requests"
        case .settings: return "Settings"
        case .referrals: return "Referrals"
        case .affiliate: return "Affiliate"
        case .help: return "Help"
        case .otherProfile: return "Profile"
        case .trade: return "Trade"
        case .post: return "Post"
        case .reel: return "Reel"
        case .achievement: return "Achievement"
        case .rooms: return "Trade Rooms"
        case .room: return "Trade Room"
        case .roomMembers: return "Members"
        case .roomInfo: return "Room Info"
        }
    }
}

/// Create tab content is never shown — coordinator intercepts selection.
private struct CreateTabPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
