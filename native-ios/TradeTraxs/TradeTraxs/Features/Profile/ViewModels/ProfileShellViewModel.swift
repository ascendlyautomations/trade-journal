import Foundation
import Observation

/// Owns Profile section selection and lazily created section ViewModels.
///
/// Sections load once on first visit and retain cached results while the Profile
/// root stays alive — no duplicate fetches when switching tabs.
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

    func select(_ section: ProfileSection) {
        guard selectedSection != section else {
            activate(section)
            return
        }
        ExperienceHaptics.play(.selection)
        selectedSection = section
        activate(section)
    }

    /// Ensures the visible section has started loading.
    func activateSelected() {
        activate(selectedSection)
    }

    func refreshSelected() async {
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
                    isOwner: isOwner
                )
            }
            trades?.loadIfNeeded()
        case .posts:
            if posts == nil {
                posts = PostsContainerViewModel(
                    profileID: profileID,
                    profiles: data.profiles,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache
                )
            }
            posts?.loadIfNeeded()
        case .clips:
            if clips == nil {
                clips = ClipsContainerViewModel(
                    profileID: profileID,
                    feed: data.feed,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache
                )
            }
            clips?.loadIfNeeded()
        case .stats:
            if stats == nil {
                stats = StatsContainerViewModel(
                    profileID: profileID,
                    trades: data.trades,
                    achievements: data.achievements,
                    detailCache: data.detailCache
                )
            }
            stats?.loadIfNeeded()
        case .achievements:
            if achievements == nil {
                achievements = AchievementsContainerViewModel(
                    profileID: profileID,
                    achievements: data.achievements,
                    navigationCoordinator: navigationCoordinator,
                    detailCache: data.detailCache
                )
            }
            achievements?.loadIfNeeded()
        }
    }
}
