import PhotosUI
import SwiftUI
import UIKit

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
    @State private var chatReactionPickerMessageID: String?

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
                    VStack(alignment: .leading, spacing: BroadcastChatRowLayout.listRowSpacing) {
                        ForEach(coordinator.chatMessages) { msg in
                            RoomBroadcastChatRow(
                                message: msg,
                                imagePipeline: imagePipeline,
                                coordinator: coordinator,
                                isHighlighted: coordinator.highlightedBroadcastChatMessageID == msg.id,
                                viewerUserID: userId,
                                onReply: { beginReply(to: msg) },
                                onOpenReactionPicker: {
                                    chatReactionPickerMessageID = msg.id
                                },
                                onToggleReaction: { emoji in
                                    guard let userId else { return }
                                    Task {
                                        _ = await coordinator.toggleBroadcastChatReaction(
                                            messageID: msg.id,
                                            userId: userId,
                                            emoji: emoji
                                        )
                                    }
                                }
                            )
                            .id(msg.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollDismissesKeyboard(useViewerKeyboardChrome ? .interactively : .automatic)
                .onAppear {
                    scrollToLatestMessage(using: proxy, animated: false)
                }
                .onChange(of: coordinator.chatMessages.count) { _, _ in
                    scrollToLatestMessage(using: proxy)
                }
                .onChange(of: coordinator.chatMessages.last?.id) { _, _ in
                    scrollToLatestMessage(using: proxy)
                }
                .onChange(of: coordinator.chatSharedTrades.count) { _, _ in
                    scrollToLatestMessage(using: proxy, animated: false)
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
            .frame(maxHeight: .infinity)
            if let target = replyTarget.wrappedValue {
                replyComposerBanner(for: target)
            }
            RoomBroadcastChatComposer(
                coordinator: coordinator,
                userId: userId,
                displayName: displayName,
                imagePipeline: imagePipeline,
                chatDraft: $chatDraft,
                replyTarget: replyTarget,
                useViewerKeyboardChrome: useViewerKeyboardChrome,
                composerFocus: $composerFocused
            )
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { chatReactionPickerMessageID != nil },
                set: { if !$0 { chatReactionPickerMessageID = nil } }
            )
        ) {
            if let messageID = chatReactionPickerMessageID, let userId {
                UnicodeEmojiPickerSheet { emoji in
                    chatReactionPickerMessageID = nil
                    Task {
                        _ = await coordinator.toggleBroadcastChatReaction(
                            messageID: messageID,
                            userId: userId,
                            emoji: emoji
                        )
                    }
                }
            } else {
                UnicodeEmojiPickerSheet { _ in chatReactionPickerMessageID = nil }
            }
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

    private func scrollToLatestMessage(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = coordinator.chatMessages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

/// Message field + send (viewer + OBS manage stream).
struct RoomBroadcastChatComposer: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    let userId: String?
    let displayName: String
    let imagePipeline: any ImagePipeline
    @Binding var chatDraft: String
    @Binding var replyTarget: BroadcastChatMessageItem?
    var useViewerKeyboardChrome: Bool = false
    @FocusState.Binding var composerFocus: Bool

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var keyboardSendScheduled = false
    @State private var isSendingChat = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsTradePicker = false
    @State private var tradePickerTrades: [Trade] = []
    @State private var isLoadingTradePicker = false

    var body: some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            if let error = coordinator.broadcastChatComposerError {
                composerErrorBanner(error)
            }
            HStack(alignment: .bottom, spacing: ExperienceSpacing.xxs) {
                if userId != nil {
                    attachmentLauncher
                }

                composerTextField
                    .frame(maxWidth: .infinity, alignment: .leading)

                if canSendChat {
                    sendButton
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.xs)
        .padding(.vertical, ExperienceSpacing.xs)
        .background(colors.navigationBackground.opacity(0.96))
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $photoItem,
            matching: MediaPickerPolicy.imageOnly.matching
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPickedPhoto(item) }
            photoItem = nil
        }
        .sheet(isPresented: $showsTradePicker) {
            TradeSharePickerSheet(
                trades: tradePickerTrades,
                imagePipeline: imagePipeline,
                isLoading: isLoadingTradePicker,
                onSelect: { trade in
                    showsTradePicker = false
                    Task { await sendTrade(trade) }
                },
                onClose: { showsTradePicker = false }
            )
            .task { await loadTradePickerIfNeeded() }
        }
        .experienceFormFocusSync($composerFocus)
    }

    private var attachmentLauncher: some View {
        Menu {
            Button {
                presentPhotoPicker()
            } label: {
                Label("Photo", systemImage: "photo")
            }
            .accessibilityIdentifier("tradeRooms.broadcast.chat.photo")

            Button {
                presentTradePicker()
            } label: {
                Label("Send Trade", systemImage: "chart.line.uptrend.xyaxis")
            }
            .accessibilityIdentifier("tradeRooms.broadcast.chat.trade")
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 28, height: 28)
                .background(colors.fillSecondary, in: Circle())
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
                .experienceControlHitTarget()
        }
        .menuStyle(.button)
        .buttonStyle(.experiencePlain)
        .fixedSize(horizontal: true, vertical: true)
        .disabled(isSendingChat)
        .accessibilityLabel("Add attachment")
        .accessibilityIdentifier("tradeRooms.broadcast.chat.add")
    }

    private var composerTextField: some View {
        TextField("Message…", text: $chatDraft, axis: .vertical)
            .lineLimit(1 ... 4)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.sentences)
            .focused($composerFocus)
            .disabled(userId == nil)
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
            .experienceKeyboardExcludesDoneToolbarWhenFocused(composerFocus)
    }

    private var sendButton: some View {
        Button(action: sendChat) {
            Group {
                if isSendingChat {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(colors.accent)
                }
            }
            .experienceTouchTarget()
        }
        .buttonStyle(.experiencePlain)
        .disabled(isSendingChat)
        .accessibilityLabel("Send")
        .accessibilityIdentifier("tradeRooms.broadcast.chat.send")
    }

    private var canSendChat: Bool {
        guard userId != nil else { return false }
        return !chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func presentPhotoPicker() {
        ExperienceHaptics.play(.selection)
        showsPhotoPicker = true
    }

    private func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    private func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker else { return }
        guard let userId else { return }
        let viewerID = ProfileID(userId)
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if MessagesInboxSupport.isLocalDevelopmentProfile(viewerID) {
            tradePickerTrades = BroadcastChatAttachmentPolicy.eligibleTradesForSharing(
                TradeShareFixtures.sampleTrades(ownerID: viewerID)
            )
            return
        }
        do {
            let page = try await appEnvironment.data.trades.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            tradePickerTrades = BroadcastChatAttachmentPolicy.eligibleTradesForSharing(page.items)
        } catch {
            tradePickerTrades = []
        }
    }

    private func sendPickedPhoto(_ item: PhotosPickerItem) async {
        guard let userId else { return }
        guard !isSendingChat else { return }
        isSendingChat = true
        defer { isSendingChat = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            coordinator.setBroadcastChatComposerError("Couldn't read that photo.")
            return
        }
        guard let image = UIImage(data: data) else {
            coordinator.setBroadcastChatComposerError("Couldn't use that photo.")
            return
        }
        guard let jpeg = MediaImagePreparation.chatJPEGData(from: image) else {
            coordinator.setBroadcastChatComposerError("Couldn't prepare that photo for chat.")
            return
        }
        do {
            let path = StorageOptimizedMedia.objectPath(prefix: userId, fileExtension: "jpg")
            let rawURL = try await OptimisticOutboundImageSendSupport.uploadJPEG(
                localImageData: jpeg,
                storagePath: path,
                uploadService: appEnvironment.data.uploadService,
                objectStorage: appEnvironment.data.objectStorage
            )
            guard let imageURL = BroadcastChatAttachmentPolicy.resolvedAllowedBroadcastImageURL(
                rawURL,
                objectStorage: appEnvironment.data.objectStorage
            ) else {
                coordinator.setBroadcastChatComposerError(
                    "Photo uploaded but couldn't get a valid HTTPS link for livestream chat."
                )
                return
            }
            let caption = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let reply = replyTarget.map(replyReference(for:))
            let result = await coordinator.sendChat(
                userId: userId,
                displayName: displayName,
                avatarUrl: nil,
                text: caption,
                imageURL: imageURL,
                replyTo: reply
            )
            switch result {
            case .sent:
                chatDraft = ""
                replyTarget = nil
                retainComposerFocusAfterSend()
            case .failed(let message):
                coordinator.setBroadcastChatComposerError(message)
            }
        } catch {
            coordinator.setBroadcastChatComposerError("Could not upload photo.")
        }
    }

    private func sendTrade(_ trade: Trade) async {
        guard let userId else { return }
        guard !isSendingChat else { return }
        isSendingChat = true
        defer { isSendingChat = false }
        coordinator.stageSharedTradeForChat(trade)
        let caption = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = replyTarget.map(replyReference(for:))
        let result = await coordinator.sendChat(
            userId: userId,
            displayName: displayName,
            avatarUrl: nil,
            text: caption,
            tradeID: trade.id,
            replyTo: reply
        )
        switch result {
        case .sent:
            chatDraft = ""
            replyTarget = nil
            retainComposerFocusAfterSend()
        case .failed(let message):
            coordinator.setBroadcastChatComposerError(message)
        }
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
            let result = await coordinator.sendChat(
                userId: userId,
                displayName: displayName,
                avatarUrl: nil,
                text: trimmed,
                replyTo: reply
            )
            isSendingChat = false
            switch result {
            case .sent:
                retainComposerFocusAfterSend()
            case .failed(let message):
                coordinator.setBroadcastChatComposerError(message)
            }
        }
    }

    private func composerErrorBanner(_ message: String) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(colors.error)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button("OK") {
                coordinator.acknowledgeBroadcastChatComposerError()
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, ExperienceSpacing.xxs)
        .accessibilityIdentifier("tradeRooms.broadcast.chat.composerError")
    }

    private func retainComposerFocusAfterSend() {
        guard useViewerKeyboardChrome else { return }
        composerFocus = true
    }
}