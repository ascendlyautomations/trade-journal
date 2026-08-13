import SwiftUI

/// Unified Profile root — same UI for the authenticated user and every other profile.
///
/// Ownership only swaps the action row (Edit/Share/Settings vs Follow/Following).
/// Data lifecycle is owned exclusively by ``ProfileScreenViewModel``.
struct ProfileView: View {
    @State private var screen: ProfileScreenViewModel

    private let showsOwnerChrome: Bool

    /// Observed so the tab Profile can seed session cache from the already-loaded owner store.
    @Bindable private var currentUserProfile: CurrentUserProfileStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Profile tab root — current user.
    init(
        store: CurrentUserProfileStore,
        navigationCoordinator: NavigationCoordinator,
        authenticationCoordinator: AuthenticationCoordinator,
        data: DataEnvironment
    ) {
        self.currentUserProfile = store
        self.showsOwnerChrome = true
        _screen = State(
            initialValue: ProfileScreenViewModel(
                target: .currentUser,
                currentUserProfile: store,
                navigationCoordinator: navigationCoordinator,
                authenticationCoordinator: authenticationCoordinator,
                data: data,
                showsOwnerChrome: true
            )
        )
    }

    /// Pushed Profile for any user (Followers / Feed / Detail / Search / …).
    init(
        profileID: ProfileID,
        currentUserProfile: CurrentUserProfileStore,
        navigationCoordinator: NavigationCoordinator,
        data: DataEnvironment
    ) {
        self.currentUserProfile = currentUserProfile
        self.showsOwnerChrome = false
        _screen = State(
            initialValue: ProfileScreenViewModel(
                target: .profile(profileID),
                currentUserProfile: currentUserProfile,
                navigationCoordinator: navigationCoordinator,
                authenticationCoordinator: nil,
                data: data,
                showsOwnerChrome: false
            )
        )
    }

    var body: some View {
        let contentStore = screen.contentStore
        let headerViewModel = screen.headerViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                ProfileHeaderView(store: contentStore, viewModel: headerViewModel)
                    .experiencePadding(.horizontal, .lg)
                    .padding(.top, ExperienceSpacing.sm)

                if let shellViewModel = screen.shellViewModel {
                    ProfileSectionPicker(
                        selection: Binding(
                            get: { shellViewModel.selectedSection },
                            set: { shellViewModel.select($0) }
                        )
                    )

                    ExperienceDivider()
                        .padding(.horizontal, ExperienceSpacing.lg)

                    sectionBody(shellViewModel)
                        .environment(\.appEnvironment, appEnvironment)
                } else if screen.state.phase == .loading && screen.state.profile == nil {
                    ProfileSectionPicker(selection: .constant(.trades))
                        .disabled(true)
                        .opacity(ExperienceOpacity.disabled)
                    ProfileSectionContainerChrome(
                        section: .trades,
                        state: .loading,
                        onRetry: {},
                        content: { EmptyView() }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .experienceScreenBackground()
        .experienceNavigationTitle(navigationTitle)
        .toolbar(.visible, for: .tabBar)
        .toolbar {
            if screen.showsSettingsToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: AppIcon.settings.systemName) {
                        screen.openSettings()
                    }
                    .accessibilityIdentifier("profile.toolbar.settings")
                }
            }
        }
        .refreshable {
            await screen.refresh()
        }
        .onAppear {
            headerViewModel.onRetryBootstrap = { screen.retryBootstrap() }
            screen.onAppear(currentUserProfile: currentUserProfile)
        }
        .onChange(of: screen.state.profileID) { _, _ in
            screen.syncShellIfNeeded()
            screen.activateShellForLaunch()
        }
        .onChange(of: contentStore.isOwner) { _, _ in
            screen.reconcileOwnershipIfNeeded()
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: screen.shellViewModel?.selectedSection
        )
        .accessibilityIdentifier(contentStore.isOwner ? "profile.root.owner" : "profile.root.other")
    }

    private var navigationTitle: String {
        if screen.contentStore.isOwner { return "Profile" }
        if let username = screen.contentStore.profile?.username, !username.isEmpty {
            return "@\(username)"
        }
        return "Profile"
    }

    @ViewBuilder
    private func sectionBody(_ shell: ProfileShellViewModel) -> some View {
        switch shell.selectedSection {
        case .trades:
            if let viewModel = shell.trades {
                TradesContainerView(
                    viewModel: viewModel,
                    imagePipeline: appEnvironment.data.imagePipeline,
                    engagementStore: appEnvironment.data.engagementStore
                )
            }
        case .posts:
            if let viewModel = shell.posts {
                PostsContainerView(
                    viewModel: viewModel,
                    imagePipeline: appEnvironment.data.imagePipeline,
                    engagementStore: appEnvironment.data.engagementStore
                )
            }
        case .clips:
            if let viewModel = shell.clips {
                ClipsContainerView(
                    viewModel: viewModel,
                    imagePipeline: appEnvironment.data.imagePipeline,
                    engagementStore: appEnvironment.data.engagementStore
                )
            }
        case .stats:
            if let viewModel = shell.stats {
                StatsContainerView(viewModel: viewModel)
            }
        case .achievements:
            if let viewModel = shell.achievements {
                AchievementsContainerView(
                    viewModel: viewModel,
                    imagePipeline: appEnvironment.data.imagePipeline,
                    engagementStore: appEnvironment.data.engagementStore
                )
            }
        }
    }
}
