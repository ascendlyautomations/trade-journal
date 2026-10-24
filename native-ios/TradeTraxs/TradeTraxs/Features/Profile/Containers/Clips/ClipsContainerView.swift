import SwiftUI

struct ClipsContainerView: View {
    @Bindable var viewModel: ClipsContainerViewModel
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var browseLayout = ProfileBrowseLayoutStore.layout(for: .clips)

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
        ]
    }

    var body: some View {
        ProfileSectionContainerChrome(
            section: .clips,
            state: viewModel.state,
            emptyMessage: viewModel.isOwner ? nil : ProfileSection.clips.emptyMessage,
            emptyActionTitle: viewModel.isOwner ? "Add Clip" : nil,
            emptyAction: viewModel.isOwner ? { viewModel.addClip() } : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack {
                    Spacer(minLength: 0)
                    ProfileBrowseLayoutToggle(layout: $browseLayout)
                }
                .onChange(of: browseLayout) { _, layout in
                    ProfileBrowseLayoutStore.save(layout, for: .clips)
                }

                if browseLayout == .grid {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(viewModel.items) { reel in
                            ProfileClipGridTile(
                                reel: reel,
                                imagePipeline: imagePipeline,
                                title: ClipDisplayTitle.text(for: reel, cache: detailCache),
                                onOpen: { viewModel.openClip(reel) }
                            )
                            .task {
                                await viewModel.loadMoreIfNeeded(currentReelID: reel.id)
                            }
                        }
                    }
                    .accessibilityIdentifier("profile.clips.grid")
                } else {
                    clipList
                }
            }
            .onChange(of: viewModel.items.map(\.id)) { _, ids in
                viewModel.prefetchEngagement(for: ids)
            }
            .onAppear {
                viewModel.prefetchEngagement(for: viewModel.items.map(\.id))
            }
        }
    }

    private var clipList: some View {
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
                .task {
                    await viewModel.loadMoreIfNeeded(currentReelID: reel.id)
                }
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: viewModel.items.map(\.id)
        )
        .accessibilityIdentifier("profile.clips.list")
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
