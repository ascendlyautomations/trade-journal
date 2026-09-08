import SwiftUI

struct CommentComposerView: View {
    @Bindable var viewModel: CommentsViewModel
    var viewerProfile: Profile?
    var imagePipeline: (any ImagePipeline)?

    @Environment(\.themeColors) private var colors
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            if let replyTarget = viewModel.replyTarget {
                replyBanner(for: replyTarget)
            }

            HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
                if let viewerProfile, let imagePipeline {
                    FollowListAvatarView(
                        profile: viewerProfile,
                        imagePipeline: imagePipeline,
                        size: 32
                    )
                }

                TextField(
                    viewModel.replyTarget == nil ? "Add a comment…" : "Add to reply…",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(colors.fillPrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.submit() }
                }
                .accessibilityIdentifier("interaction.comment.composer")

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.isPosting {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? colors.tertiaryText
                                    : colors.accent
                            )
                    }
                }
                .experienceTouchTarget()
                .disabled(
                    viewModel.isPosting
                        || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityLabel("Post comment")
                .accessibilityIdentifier("interaction.comment.send")
            }
        }
        .onChange(of: viewModel.composerFocusToken) { _, _ in
            focused = true
        }
    }

    @ViewBuilder
    private func replyBanner(for replyTarget: CommentThreadSupport.ReplyTarget) -> some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to @\(replyTarget.mentionUsername)")
                    .experienceStyle(.caption, color: colors.accent)
                if !replyTarget.preview.isEmpty {
                    Text("“\(replyTarget.preview)”")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                viewModel.cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(colors.fillPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("interaction.comment.replyCancel")
        }
        .padding(.horizontal, ExperienceSpacing.sm)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.fillPrimary.opacity(0.6), in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(colors.accent)
                .frame(width: 3)
        }
    }
}
