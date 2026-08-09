import SwiftUI

struct PostsContainerView: View {
    @Bindable var viewModel: PostsContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProfileSectionContainerChrome(
            section: .posts,
            state: viewModel.state,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(viewModel.items) { post in
                    ProfilePostCard(
                        post: post,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        onOpen: { viewModel.openPost(post) }
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
                engagementStore.prefetch(ids.map { .profilePost($0) })
            }
            .onAppear {
                engagementStore.prefetch(viewModel.items.map { .profilePost($0.id) })
            }
            .accessibilityIdentifier("profile.posts.list")
        }
    }
}
