import SwiftUI

struct PostsContainerView: View {
    @Bindable var viewModel: PostsContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore
    var profilePin: ProfilePinCallbacks? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        ProfileSectionContainerChrome(
            section: .posts,
            state: viewModel.state,
            emptyMessage: viewModel.isOwner ? nil : ProfileSection.posts.emptyMessage,
            emptyActionTitle: viewModel.isOwner ? "Add Post" : nil,
            emptyAction: viewModel.isOwner ? { viewModel.addPost() } : nil,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(viewModel.items) { post in
                    ProfilePostCard(
                        post: post,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        vaultStore: vaultStore,
                        onOpen: { viewModel.openPost(post) },
                        isOwner: viewModel.isOwner,
                        onReport: reportAction(for: post),
                        profilePin: profilePin
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentPostID: post.id)
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
            .accessibilityIdentifier("profile.posts.list")
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
