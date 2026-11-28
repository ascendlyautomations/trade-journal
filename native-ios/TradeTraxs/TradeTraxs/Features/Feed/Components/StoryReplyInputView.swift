import SwiftUI
import UIKit

private enum StoryReplyInputViewMetrics {
    static var singleLineFieldHeight: CGFloat {
        ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight)
    }
}

struct StoryReplyInputView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let isSending: Bool
    var isStoryLiked: Bool = false
    var isTogglingStoryLike: Bool = false
    var onToggleStoryLike: (() -> Void)? = nil
    let onSend: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var keyboardSendScheduled = false
    @Environment(\.colorScheme) private var colorScheme

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !isSending && !trimmedText.isEmpty
    }

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.55)
    }

    private var fieldBorder: Color {
        Color.white.opacity(colorScheme == .dark ? 0.32 : 0.38)
    }

    private var fieldForeground: Color {
        .white
    }

    private var heartUnlikedColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.92)
            : Color.white
    }

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            if onToggleStoryLike != nil {
                Button {
                    onToggleStoryLike?()
                } label: {
                    Image(systemName: isStoryLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isStoryLiked ? Color.red : heartUnlikedColor)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isTogglingStoryLike)
                .opacity(isTogglingStoryLike ? 0.55 : 1)
                .accessibilityLabel(isStoryLiked ? "Unlike story" : "Like story")
                .accessibilityIdentifier("feed.story.likeButton")
            }

            ZStack(alignment: .leading) {
                if trimmedText.isEmpty {
                    Text("Send message...")
                        .foregroundStyle(Color.white.opacity(0.68))
                        .allowsHitTesting(false)
                }
                StoryReplyMultilineTextField(
                    text: $text,
                    isFocused: $isFocused,
                    isEnabled: !isSending,
                    onSubmit: submitFromKeyboard
                )
                .frame(maxWidth: .infinity)
                .frame(height: StoryReplyInputViewMetrics.singleLineFieldHeight)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm + 2)
            .background(fieldBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(fieldBorder, lineWidth: 1)
            }

            Button(action: submitFromKeyboard) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.blue, in: Circle())
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.45)
            .accessibilityLabel("Send story reply")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.95), .black.opacity(0.78), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .accessibilityIdentifier("feed.story.replyInput")
        .onChange(of: isFocused) { _, focused in
            guard fieldFocused != focused else { return }
            fieldFocused = focused
        }
        .experienceFormFocusSync($fieldFocused)
        .experienceSuppressKeyboardInputAccessory()
    }

    private func submitFromKeyboard() {
        guard !keyboardSendScheduled else { return }
        guard canSend else { return }
        keyboardSendScheduled = true
        fieldFocused = false
        isFocused = false
        onSend()
        Task { @MainActor in
            keyboardSendScheduled = false
        }
    }
}