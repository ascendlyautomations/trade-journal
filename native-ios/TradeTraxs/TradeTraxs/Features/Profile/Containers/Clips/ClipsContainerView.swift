import SwiftUI

struct ClipsContainerView: View {
    @Bindable var viewModel: ClipsContainerViewModel
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore
    var profilePin: ProfilePinCallbacks? = nil
    var profilePinnedItems: [ProfilePinnedItem] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var browseLayout = ProfileBrowseLayoutStore.layout(for: .clips)
    @State private var shareTarget: SharedContentShareTarget?

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
                        ForEach(displayItems) { reel in
                            ProfileClipGridTile(
                                reel: reel,
                                imagePipeline: imagePipeline,
                                engagementStore: engagementStore,
                                title: ClipDisplayTitle.text(for: reel, cache: detailCache),
                                isOwner: viewModel.isOwner,
                                isPinned: isProfilePinned(reel),
                                profilePin: profilePin,
                                isDeleteInProgress: viewModel.isDeletingReel(reel.id),
                                onDelete: viewModel.isOwner
                                    ? {
                                        guard !viewModel.isDeletingReel(reel.id) else { return }
                                        viewModel.requestDelete(reel)
                                    }
                                    : nil,
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
            .onChange(of: displayItems.map(\.id)) { _, ids in
                viewModel.prefetchEngagement(for: ids)
            }
            .onAppear {
                viewModel.prefetchEngagement(for: displayItems.map(\.id))
            }
        }
        .confirmationDialog(
            "Delete Clip?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Clip", role: .destructive) {
                let reel = viewModel.pendingDelete
                Task { await viewModel.confirmDelete(reel: reel) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: {
            Text("This can’t be undone.")
        }
        .alert(
            "Couldn't delete clip",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .sheet(item: $shareTarget) { target in
            SharedContentShareSheet(
                target: target,
                data: appEnvironment.data,
                onClose: { shareTarget = nil }
            )
        }
    }

    private var displayItems: [Reel] {
        ProfilePinnedOrdering.displayItems(
            viewModel.items,
            profilePins: profilePinnedItems,
            contentType: .reel,
            contentID: { $0.id.rawValue }
        )
    }

    private func isProfilePinned(_ reel: Reel) -> Bool {
        profilePinnedItems.contains {
            $0.contentType == .reel && $0.contentID == reel.id.rawValue
        }
    }

    private var clipList: some View {
        LazyVStack(spacing: ExperienceSpacing.sm) {
            ForEach(displayItems) { reel in
                ProfileClipCard(
                    reel: reel,
                    detailCache: detailCache,
                    imagePipeline: imagePipeline,
                    engagementStore: engagementStore,
                    vaultStore: vaultStore,
                    onOpen: { viewModel.openClip(reel) },
                    onShare: { shareTarget = viewModel.shareClip(reel) },
                    isOwner: viewModel.isOwner,
                    onDelete: viewModel.isOwner
                        ? {
                            guard !viewModel.isDeletingReel(reel.id) else { return }
                            viewModel.requestDelete(reel)
                        }
                        : nil,
                    isDeleteInProgress: viewModel.isDeletingReel(reel.id),
                    onReport: reportAction(for: reel),
                    profilePin: profilePin,
                    isProfilePinned: isProfilePinned(reel)
                )
                .task {
                    await viewModel.loadMoreIfNeeded(currentReelID: reel.id)
                }
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: displayItems.map(\.id)
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
