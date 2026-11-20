import SwiftUI

/// Livestream chat list + composer (viewer sheet + OBS manage stream).
struct RoomBroadcastStudioChatPane: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let userId: String?
    let displayName: String
    @Binding var chatDraft: String
    /// Expanded viewer: Send key + focus reporting for compact video chrome.
    var useViewerKeyboardChrome: Bool = false
    var composerFocusedBinding: Binding<Bool>? = nil
    var replyTargetBinding: Binding<BroadcastChatMessageItem?>? = nil
    @Environment(\.themeColors) private var colors
    @FocusState private var composerFocused: Bool
    @State private var internalReplyTarget: BroadcastChatMessageItem?

    private var replyTarget: Binding<BroadcastChatMessageItem?> {
        replyTargetBinding ?? $internalReplyTarget
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = coordinator.broadcastChatNavigationNotice {
                navigationNoticeBar(notice)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                        ForEach(coordinator.chatMessages) { msg in
                            RoomBroadcastChatRow(
                                message: msg,
                                imagePipeline: imagePipeline,
                                coordinator: coordinator,
                                isHighlighted: coordinator.highlightedBroadcastChatMessageID == msg.id,
                                onReply: { beginReply(to: msg) }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                }
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(useViewerKeyboardChrome ? .interactively : .automatic)
                .onChange(of: coordinator.chatMessages.count) { _, _ in
                    scrollToLatestMessage(using: proxy)
                }
                .onChange(of: composerFocused) { _, focused in
                    composerFocusedBinding?.wrappedValue = focused
                    if focused, useViewerKeyboardChrome {
                        scrollToLatestMessage(using: proxy)
                    }
                }
                .onChange(of: coordinator.broadcastChatScrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(request.messageID, anchor: .center)
                    }
                }
            }
            if let target = replyTarget.wrappedValue {
                replyComposerBanner(for: target)
            }
            RoomBroadcastChatComposer(
                coordinator: coordinator,
                userId: userId,
                displayName: displayName,
                chatDraft: $chatDraft,
                replyTarget: replyTarget,
                useViewerKeyboardChrome: useViewerKeyboardChrome,
                composerFocus: $composerFocused
            )
        }
    }

    private func navigationNoticeBar(_ notice: String) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Text(notice)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(colors.secondaryText)
            Spacer(minLength: 0)
            Button("OK") {
                coordinator.acknowledgeBroadcastChatNavigationNotice()
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .buttonStyle(.experiencePlain)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.fillSecondary.opacity(0.9))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                if coordinator.broadcastChatNavigationNotice == notice {
                    coordinator.acknowledgeBroadcastChatNavigationNotice()
                }
            }
        }
    }

    private func replyComposerBanner(for message: BroadcastChatMessageItem) -> some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: message.userId)
        let name = profile?.displayName ?? message.displayName
        return HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(colors.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(name)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.accent)
                    .lineLimit(1)
                Text(BroadcastChatReplyFormatting.previewText(message.text))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(colors.tertiaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                cancelReply()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(colors.fillSecondary, in: Circle())
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
        .accessibilityIdentifier("tradeRooms.broadcast.chat.replyBanner")
    }

    private func beginReply(to message: BroadcastChatMessageItem) {
        ExperienceHaptics.play(.selection)
        replyTarget.wrappedValue = message
        composerFocused = true
    }

    private func cancelReply() {
        replyTarget.wrappedValue = nil
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy) {
        guard let last = coordinator.chatMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

/// Message field + send (viewer + OBS manage stream).
struct RoomBroadcastChatComposer: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    let userId: String?
    let displayName: String
    @Binding var chatDraft: String
    @Binding var replyTarget: BroadcastChatMessageItem?
    var useViewerKeyboardChrome: Bool = false
    @FocusState.Binding var composerFocus: Bool

    @Environment(\.themeColors) private var colors
    @State private var keyboardSendScheduled = false
    @State private var isSendingChat = false

    var body: some View {
        HStack(alignment: .bottom, spacing: ExperienceSpacing.xxs) {
            composerTextField
                .frame(maxWidth: .infinity, alignment: .leading)

            if canSendChat {
                Button(action: sendChat) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(colors.accent)
                        .experienceTouchTarget()
                }
                .buttonStyle(.experiencePlain)
                .disabled(isSendingChat)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
        .experienceFormFocusSync($composerFocus)
    }

    private var composerTextField: some View {
        TextField("Message…", text: $chatDraft, axis: .vertical)
            .lineLimit(1 ... 4)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.sentences)
            .focused($composerFocus)
            .disabled(userId == nil || isSendingChat)
            .submitLabel(useViewerKeyboardChrome ? .send : .return)
            .onSubmit {
                if useViewerKeyboardChrome {
                    submitFromKeyboard()
                }
            }
            .onChange(of: chatDraft) { previous, updated in
                guard useViewerKeyboardChrome else { return }
                guard ComposerKeyboardSubmit.insertedReturn(from: previous, to: updated) else { return }
                chatDraft = previous
                submitFromKeyboard()
            }
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
    }

    private var canSendChat: Bool {
        guard userId != nil, !isSendingChat else { return false }
        return !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func replyReference(for message: BroadcastChatMessageItem) -> BroadcastChatReplyReference {
        let profile = coordinator.chatProfileCache.profile(forUserId: message.userId)
        let name = profile?.displayName ?? message.displayName
        return BroadcastChatReplyFormatting.reference(for: message, displayName: name)
    }

    private func submitFromKeyboard() {
        guard useViewerKeyboardChrome else { return }
        guard !keyboardSendScheduled else { return }
        guard canSendChat else { return }
        keyboardSendScheduled = true
        sendChat()
        Task { @MainActor in
            keyboardSendScheduled = false
        }
    }

    private func sendChat() {
        guard let userId else { return }
        guard !isSendingChat else { return }
        let trimmed = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let reply = replyTarget.map(replyReference(for:))
        chatDraft = ""
        replyTarget = nil
        isSendingChat = true
        Task {
            await coordinator.sendChat(
                userId: userId,
                displayName: displayName,
                avatarUrl: nil,
                text: trimmed,
                replyTo: reply
            )
            isSendingChat = false
        }
    }
}