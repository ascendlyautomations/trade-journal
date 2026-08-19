import SwiftUI

struct AchievementsContainerView: View {
    @Bindable var viewModel: AchievementsContainerViewModel
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProfileSectionContainerChrome(
            section: .achievements,
            state: viewModel.state,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(viewModel.items) { achievement in
                    ProfileAchievementCard(
                        achievement: achievement,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        onOpen: { viewModel.openAchievement(achievement) }
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                }
            }
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.items.map(\.id)
            )
            .onChange(of: viewModel.items.map(\.id)) { _, ids in
                viewModel.prefetchEngagement(for: ids)
            }
            .onAppear {
                viewModel.prefetchEngagement(for: viewModel.items.map(\.id))
            }
            .accessibilityIdentifier("profile.achievements.list")
        }
    }
}
