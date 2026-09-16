import SwiftUI

struct StoryReplyInputView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let isSending: Bool
    let onSend: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            TextField("Send message...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .disabled(isSending)
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.vertical, ExperienceSpacing.sm + 2)
                .background(Color.white.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit(sendIfPossible)

            Button(action: sendIfPossible) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.blue, in: Circle())
            }
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send story reply")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.95), .black.opacity(0.75), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .accessibilityIdentifier("feed.story.replyInput")
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
        }
        .onChange(of: isFocused) { _, focused in
            fieldFocused = focused
        }
        .experienceFormFocusSync($fieldFocused)
    }

    private func sendIfPossible() {
        guard !isSending else { return }
        onSend()
    }
}
