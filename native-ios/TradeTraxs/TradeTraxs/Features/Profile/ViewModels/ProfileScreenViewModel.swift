import Foundation
import Observation

/// Canonical Profile screen owner — one bootstrap, one ``ProfileState``, render-only children.
///
/// Reference architecture for every TradeTraxs screen:
/// Screen ViewModel → coordinated bootstrap → shared state → section VMs apply / paginate only.
@Observable
@MainActor
final class ProfileScreenViewModel {
    private(set) var state = ProfileState()
    let contentStore: ProfileContentStore
    let headerViewModel: ProfileHeaderViewModel
    private(set) var shellViewModel: ProfileShellViewModel?

    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator
    private let showsOwnerChrome: Bool
    private let target: ProfileContentStore.Target

    private var bootstrapTask: Task<Void, Never>?

    init(
        target: ProfileContentStore.Target,
        currentUserProfile _: CurrentUserProfileStore,
        navigationCoordinator: NavigationCoordinator,
        authenticationCoordinator _: AuthenticationCoordinator?,
        data: DataEnvironment,
        showsOwnerChrome: Bool
    ) {
        self.target = target
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.showsOwnerChrome = showsOwnerChrome

        let content = ProfileContentStore(
            target: target,
            profiles: data.profiles,
            rooms: data.rooms,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache
        )
        contentStore = content
        headerViewModel = ProfileHeaderViewModel(
            store: content,
            messages: data.messages,
            session: data.session,
            navigationCoordinator: navigationCoordinator
        )
    }

    var showsSettingsToolbar: Bool {
        showsOwnerChrome && contentStore.isOwner
    }

    /// Exactly one bootstrap on first presentation (unless already completed).
    func onAppear(currentUserProfile: CurrentUserProfileStore) {
        seedOwnerCacheIfNeeded(from: currentUserProfile)
        if state.didBootstrap {
            publish(state)
            return
        }
        bootstrapIfNeeded(force: false)
    }

    /// Standard lifecycle — first coordinated bootstrap (no-op when already done).
    func bootstrapIfNeeded() async {
        await performBootstrap(force: false)
    }

    /// Pull-to-refresh — explicit full-screen re-bootstrap.
    func refresh() async {
        ExperienceHaptics.play(.selection)
        state.isRefreshing = true
        await performBootstrap(force: true)
        state.isRefreshing = false
    }

    /// Profile pagination lives on section VMs after bootstrap; screen-level no-op.
    func loadMore() async {}

    /// Profile has no screen-owned realtime loop today.
    func subscribeRealtime() {}

    func unsubscribeRealtime() {}

    /// Header retry button — same as pull-to-refresh.
    func retryBootstrap() {
        bootstrapIfNeeded(force: true)
    }

    func syncShellIfNeeded() {
        guard let profileID = state.profileID ?? contentStore.resolvedProfileID else {
            shellViewModel = nil
            return
        }
        if shellViewModel?.profileID != profileID {
            shellViewModel = ProfileShellViewModel(
                profileID: profileID,
                data: data,
                navigationCoordinator: navigationCoordinator,
                isOwner: state.isOwner || contentStore.isOwner
            )
        }
        shellViewModel?.apply(state: state)
    }

    func reconcileOwnershipIfNeeded() {
        guard let id = state.profileID ?? contentStore.resolvedProfileID,
              shellViewModel?.profileID == id,
              shellViewModel?.isOwner != contentStore.isOwner
        else { return }
        shellViewModel = ProfileShellViewModel(
            profileID: id,
            data: data,
            navigationCoordinator: navigationCoordinator,
            isOwner: contentStore.isOwner
        )
        shellViewModel?.apply(state: state)
        activateShellForLaunch()
    }

    func activateShellForLaunch() {
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

    func openSettings() {
        headerViewModel.openSettings()
    }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded(force: Bool) {
        if let bootstrapTask, !force { return }
        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            await self?.performBootstrap(force: force)
        }
    }

    private func performBootstrap(force: Bool) async {
        if !force, state.didBootstrap { return }

        if state.profile == nil {
            state.phase = .loading
            contentStore.applyBootstrap(state)
        }

        let next = await ProfileBootstrap.load(
            .init(
                target: target,
                profiles: data.profiles,
                trades: data.trades,
                achievements: data.achievements,
                feed: data.feed,
                rooms: data.rooms,
                session: data.session,
                detailCache: data.detailCache,
                force: force
            )
        )
        guard !Task.isCancelled else { return }
        publish(next)
        bootstrapTask = nil
    }

    private func publish(_ next: ProfileState) {
        var next = next
        if next.phase == .loaded {
            next.lastUpdated = Date()
        }
        // Preserve in-flight refresh flag across publish.
        next.isRefreshing = state.isRefreshing
        state = next
        contentStore.applyBootstrap(next)
        syncShellIfNeeded()
        activateShellForLaunch()

        // Prefetch engagement for the default trades surface from the screen owner.
        if let trades = shellViewModel?.trades {
            trades.prefetchEngagement(for: next.trades.map(\.id))
        }
    }

    private func seedOwnerCacheIfNeeded(from currentUserProfile: CurrentUserProfileStore) {
        guard case .currentUser = target else { return }
        if let profile = currentUserProfile.profile {
            data.detailCache.seed(profile)
        }
        if let stats = currentUserProfile.stats {
            data.detailCache.seed(stats: stats)
        }
    }
}

extension ProfileScreenViewModel: ScreenLifecycle {}
