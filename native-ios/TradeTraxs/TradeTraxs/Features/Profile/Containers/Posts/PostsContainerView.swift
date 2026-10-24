import SwiftUI

struct PostsContainerView: View {
    @Bindable var viewModel: PostsContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore
    var profilePin: ProfilePinCallbacks? = nil
    var profilePinnedItems: [ProfilePinnedItem] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var browseLayout = ProfileBrowseLayoutStore.layout(for: .posts)

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 2),
            GridItem(.flexible(), spacing: 2),
        ]
    }

    var body: some View {
        ProfileSectionContainerChrome(
            section: .posts,
            state: viewModel.state,
            emptyMessage: viewModel.isOwner ? nil : ProfileSection.posts.emptyMessage,
            emptyActionTitle: viewModel.isOwner ? "Add Post" : nil,
            emptyAction: viewModel.isOwner ? { viewModel.addPost() } : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack {
                    Spacer(minLength: 0)
                    ProfileBrowseLayoutToggle(layout: $browseLayout)
                }
                .onChange(of: browseLayout) { _, layout in
                    ProfileBrowseLayoutStore.save(layout, for: .posts)
                }

                if browseLayout == .grid {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(displayItems) { post in
                            ProfilePostGridTile(
                                post: post,
                                imagePipeline: imagePipeline,
                                isPinned: isProfilePinned(post),
                                onOpen: { viewModel.openPost(post) }
                            )
                            .task {
                                await viewModel.loadMoreIfNeeded(currentPostID: post.id)
                            }
                        }
                    }
                    .accessibilityIdentifier("profile.posts.grid")
                } else {
                    postList
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
            "Delete Post?",
            isPresented: Binding(
                get: { viewModel.pendingDelete != nil },
                set: { if !$0 { viewModel.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Post", role: .destructive) {
                let post = viewModel.pendingDelete
                Task { await viewModel.confirmDelete(post: post) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDelete = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Couldn't delete post",
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

    private var postList: some View {
        LazyVStack(spacing: ExperienceSpacing.sm) {
            ForEach(displayItems) { post in
                ProfilePostCard(
                    post: post,
                    imagePipeline: imagePipeline,
                    engagementStore: engagementStore,
                    vaultStore: vaultStore,
                    onOpen: { viewModel.openPost(post) },
                    isOwner: viewModel.isOwner,
                    onDelete: viewModel.isOwner
                        ? {
                            guard !viewModel.isDeletingPost(post.id) else { return }
                            viewModel.requestDelete(post)
                        }
                        : nil,
                    isDeleteInProgress: viewModel.isDeletingPost(post.id),
                    onReport: reportAction(for: post),
                    profilePin: profilePin,
                    isProfilePinned: isProfilePinned(post)
                )
                .task {
                    await viewModel.loadMoreIfNeeded(currentPostID: post.id)
                }
            }
        }
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: displayItems.map(\.id)
        )
        .accessibilityIdentifier("profile.posts.list")
    }

    private var displayItems: [Post] {
        ProfilePinnedOrdering.displayItems(
            viewModel.items,
            profilePins: profilePinnedItems,
            contentType: .profilePost,
            contentID: { $0.id.rawValue }
        )
    }

    private func isProfilePinned(_ post: Post) -> Bool {
        profilePinnedItems.contains {
            $0.contentType == .profilePost && $0.contentID == post.id.rawValue
        }
    }

    private func reportAction(for post: Post) -> (() -> Void)? {
        guard !viewModel.isOwner else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentPost(
                post.id,
                ownerID: viewModel.profileOwnerID,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}
