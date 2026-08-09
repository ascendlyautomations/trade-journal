import SwiftUI

/// Reusable comment list — Trade / Post / Clip detail.
struct CommentListView: View {
    @Bindable var viewModel: CommentsViewModel
    let currentUserID: ProfileID?

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
                Text("No comments yet")
                    .experienceStyle(.body, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.topLevelComments) { comment in
                        CommentRowView(
                            comment: comment,
                            isOwn: currentUserID == comment.authorProfileID,
                            onDelete: currentUserID == comment.authorProfileID
                                ? { Task { await viewModel.delete(comment) } }
                                : nil
                        )
                        ForEach(viewModel.replies(to: comment.id)) { reply in
                            CommentRowView(
                                comment: reply,
                                isOwn: currentUserID == reply.authorProfileID,
                                onDelete: currentUserID == reply.authorProfileID
                                    ? { Task { await viewModel.delete(reply) } }
                                    : nil
                            )
                            .padding(.leading, ExperienceSpacing.xl)
                        }
                    }
                }
            }

            CommentComposerView(viewModel: viewModel)
        }
        .accessibilityIdentifier("interaction.comment.list")
    }
}
