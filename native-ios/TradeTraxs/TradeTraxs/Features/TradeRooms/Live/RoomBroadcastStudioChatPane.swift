import SwiftUI

/// Livestream chat list + composer (viewer sheet + OBS manage stream).
struct RoomBroadcastStudioChatPane: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let userId: String?
    let displayName: String
    @Binding var chatDraft: String
    @Environment(\.themeColors) private var colors
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        ForEach(coordinator.chatMessages) { msg in
                            RoomBroadcastChatRow(
                                message: msg,
                                imagePipeline: imagePipeline,
                                coordinator: coordinator
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: coordinator.chatMessages.count) { _, _ in
                    if let last = coordinator.chatMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
            composerBar
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.xxs) {
            TextField("Message…", text: $chatDraft, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .focused($composerFocused)
                .disabled(userId == nil)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .frame(
                    minHeight: ExperienceAccessibility.minTouchTarget,
                    alignment: .leading
                )
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.lg, style: .continuous)
                )

            if canSendChat {
                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(colors.accent)
                        .experienceTouchTarget()
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
    }

    private var canSendChat: Bool {
        guard userId != nil else { return false }
        return !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendChat() {
        guard let userId else { return }
        let draft = chatDraft
        chatDraft = ""
        Task {
            await coordinator.sendChat(
                userId: userId,
                displayName: displayName,
                avatarUrl: nil,
                text: draft
            )
        }
    }
}
