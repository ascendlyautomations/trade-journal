import SwiftUI

struct AchievementsContainerView: View {
    @Bindable var viewModel: AchievementsContainerViewModel
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    var profilePin: ProfilePinCallbacks? = nil
    var profilePinnedItems: [ProfilePinnedItem] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        ProfileSectionContainerChrome(
            section: .achievements,
            state: viewModel.state,
            emptyMessage: viewModel.isOwner ? nil : ProfileSection.achievements.emptyMessage,
            emptyActionTitle: viewModel.isOwner ? "Add Achievement" : nil,
            emptyAction: viewModel.isOwner ? { viewModel.addAchievement() } : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(displayItems) { achievement in
                    ProfileAchievementCard(
                        achievement: achievement,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        vaultStore: vaultStore,
                        onOpen: { viewModel.openAchievement(achievement) },
                        isOwner: viewModel.isOwner,
                        onReport: reportAction(for: achievement),
                        profilePin: profilePin,
                        isProfilePinned: isProfilePinned(achievement)
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentAchievementID: achievement.id)
                    }
                }
            }
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: displayItems.map(\.id)
            )
            .onChange(of: displayItems.map(\.id)) { _, ids in
                viewModel.prefetchEngagement(for: ids)
            }
            .onAppear {
                viewModel.prefetchEngagement(for: displayItems.map(\.id))
            }
            .accessibilityIdentifier("profile.achievements.list")
        }
    }

    private var displayItems: [Achievement] {
        ProfilePinnedOrdering.displayItems(
            viewModel.items,
            profilePins: profilePinnedItems,
            contentType: .achievement,
            contentID: { $0.id.rawValue }
        )
    }

    private func isProfilePinned(_ achievement: Achievement) -> Bool {
        profilePinnedItems.contains {
            $0.contentType == .achievement && $0.contentID == achievement.id.rawValue
        }
    }

    private func reportAction(for achievement: Achievement) -> (() -> Void)? {
        guard !viewModel.isOwner else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentAchievement(
                achievement.id,
                ownerID: viewModel.profileOwnerID,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}
