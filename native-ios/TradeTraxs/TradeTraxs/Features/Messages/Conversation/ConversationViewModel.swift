import Foundation
import Observation
import OSLog
import UIKit

@Observable
@MainActor
final class ConversationViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let conversationID: ConversationID

    private(set) var phase: Phase = .idle
    private(set) var conversation: Conversation?
    private(set) var messages: [Message] = []
    private(set) var sendStates: [MessageID: ConversationBubbleItem.SendState] = [:]
    private(set) var isLoadingOlder = false
    private(set) var hasMoreOlder = true
    private(set) var viewerID: ProfileID?
    private(set) var peerProfile: Profile?
    private(set) var title: String = "Conversation"
    private(set) var subtitle: String?
    var draft = ""
    var isSending = false
    var showsTradePicker = false
    private(set) var tradePickerTrades: [Trade] = []
    private(set) var isLoadingTradePicker = false
    private(set) var sharedTrades: [TradeID: Trade] = [:]

    private let messagesRepo: any MessageRepository
    private let profiles: any ProfileRepository
    private let notifications: (any NotificationRepository)?
    private let tradesRepo: (any TradeRepository)?
    private let session: any SessionProviding
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let detailCache: DetailPresentationCache
    private let inboxStore: MessagesInboxStore
    private let realtimeHub: RealtimeHub?

    private var nextOlderCursor: String?
    private var realtimeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var isApplyingRealtime = false
    private var didMarkReadThisOpen = false

    init(
        conversationID: ConversationID,
        messages: any MessageRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        detailCache: DetailPresentationCache,
        trades: (any TradeRepository)? = nil,
        notifications: (any NotificationRepository)? = nil,
        realtimeHub: RealtimeHub? = nil,
        inboxStore: MessagesInboxStore? = nil
    ) {
        self.conversationID = conversationID
        self.messagesRepo = messages
        self.profiles = profiles
        self.notifications = notifications
        self.tradesRepo = trades
        self.session = session
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.inboxStore = inboxStore ?? .shared
    }

    var timeline: [ConversationTimelineItem] {
        buildTimeline(from: messages)
    }

    var showsEmpty: Bool {
        phase == .loaded && messages.isEmpty
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded else { return }
        loadTask = Task { await performInitialLoad() }
    }

    func retryLoad() {
        guard loadTask == nil else { return }
        phase = .idle
        loadTask = Task { await performInitialLoad() }
    }

    func refreshNewest() async {
        await fetchIncrementalUpdates()
    }

    func loadOlderIfNeeded() async {
        guard hasMoreOlder, !isLoadingOlder, phase == .loaded else { return }
        guard let viewerID, !ConversationThreadSupport.isLocalDevelopment(viewerID) else {
            hasMoreOlder = false
            return
        }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            var page = PageRequest(limit: 40)
            page.cursor = nextOlderCursor
            let result = try await messagesRepo.messages(in: conversationID, page: page)
            // Repo returns newest-first; older page is older than current oldest.
            let chronological = result.items.sorted { $0.createdAt < $1.createdAt }
            let existing = Set(messages.map(\.id))
            let fresh = chronological.filter { !existing.contains($0.id) }
            messages = (fresh + messages).sorted { $0.createdAt < $1.createdAt }
            nextOlderCursor = result.nextCursor
            hasMoreOlder = result.nextCursor != nil
        } catch {
            // Soft-fail older page.
        }
    }

    func startRealtime() {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            // Register topic + join web-equivalent messages postgres_changes. Remain idle — no polling.
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.subscribe(channel)
            let token = await session.accessToken
            guard let realtimeHub else { return }
            for await signal in realtimeHub.watchConversationMessages(
                conversationID: conversationID,
                accessToken: token
            ) {
                guard !Task.isCancelled else { break }
                await applyRealtimeSignal(signal)
            }
        }
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        Task { [conversationID, realtimeHub] in
            let channel = RealtimeChannelID(
                kind: .conversation,
                topic: conversationID.rawValue
            )
            try? await realtimeHub?.subscriptions.unsubscribe(channel)
            await realtimeHub?.stopWatchingConversationMessages(conversationID: conversationID)
        }
    }

    func sendText() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        await send(body: text, imageURL: nil, localImageData: nil)
    }

    func sendImage(_ image: UIImage) async {
        guard !isSending else { return }
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        await send(body: draft.trimmingCharacters(in: .whitespacesAndNewlines), imageURL: nil, localImageData: data)
        draft = ""
    }

    func presentTradePicker() {
        ExperienceHaptics.play(.selection)
        showsTradePicker = true
    }

    func loadTradePickerIfNeeded() async {
        guard tradePickerTrades.isEmpty, !isLoadingTradePicker else { return }
        guard let viewerID, let tradesRepo else { return }
        isLoadingTradePicker = true
        defer { isLoadingTradePicker = false }
        if ConversationThreadSupport.isLocalDevelopment(viewerID) {
            tradePickerTrades = TradeShareFixtures.sampleTrades(ownerID: viewerID)
            return
        }
        do {
            let page = try await tradesRepo.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 40),
                publicOnly: false
            )
            tradePickerTrades = page.items
        } catch {
            tradePickerTrades = []
        }
    }

    func sendTrade(_ trade: Trade) async {
        guard let viewerID, !isSending else { return }
        showsTradePicker = false
        sharedTrades[trade.id] = trade
        isSending = true
        defer { isSending = false }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: .tradeShare,
            body: nil,
            attachments: [
                MessageAttachment(
                    id: trade.id.rawValue,
                    media: MediaReference(id: trade.id.rawValue, kind: .file, altText: "Shared trade"),
                    tradeID: trade.id
                ),
            ],
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        messages.append(optimistic)
        sendStates[tempID] = .sending

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            patchInbox(with: optimistic)
            return
        }

        do {
            let saved = try await messagesRepo.send(optimistic)
            messages.removeAll { $0.id == tempID }
            sendStates.removeValue(forKey: tempID)
            if !messages.contains(where: { $0.id == saved.id }) {
                messages.append(saved)
                messages.sort { $0.createdAt < $1.createdAt }
            }
            sendStates[saved.id] = .sent
            sharedTrades[trade.id] = trade
            patchInbox(with: saved)
            ExperienceHaptics.play(.selection)
        } catch {
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.warning)
        }
    }

    func sharedTrade(for message: Message) -> Trade? {
        guard let tradeID = message.attachments.first?.tradeID else { return nil }
        return sharedTrades[tradeID]
    }

    func retry(_ item: ConversationBubbleItem) async {
        guard sendStates[item.id] == .failed else { return }
        messages.removeAll { $0.id == item.id }
        sendStates.removeValue(forKey: item.id)
        let imageURL = item.imageReference?.id
        await send(body: item.text ?? "", imageURL: imageURL, localImageData: nil)
    }

    // MARK: - Private

    private func performInitialLoad() async {
        phase = .loading
        // Web optimistic clear on open — badge drops before history finishes loading.
        inboxStore.markRead(conversationID: conversationID)

        let current = await session.currentUserID
        let viewer = current.map { ProfileID($0.rawValue) }
        viewerID = viewer

        do {
            if let viewer,
               ConversationThreadSupport.isLocalDevelopment(viewer)
                || ConversationThreadSupport.isLocalConversation(conversationID)
            {
                await loadLocalFixtures(viewerID: viewer)
            } else {
                try await loadFromRepository()
            }
            await markConversationSeenIfNeeded()
            phase = .loaded
            startRealtime()
        } catch {
            // Still persist read intent when the thread fails to load (web open path).
            await markConversationSeenIfNeeded()
            phase = .failed(ConversationThreadSupport.message(for: error))
        }
        loadTask = nil
    }

    /// Web `markConversationMessagesSeen` + `markMessageNotificationsRead` on conversation open.
    private func markConversationSeenIfNeeded() async {
        inboxStore.markRead(conversationID: conversationID)
        guard !didMarkReadThisOpen else { return }
        didMarkReadThisOpen = true

        guard let viewerID,
              !ConversationThreadSupport.isLocalDevelopment(viewerID),
              !ConversationThreadSupport.isLocalConversation(conversationID)
        else { return }

        try? await messagesRepo.markRead(conversationID: conversationID)
        await markMessageNotificationsRead()
        // Keep local badge cleared even if a concurrent inbox patch raced in.
        inboxStore.markRead(conversationID: conversationID)
    }

    /// Web `messages/[id]` marks all unread `type=message` Activity rows on open.
    private func markMessageNotificationsRead() async {
        guard let notifications else { return }
        guard let page = try? await notifications.notifications(page: PageRequest(limit: 100)) else {
            return
        }
        for item in page.items where !item.isRead && item.kind == .message {
            try? await notifications.markRead(id: item.id)
        }
    }

    private func loadLocalFixtures(viewerID: ProfileID) async {
        if let cached = inboxStore.conversations.first(where: { $0.id == conversationID }) {
            conversation = cached
        } else {
            conversation = Conversation(
                id: conversationID,
                participantProfileIDs: [viewerID],
                title: "Conversation",
                peerUsername: nil,
                avatar: nil,
                isGroup: false,
                isPinned: false,
                lastMessagePreview: nil,
                lastMessageAt: nil,
                unreadCount: 0,
                isMuted: false,
                updatedAt: .now
            )
        }
        let peerID = MessagesInboxSupport.peerID(in: conversation!, viewerID: viewerID)
            ?? ProfileID("dev.follower.ada")
        if let profile = FollowListFixtures.profile(id: peerID) ?? detailCache.profile(id: peerID) {
            peerProfile = profile
            detailCache.seed(profile)
        }
        applyHeader(from: conversation)
        messages = ConversationThreadFixtures.messages(
            conversationID: conversationID,
            viewerID: viewerID,
            peerID: peerID
        )
        hasMoreOlder = false
    }

    private func loadFromRepository() async throws {
        let meta = try await messagesRepo.conversation(id: conversationID)
        conversation = meta
        if let viewerID {
            let peerID = MessagesInboxSupport.peerID(in: meta, viewerID: viewerID)
            if let peerID {
                if let cached = detailCache.profile(id: peerID) {
                    peerProfile = cached
                } else if let fetched = try? await profiles.profile(id: peerID) {
                    detailCache.seed(fetched)
                    peerProfile = fetched
                }
            }
        }
        applyHeader(from: meta)
        let page = try await messagesRepo.messages(
            in: conversationID,
            page: PageRequest(limit: 50)
        )
        messages = page.items.sorted { $0.createdAt < $1.createdAt }
        nextOlderCursor = page.nextCursor
        hasMoreOlder = page.nextCursor != nil
        await hydrateSharedTrades(from: messages)
    }

    /// Pull-to-refresh / explicit refresh — not used on a timer.
    private func fetchIncrementalUpdates() async {
        await applyRealtimeSignal(MessageRealtimeSignal(kind: .insert, messageID: nil))
    }

    /// Incremental apply from Realtime — never reloads the whole conversation.
    private func applyRealtimeSignal(_ signal: MessageRealtimeSignal) async {
        guard let viewerID,
              !ConversationThreadSupport.isLocalDevelopment(viewerID),
              !ConversationThreadSupport.isLocalConversation(conversationID),
              !isApplyingRealtime
        else { return }

        if signal.kind == .delete, let rawID = signal.messageID {
            let id = MessageID(rawID)
            messages.removeAll { $0.id == id }
            return
        }

        isApplyingRealtime = true
        defer { isApplyingRealtime = false }
        do {
            let page = try await messagesRepo.messages(
                in: conversationID,
                page: PageRequest(limit: 30)
            )
            let existing = Set(messages.map(\.id))
            let incoming = page.items
                .filter { !existing.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }

            if signal.kind == .update, let rawID = signal.messageID {
                let id = MessageID(rawID)
                if let updated = page.items.first(where: { $0.id == id }),
                   let index = messages.firstIndex(where: { $0.id == id })
                {
                    messages[index] = updated
                    await hydrateSharedTrades(from: [updated])
                    return
                }
            }

            guard !incoming.isEmpty else { return }
            messages.append(contentsOf: incoming)
            messages.sort { $0.createdAt < $1.createdAt }
            await hydrateSharedTrades(from: incoming)
            if let last = messages.last {
                patchInbox(with: last)
            }
        } catch {
            // Soft-fail event-driven hydrate.
        }
    }

    private func hydrateSharedTrades(from messages: [Message]) async {
        guard let tradesRepo else { return }
        let ids = Set(messages.compactMap { $0.attachments.first?.tradeID })
        for id in ids where sharedTrades[id] == nil {
            if let trade = try? await tradesRepo.trade(id: id) {
                sharedTrades[id] = trade
            }
        }
    }

    private func send(body: String, imageURL: String?, localImageData: Data?) async {
        guard let viewerID else { return }
        isSending = true
        defer { isSending = false }

        let tempID = MessageID("temp-\(UUID().uuidString)")
        var attachments: [MessageAttachment] = []
        if let imageURL {
            attachments = [
                MessageAttachment(
                    id: imageURL,
                    media: MediaReference(id: imageURL, kind: .image, altText: nil),
                    tradeID: nil
                ),
            ]
        }

        let optimistic = Message(
            id: tempID,
            conversationID: conversationID,
            senderProfileID: viewerID,
            kind: attachments.isEmpty ? .text : .media,
            body: body.isEmpty ? nil : body,
            attachments: attachments,
            replyToMessageID: nil,
            createdAt: .now,
            isReadByViewer: true
        )
        messages.append(optimistic)
        sendStates[tempID] = .sending

        if ConversationThreadSupport.isLocalDevelopment(viewerID)
            || ConversationThreadSupport.isLocalConversation(conversationID)
        {
            sendStates[tempID] = .sent
            patchInbox(with: optimistic)
            return
        }

        do {
            var resolvedImageURL = imageURL
            if let localImageData {
                let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                let reference = try await uploadService.upload(
                    UploadRequest(
                        bucket: StorageBucket.screenshots.rawValue,
                        path: path,
                        data: localImageData,
                        contentType: "image/jpeg",
                        purpose: .tradeScreenshot
                    )
                )
                if let publicURL = objectStorage.publicURL(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: reference.id
                ) {
                    resolvedImageURL = publicURL.absoluteString
                } else {
                    resolvedImageURL = reference.id
                }
                if let index = messages.firstIndex(where: { $0.id == tempID }),
                   let url = resolvedImageURL
                {
                    messages[index].attachments = [
                        MessageAttachment(
                            id: url,
                            media: MediaReference(id: url, kind: .image, altText: nil),
                            tradeID: nil
                        ),
                    ]
                    messages[index].kind = .media
                }
            }

            let payload = Message(
                id: tempID,
                conversationID: conversationID,
                senderProfileID: viewerID,
                kind: resolvedImageURL == nil ? .text : .media,
                body: body.isEmpty ? "" : body,
                attachments: resolvedImageURL.map {
                    [
                        MessageAttachment(
                            id: $0,
                            media: MediaReference(id: $0, kind: .image, altText: nil),
                            tradeID: nil
                        ),
                    ]
                } ?? [],
                replyToMessageID: nil,
                createdAt: .now,
                isReadByViewer: true
            )
            AppLog.networking.info(
                """
                conversation.send invoking MessageRepository.send \
                conversation=\(self.conversationID.rawValue, privacy: .public) \
                sender=\(viewerID.rawValue, privacy: .public) \
                bodyChars=\(body.count, privacy: .public) \
                hasImage=\(resolvedImageURL != nil, privacy: .public)
                """
            )
            let saved = try await messagesRepo.send(payload)
            messages.removeAll { $0.id == tempID }
            sendStates.removeValue(forKey: tempID)
            if !messages.contains(where: { $0.id == saved.id }) {
                messages.append(saved)
                messages.sort { $0.createdAt < $1.createdAt }
            }
            sendStates[saved.id] = .sent
            patchInbox(with: saved)
            ExperienceHaptics.play(.selection)
        } catch {
            AppLog.networking.error(
                """
                conversation.send failed \
                conversation=\(self.conversationID.rawValue, privacy: .public) \
                sender=\(viewerID.rawValue, privacy: .public) \
                error=\(String(describing: error), privacy: .public)
                """
            )
            sendStates[tempID] = .failed
            ExperienceHaptics.play(.warning)
        }
    }

    private func applyHeader(from conversation: Conversation?) {
        guard let conversation else { return }
        if conversation.isGroup {
            title = conversation.title ?? "Group Chat"
            subtitle = nil
        } else {
            title = conversation.title
                ?? peerProfile?.displayName
                ?? conversation.peerUsername
                ?? "Conversation"
            if let username = conversation.peerUsername ?? peerProfile?.username {
                subtitle = "@\(username)"
            }
        }
    }

    private func patchInbox(with message: Message) {
        guard var convo = inboxStore.conversations.first(where: { $0.id == conversationID })
            ?? conversation
        else { return }
        let preview: String
        if message.attachments.isEmpty {
            preview = message.body ?? ""
        } else if let body = message.body, !body.isEmpty {
            preview = body
        } else {
            preview = "Photo"
        }
        convo.lastMessagePreview = preview
        convo.lastMessageAt = message.createdAt
        convo.updatedAt = message.createdAt
        convo.unreadCount = 0
        inboxStore.upsertConversation(convo)
        conversation = convo
    }

    private func buildTimeline(from messages: [Message]) -> [ConversationTimelineItem] {
        var items: [ConversationTimelineItem] = []
        let calendar = Calendar.current
        var lastDay: DateComponents?
        for (index, message) in messages.enumerated() {
            let day = calendar.dateComponents([.year, .month, .day], from: message.createdAt)
            if day != lastDay {
                let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                items.append(
                    .daySeparator(
                        id: key,
                        title: ConversationThreadSupport.daySeparator(message.createdAt)
                    )
                )
                lastDay = day
            }
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let isOutgoing = message.senderProfileID == viewerID
            let showsAvatar = !isOutgoing && (
                previous?.senderProfileID != message.senderProfileID
                    || previous.map { abs($0.createdAt.timeIntervalSince(message.createdAt)) > 300 } ?? true
            )
            let showsTimestamp = next?.senderProfileID != message.senderProfileID
                || next.map { abs($0.createdAt.timeIntervalSince(message.createdAt)) > 300 } ?? true
            items.append(
                .message(
                    ConversationBubbleItem(
                        id: message.id,
                        message: message,
                        isOutgoing: isOutgoing,
                        showsAvatar: showsAvatar,
                        showsTimestamp: showsTimestamp,
                        sendState: sendStates[message.id] ?? .sent
                    )
                )
            )
        }
        return items
    }
}
