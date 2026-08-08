import SwiftUI

/// Production retained 5-tab shell.
///
/// Create is an action tab: selection presents compose UI and does not steal
/// the content tab's retained stack.
struct MainTabShellView: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(TabIdentifier.home.displayName, systemImage: TabIdentifier.home.systemImage, value: TabIdentifier.home) {
                HomeNavigationStack(store: store, coordinator: coordinator)
            }

            Tab(TabIdentifier.feed.displayName, systemImage: TabIdentifier.feed.systemImage, value: TabIdentifier.feed) {
                FeedNavigationStack(store: store, coordinator: coordinator)
            }

            Tab(TabIdentifier.create.displayName, systemImage: TabIdentifier.create.systemImage, value: TabIdentifier.create) {
                // Content unused — Create selection is intercepted as an action.
                Color.clear
                    .accessibilityHidden(true)
            }

            Tab(TabIdentifier.messages.displayName, systemImage: TabIdentifier.messages.systemImage, value: TabIdentifier.messages) {
                MessagesNavigationStack(store: store, coordinator: coordinator)
            }

            Tab(TabIdentifier.profile.displayName, systemImage: TabIdentifier.profile.systemImage, value: TabIdentifier.profile) {
                ProfileNavigationStack(store: store, coordinator: coordinator)
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
                NavigationInfrastructurePlaceholder(
                    title: feedTitle(route),
                    subtitle: String(describing: route),
                    systemImage: "rectangle.stack"
                )
                .navigationTitle(feedTitle(route))
            }
        }
    }

    private var feedPath: Binding<[FeedRoute]> {
        Binding(
            get: { store.paths.feed },
            set: { store.paths.feed = $0 }
        )
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
        case .rooms: return "Rooms"
        case .room: return "Room"
        }
    }
}

struct MessagesNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator

    var body: some View {
        NavigationStack(path: messagesPath) {
            NavigationInfrastructurePlaceholder(
                title: "Messages",
                subtitle: "DM inbox root — threads push here.",
                systemImage: TabIdentifier.messages.systemImage
            )
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sample Thread") {
                        coordinator.open(.messages(.thread(ConversationID("sample"))))
                    }
                }
            }
            .navigationDestination(for: MessagesRoute.self) { route in
                NavigationInfrastructurePlaceholder(
                    title: messagesTitle(route),
                    subtitle: String(describing: route),
                    systemImage: "bubble.left"
                )
                .navigationTitle(messagesTitle(route))
            }
        }
    }

    private var messagesPath: Binding<[MessagesRoute]> {
        Binding(
            get: { store.paths.messages },
            set: { store.paths.messages = $0 }
        )
    }

    private func messagesTitle(_ route: MessagesRoute) -> String {
        switch route {
        case .thread: return "Thread"
        case .sharedTrade: return "Shared Trade"
        case .sharedPost: return "Shared Post"
        case .sharedReel: return "Shared Reel"
        case .profile: return "Profile"
        }
    }
}

struct ProfileNavigationStack: View {
    @Bindable var store: NavigationStore
    let coordinator: NavigationCoordinator

    var body: some View {
        NavigationStack(path: profilePath) {
            NavigationInfrastructurePlaceholder(
                title: "Profile",
                subtitle: "You — Activity, Settings, account gateway.",
                systemImage: TabIdentifier.profile.systemImage
            )
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        coordinator.open(.profile(.settings(nil)))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        coordinator.markUnauthenticated()
                    }
                }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                NavigationInfrastructurePlaceholder(
                    title: profileTitle(route),
                    subtitle: String(describing: route),
                    systemImage: "person"
                )
                .navigationTitle(profileTitle(route))
            }
        }
    }

    private var profilePath: Binding<[ProfileRoute]> {
        Binding(
            get: { store.paths.profile },
            set: { store.paths.profile = $0 }
        )
    }

    private func profileTitle(_ route: ProfileRoute) -> String {
        switch route {
        case .activity: return "Activity"
        case .followRequests: return "Follow Requests"
        case .settings: return "Settings"
        case .referrals: return "Referrals"
        case .affiliate: return "Affiliate"
        case .help: return "Help"
        case .otherProfile: return "Profile"
        case .trade: return "Trade"
        case .post: return "Post"
        case .reel: return "Reel"
        case .rooms: return "Rooms"
        case .room: return "Room"
        }
    }
}
