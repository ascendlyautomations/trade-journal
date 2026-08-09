import SwiftUI

/// Unified Profile root — same UI for the authenticated user and every other profile.
///
/// Ownership only swaps the action row (Edit/Share/Settings vs Follow/Following).
struct ProfileView: View {
    @State private var contentStore: ProfileContentStore
    @State private var headerViewModel: ProfileHeaderViewModel
    @State private var shellViewModel: ProfileShellViewModel?

    private let authenticationCoordinator: AuthenticationCoordinator?
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
        self.authenticationCoordinator = authenticationCoordinator
        self.showsOwnerChrome = true
        let content = ProfileContentStore(
            target: .currentUser,
            profiles: data.profiles,
            rooms: data.rooms,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache
        )
        _contentStore = State(initialValue: content)
        _headerViewModel = State(
            initialValue: ProfileHeaderViewModel(
                store: content,
                messages: data.messages,
                session: data.session,
                navigationCoordinator: navigationCoordinator
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
        self.authenticationCoordinator = nil
        self.showsOwnerChrome = false
        let content = ProfileContentStore(
            target: .profile(profileID),
            profiles: data.profiles,
            rooms: data.rooms,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache
        )
        _contentStore = State(initialValue: content)
        _headerViewModel = State(
            initialValue: ProfileHeaderViewModel(
                store: content,
                messages: data.messages,
                session: data.session,
                navigationCoordinator: navigationCoordinator
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                ProfileHeaderView(store: contentStore, viewModel: headerViewModel)
                    .experiencePadding(.horizontal, .lg)
                    .padding(.top, ExperienceSpacing.sm)

                if let shellViewModel {
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
                } else if contentStore.phase == .loading && contentStore.profile == nil {
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
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbar {
            if showsOwnerChrome, contentStore.isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: AppIcon.settings.systemName) {
                        headerViewModel.openSettings()
                    }
                    .accessibilityIdentifier("profile.toolbar.settings")
                }
                if let authenticationCoordinator {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await authenticationCoordinator.logout()
                                ExperienceHaptics.play(.warning)
                            }
                        }
                        .accessibilityIdentifier("profile.signOut")
                    }
                }
            }
        }
        .refreshable {
            headerViewModel.retry()
            await shellViewModel?.refreshSelected()
        }
        .onAppear {
            seedOwnerCacheIfNeeded()
            headerViewModel.onAppear()
            syncShellIfNeeded()
            activateShellForLaunch()
        }
        .onChange(of: contentStore.resolvedProfileID) { _, _ in
            syncShellIfNeeded()
            activateShellForLaunch()
        }
        .onChange(of: contentStore.isOwner) { _, _ in
            // Rebuild trades VM if ownership flips after session resolution.
            if let id = contentStore.resolvedProfileID,
               shellViewModel?.profileID == id,
               shellViewModel?.isOwner != contentStore.isOwner
            {
                shellViewModel = ProfileShellViewModel(
                    profileID: id,
                    data: appEnvironment.data,
                    navigationCoordinator: appEnvironment.navigation.coordinator,
                    isOwner: contentStore.isOwner
                )
                activateShellForLaunch()
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: shellViewModel?.selectedSection
        )
        .accessibilityIdentifier(contentStore.isOwner ? "profile.root.owner" : "profile.root.other")
    }

    private var navigationTitle: String {
        if contentStore.isOwner { return "Profile" }
        if let username = contentStore.profile?.username, !username.isEmpty {
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

    private func seedOwnerCacheIfNeeded() {
        guard case .currentUser = contentStore.target else { return }
        if let profile = currentUserProfile.profile {
            appEnvironment.data.detailCache.seed(profile)
        }
        if let stats = currentUserProfile.stats {
            appEnvironment.data.detailCache.seed(stats: stats)
        }
    }

    private func syncShellIfNeeded() {
        guard let profileID = contentStore.resolvedProfileID ?? contentStore.profile?.id else {
            shellViewModel = nil
            return
        }
        if shellViewModel?.profileID != profileID {
            shellViewModel = ProfileShellViewModel(
                profileID: profileID,
                data: appEnvironment.data,
                navigationCoordinator: appEnvironment.navigation.coordinator,
                isOwner: contentStore.isOwner
            )
        }
    }

    private func activateShellForLaunch() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitesting-profile-stats") {
            shellViewModel?.select(.stats)
            return
        }
        if args.contains("-uitesting-profile-posts") {
            shellViewModel?.select(.posts)
            return
        }
        #endif
        shellViewModel?.activateSelected()
    }
}
