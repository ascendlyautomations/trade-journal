import SwiftUI

struct CommentComposerView: View {
    @Bindable var viewModel: CommentsViewModel

    @Environment(\.themeColors) private var colors
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
            TextField("Add a comment…", text: $viewModel.draft, axis: .vertical)
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
}
