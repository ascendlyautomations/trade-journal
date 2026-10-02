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
                        onDelete: viewModel.isOwner
                            ? {
                                guard !viewModel.isDeletingAchievement(achievement.id) else { return }
                                viewModel.requestDelete(achievement)
                            }
                            : nil,
                        isDeleteInProgress: viewModel.isDeletingAchievement(achievement.id),
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
        .confirmationDialog(
            "Delete Achievement?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Achievement", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: {
            Text("This permanently removes the achievement.")
        }
        .alert(
            "Couldn't delete achievement",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
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
