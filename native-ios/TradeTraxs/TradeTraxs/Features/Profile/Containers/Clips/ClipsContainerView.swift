import SwiftUI

struct ClipsContainerView: View {
    @Bindable var viewModel: ClipsContainerViewModel
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        ProfileSectionContainerChrome(
            section: .clips,
            state: viewModel.state,
            emptyMessage: viewModel.isOwner ? nil : ProfileSection.clips.emptyMessage,
            emptyActionTitle: viewModel.isOwner ? "Add Clip" : nil,
            emptyAction: viewModel.isOwner ? { viewModel.addClip() } : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(viewModel.items) { reel in
                    ProfileClipCard(
                        reel: reel,
                        detailCache: detailCache,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        vaultStore: vaultStore,
                        onOpen: { viewModel.openClip(reel) },
                        isOwner: viewModel.isOwner,
                        onReport: reportAction(for: reel)
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentReelID: reel.id)
                    }
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
            .accessibilityIdentifier("profile.clips.list")
        }
    }

    private func reportAction(for reel: Reel) -> (() -> Void)? {
        guard !viewModel.isOwner else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentReel(
                reel.id,
                ownerID: viewModel.profileOwnerID,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}
