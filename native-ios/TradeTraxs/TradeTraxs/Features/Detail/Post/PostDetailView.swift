import SwiftUI

/// Permanent Post detail destination — same hierarchy as Trade Detail.
struct PostDetailView: View {
    @State private var viewModel: PostDetailViewModel
    @State private var contentRevealed = false
    @State private var showsDeleteConfirm = false
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(postID: PostID, data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: PostDetailViewModel(
                postID: postID,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.post == nil:
                ExperienceLoadingSpinner(label: "Loading post")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where viewModel.post == nil:
                ExperienceErrorState(
                    title: "Couldn't load post",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            default:
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Post")
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.loadIfNeeded()
            data.engagementStore.prefetch([.profilePost(viewModel.postID)])
        }
        .experienceDetailEntry(revealed: contentRevealed, reduceMotion: reduceMotion)
        .onAppear {
            guard !contentRevealed else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                contentRevealed = true
            }
        }
        .confirmationDialog(
            "Delete Post?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Post", role: .destructive) {
                Task {
                    _ = await viewModel.deletePost()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.deleteErrorMessage ?? "This can’t be undone.")
        }
        .accessibilityIdentifier("detail.post.root")
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let post = viewModel.post {
                        DetailIdentityHeader(
                            initials: viewModel.authorInitials,
                            avatar: viewModel.authorAvatar,
                            displayName: viewModel.authorDisplayName,
                            username: viewModel.authorUsername,
                            dateText: TradeDisplay.dateText(post.createdAt),
                            isOwner: viewModel.isOwner,
                            contentLink: .post(post.id),
                            shareText: {
                                let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
                                if body.isEmpty { return "Post on TradeTraxs" }
                                return String(body.prefix(120))
                            }(),
                            deleteTitle: "Delete Post",
                            onDelete: viewModel.isOwner ? {
                                ExperienceHaptics.play(.warning)
                                showsDeleteConfirm = true
                            } : nil,
                            accessibilityIdentifier: "detail.post.identity"
                        )
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.sm)
                        .padding(.bottom, ExperienceSpacing.md)

                        mediaCarousel(post)

                        postBody(post, scrollProxy: proxy)
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.md)
                            .padding(.bottom, ExperienceSpacing.xl)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding(ExperienceSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ExperienceRadius.md))
            }
        }
    }

    private func postBody(_ post: Post, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            EngagementBar(
                target: .profilePost(post.id),
                store: data.engagementStore,
                onCommentTap: {
                    withAnimation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                    }
                }
            )

            caption(post)

            CommentsSectionView(target: .profilePost(post.id), data: data)
                .id(Self.commentsAnchorID)
        }
    }

    @ViewBuilder
    private func mediaCarousel(_ post: Post) -> some View {
        if post.media.isEmpty {
            ZStack {
                colors.fillPrimary
                ExperienceIcon(icon: .photo, size: .xl, color: colors.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        } else if post.media.count == 1 {
            AspectFitMediaView(
                reference: post.media[0],
                purpose: .postImage,
                imagePipeline: imagePipeline,
                accessibilityIdentifier: "detail.post.media",
                emptyIcon: .photo,
                allowsFullResolutionViewer: true,
                onDoubleTapLike: {
                    Task { await data.engagementStore.ensureLiked(on: .profilePost(post.id)) }
                }
            )
        } else {
            TabView {
                ForEach(Array(post.media.enumerated()), id: \.offset) { index, media in
                    AspectFitMediaView(
                        reference: media,
                        purpose: .postImage,
                        imagePipeline: imagePipeline,
                        accessibilityIdentifier: "detail.post.media.\(index)",
                        emptyIcon: .photo,
                        allowsFullResolutionViewer: true,
                        onDoubleTapLike: {
                            Task { await data.engagementStore.ensureLiked(on: .profilePost(post.id)) }
                        }
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200)
            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.58, 720))
            .accessibilityIdentifier("detail.post.media")
        }
    }

    @ViewBuilder
    private func caption(_ post: Post) -> some View {
        let body = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            Text(body)
                .experienceStyle(.body, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("detail.post.caption")
        }
    }

    private static let commentsAnchorID = "detail.post.comments"
}
