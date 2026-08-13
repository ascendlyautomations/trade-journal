import Foundation
import Observation

/// Owns Profile section selection and render-oriented section ViewModels.
///
/// Section ViewModels receive ``ProfileState`` from the screen bootstrap — they do not
/// perform the initial repository load. They may paginate / refresh after mutations.
@Observable
@MainActor
final class ProfileShellViewModel {
    var selectedSection: ProfileSection = .trades

    private(set) var trades: TradesContainerViewModel?
    private(set) var posts: PostsContainerViewModel?
    private(set) var clips: ClipsContainerViewModel?
    private(set) var stats: StatsContainerViewModel?
    private(set) var achievements: AchievementsContainerViewModel?

    private(set) var profileID: ProfileID
    private(set) var isOwner: Bool
    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator

    private var latestState = ProfileState()

    init(
        profileID: ProfileID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        isOwner: Bool = true
    ) {
        self.profileID = profileID
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.isOwner = isOwner
    }

    /// Applies the screen bootstrap snapshot to every created section VM.
    func apply(state: ProfileState) {
        latestState = state
        isOwner = state.isOwner
        if let profileID = state.profileID {
            self.profileID = profileID
        }
        trades?.applyBootstrap(state)
        posts?.applyBootstrap(state)
        clips?.applyBootstrap(state)
        stats?.applyBootstrap(state)
        achievements?.applyBootstrap(state)
    }

    func select(_ section: ProfileSection) {
        guard selectedSection != section else {
            activate(section)
            return
        }
        ExperienceHaptics.play(.selection)
        selectedSection = section
        activate(section)
    }

    /// Ensures the visible section VM exists and has bootstrap data (no network).
    func activateSelected() {
        activate(selectedSection)
    }

    func refreshSelected() async {
        // Screen owns full refresh via ``ProfileScreenViewModel/refresh()``.
        // Section refresh remains for mutation-driven revalidation only.
        switch selectedSection {
        case .trades: await trades?.refresh()
        case .posts: await posts?.refresh()
        case .clips: await clips?.refresh()
        case .stats: await stats?.refresh()
        case .achievements: await achievements?.refresh()
        }
    }

    private func activate(_ section: ProfileSection) {
        switch section {
        case .trades:
            if trades == nil {
                trades = TradesContainerViewModel(
                    profileID: profileID,
                    trades: data.trades,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    engagementStore: data.engagementStore,
                    isOwner: isOwner
                )
            }
            trades?.applyBootstrap(latestState)
        case .posts:
            if posts == nil {
                posts = PostsContainerViewModel(
                    profileID: profileID,
                    profiles: data.profiles,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    engagementStore: data.engagementStore
                )
            }
            posts?.applyBootstrap(latestState)
        case .clips:
            if clips == nil {
                clips = ClipsContainerViewModel(
                    profileID: profileID,
                    feed: data.feed,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    engagementStore: data.engagementStore
                )
            }
            clips?.applyBootstrap(latestState)
        case .stats:
            if stats == nil {
                stats = StatsContainerViewModel(
                    profileID: profileID,
                    trades: data.trades,
                    achievements: data.achievements,
                    detailCache: data.detailCache
                )
            }
            stats?.applyBootstrap(latestState)
        case .achievements:
            if achievements == nil {
                achievements = AchievementsContainerViewModel(
                    profileID: profileID,
                    achievements: data.achievements,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache,
                    engagementStore: data.engagementStore,
                    viewerIsOwner: isOwner
                )
            }
            achievements?.applyBootstrap(latestState)
        }
    }
}
