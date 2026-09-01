import SwiftUI

/// Reusable comment list — Trade / Post / Clip detail.
struct CommentListView: View {
    @Bindable var viewModel: CommentsViewModel
    let currentUserID: ProfileID?
    let imagePipeline: any ImagePipeline
    @State private var pendingDelete: InteractionComment?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack {
                Text("Comments")
                    .experienceStyle(.headline, color: colors.primaryText)
                Spacer()
                Picker("Sort", selection: Binding(
                    get: { viewModel.sort },
                    set: { viewModel.setSort($0) }
                )) {
                    Text("Oldest").tag(CommentSortOrder.oldest)
                    Text("Newest").tag(CommentSortOrder.newest)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("interaction.comment.sort")
            }

            if viewModel.isLoading && viewModel.comments.isEmpty {
                ExperienceLoadingSpinner(label: "Loading comments")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.lg)
            } else if let error = viewModel.errorMessage, viewModel.comments.isEmpty {
                ExperienceErrorState(
                    title: "Couldn't load comments",
                    message: error,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else if viewModel.topLevelComments.isEmpty {
                ExperienceEmptyState(
                    icon: .messages,
                    title: "No comments yet",
                    message: "Start the discussion — ask a question or share what you noticed."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.topLevelComments) { comment in
                        CommentRowView(
                            comment: comment,
                            isOwn: currentUserID == comment.authorProfileID,
                            imagePipeline: imagePipeline,
                            likeSnapshot: viewModel.likeSnapshot(for: comment.id),
                            canLike: viewModel.canLikeComments,
                            isLikeBusy: viewModel.isCommentLikeBusy(comment.id),
                            onToggleLike: {
                                Task { await viewModel.toggleCommentLike(comment) }
                            },
                            canPin: viewModel.canPinComment(comment),
                            isPinBusy: viewModel.isCommentPinBusy(comment.id),
                            onTogglePin: { pinned in
                                Task { await viewModel.toggleCommentPin(comment, pinned: pinned) }
                            },
                            onDelete: currentUserID == comment.authorProfileID
                                ? {
                                    ExperienceHaptics.play(.warning)
                                    pendingDelete = comment
                                }
                                : nil
                        )
                        ForEach(viewModel.replies(to: comment.id)) { reply in
                            CommentRowView(
                                comment: reply,
                                isOwn: currentUserID == reply.authorProfileID,
                                imagePipeline: imagePipeline,
                                likeSnapshot: viewModel.likeSnapshot(for: reply.id),
                                canLike: viewModel.canLikeComments,
                                isLikeBusy: viewModel.isCommentLikeBusy(reply.id),
                                onToggleLike: {
                                    Task { await viewModel.toggleCommentLike(reply) }
                                },
                                canPin: false,
                                isPinBusy: false,
                                onTogglePin: nil,
                                onDelete: currentUserID == reply.authorProfileID
                                    ? {
                                        ExperienceHaptics.play(.warning)
                                        pendingDelete = reply
                                    }
                                    : nil
                            )
                            .padding(.leading, ExperienceSpacing.xl)
                        }
                    }
                }
            }

            CommentComposerView(viewModel: viewModel)
        }
        .confirmationDialog(
            "Delete comment?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let comment = pendingDelete else { return }
                pendingDelete = nil
                Task { await viewModel.delete(comment) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This comment will be removed.")
        }
        .accessibilityIdentifier("interaction.comment.list")
    }
}
