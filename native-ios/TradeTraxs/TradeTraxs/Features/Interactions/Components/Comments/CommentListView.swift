import SwiftUI

/// Reusable comment list — Trade / Post / Clip detail and Clips bottom sheet.
struct CommentListView: View {
    enum Presentation {
        /// Full detail section — header, sort, list, composer.
        case detail
        /// Sheet scroll body — list rows only (header/composer provided by sheet chrome).
        case sheetScrollContent
    }

    @Bindable var viewModel: CommentsViewModel
    let currentUserID: ProfileID?
    let imagePipeline: any ImagePipeline
    var presentation: Presentation = .detail
    @State private var pendingDelete: InteractionComment?

    @Environment(\.themeColors) private var colors

    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Group {
            switch presentation {
            case .detail:
                detailBody
            case .sheetScrollContent:
                commentThreadContent
            }
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

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            commentHeader
            commentThreadContent
            CommentComposerView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var commentHeader: some View {
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
    }

    @ViewBuilder
    private var commentThreadContent: some View {
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
                        onReply: { viewModel.beginReply(to: comment) },
                        onDelete: currentUserID == comment.authorProfileID
                            ? {
                                ExperienceHaptics.play(.warning)
                                pendingDelete = comment
                            }
                            : nil,
                        onReport: commentReportAction(for: comment)
                    )
                    CommentReplyThreadView(
                        viewModel: viewModel,
                        rootComment: comment,
                        currentUserID: currentUserID,
                        imagePipeline: imagePipeline,
                        onRequestDelete: { reply in
                            ExperienceHaptics.play(.warning)
                            pendingDelete = reply
                        },
                        commentReportAction: commentReportAction(for:)
                    )
                }
            }
        }
    }

    private func commentReportAction(for comment: InteractionComment) -> (() -> Void)? {
        guard currentUserID != comment.authorProfileID else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            ContentReportSupport.presentComment(
                comment: comment,
                presenter: appEnvironment.contentReportPresenter
            )
        }
    }
}
