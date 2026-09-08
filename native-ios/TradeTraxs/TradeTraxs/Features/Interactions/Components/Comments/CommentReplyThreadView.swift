import SwiftUI

/// Nested reply thread under a top-level comment — mirrors web `CommentReplyThread`.
struct CommentReplyThreadView: View {
    @Bindable var viewModel: CommentsViewModel
    let rootComment: InteractionComment
    let currentUserID: ProfileID?
    let imagePipeline: any ImagePipeline
    let onRequestDelete: (InteractionComment) -> Void
    let commentReportAction: (InteractionComment) -> (() -> Void)?

    @Environment(\.themeColors) private var colors

    private var replies: [InteractionComment] {
        viewModel.replies(to: rootComment.id)
    }

    private var display: CommentThreadSupport.ReplyThreadDisplay<InteractionComment> {
        CommentThreadSupport.replyThreadDisplay(
            replies: replies,
            topLevelCommentCount: viewModel.topLevelComments.count,
            expanded: viewModel.isReplyThreadExpanded(rootComment.id)
        )
    }

    var body: some View {
        if replies.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                ForEach(display.visibleReplies) { reply in
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
                        onReply: { viewModel.beginReply(to: reply) },
                        onDelete: currentUserID == reply.authorProfileID
                            ? { onRequestDelete(reply) }
                            : nil,
                        onReport: commentReportAction(reply)
                    )
                    .padding(.leading, ExperienceSpacing.xl)
                }

                if display.showToggle {
                    Button {
                        viewModel.toggleReplyThread(rootComment.id)
                    } label: {
                        Text(
                            viewModel.isReplyThreadExpanded(rootComment.id)
                                ? "Hide replies"
                                : (display.collapsedLabel ?? "")
                        )
                        .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, ExperienceSpacing.xl)
                    .accessibilityIdentifier("interaction.comment.replyToggle.\(rootComment.id.rawValue)")
                }
            }
            .padding(.top, ExperienceSpacing.xxs)
        }
    }
}
