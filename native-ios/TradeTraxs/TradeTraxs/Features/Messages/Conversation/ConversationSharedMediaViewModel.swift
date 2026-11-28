import Foundation
import Observation

@Observable
@MainActor
final class ConversationSharedMediaViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    let conversationID: ConversationID
    private let rpc: (any RPCClient)?
    private let messagesRepo: (any MessageRepository)?
    var tradeBridge: ConversationSharedMediaTradeBridge = .inactive

    private(set) var phase: Phase = .idle
    private(set) var items: [ConversationSharedMediaItem] = []
    private(set) var hasMore = true
    private(set) var isLoadingMore = false
    private(set) var thumbnailFailedIDs: Set<MessageID> = []

    var selectedItem: ConversationSharedMediaItem?

    private var firstPageLoadGeneration: UInt64 = 0
    private var loadMoreGeneration: UInt64 = 0
    private(set) var openCount = 0
    private var messageLookupCache: [MessageID: Message] = [:]

    init(
        conversationID: ConversationID,
        rpc: (any RPCClient)?,
        messagesRepo: (any MessageRepository)? = nil
    ) {
        self.conversationID = conversationID
        self.rpc = rpc
        self.messagesRepo = messagesRepo
    }

    var visibleItems: [ConversationSharedMediaItem] {
        items
    }

    func isThumbnailFailed(_ item: ConversationSharedMediaItem) -> Bool {
        thumbnailFailedIDs.contains(item.id)
    }

    func open() async {
        openCount += 1
        thumbnailFailedIDs = []
        selectedItem = nil

        switch phase {
        case .loading:
            return
        case .loaded, .empty:
            await refreshFirstPage(background: true)
            return
        case .failed:
            phase = .loading
            await refreshFirstPage(background: false)
            return
        case .idle:
            phase = .loading
        }

        if let cached = await ConversationSharedMediaSessionCache.shared.snapshot(conversationID: conversationID) {
            items = await enrichAndResolveMessages(cached.items)
            hasMore = cached.hasMore
            if items.isEmpty {
                await refreshFirstPage(background: false)
            } else {
                phase = .loaded
                await refreshFirstPage(background: true)
            }
            return
        }

        hasMore = true
        await refreshFirstPage(background: false)
    }

    func retry() async {
        phase = .loading
        await refreshFirstPage(background: false)
    }

    func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore, phase == .loaded || phase == .empty else { return }
        guard let rpc else {
            phase = .failed("Couldn't load shared media.")
            return
        }
        loadMoreGeneration += 1
        let generation = loadMoreGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        let cursor = ConversationSharedMediaPagination.nextCursor(from: items)
        let result = await ConversationSharedMediaFetcher.fetch(
            conversationID: conversationID,
            cursor: cursor,
            rpc: rpc
        )
        guard generation == loadMoreGeneration else { return }
        switch result {
        case .success(let page):
            let merged = ConversationSharedMediaPagination.merged(existing: items, page: page)
            items = await enrichAndResolveMessages(merged)
            hasMore = page.count == ConversationSharedMediaSupport.pageSize
            phase = items.isEmpty ? .empty : .loaded
            await persistCache()
        case .failure:
            break
        }
    }

    func markThumbnailFailed(_ item: ConversationSharedMediaItem) {
        thumbnailFailedIDs.insert(item.id)
    }

    private func refreshFirstPage(background: Bool) async {
        guard let rpc else {
            phase = .failed("Couldn't load shared media.")
            return
        }
        firstPageLoadGeneration += 1
        let generation = firstPageLoadGeneration
        if !background {
            phase = .loading
        }
        let result = await ConversationSharedMediaFetcher.fetch(
            conversationID: conversationID,
            cursor: nil,
            rpc: rpc
        )
        guard generation == firstPageLoadGeneration else { return }
        switch result {
        case .success(let page):
            if page.isEmpty, !items.isEmpty {
                items = await enrichAndResolveMessages(items)
                phase = .loaded
                await persistCache()
                return
            }
            items = await enrichAndResolveMessages(page)
            hasMore = page.count == ConversationSharedMediaSupport.pageSize
            phase = items.isEmpty ? .empty : .loaded
            await persistCache()
        case .failure(let message):
            if items.isEmpty {
                phase = .failed(message)
            } else {
                phase = .loaded
            }
        }
    }

    private func persistCache() async {
        await ConversationSharedMediaSessionCache.shared.replace(
            conversationID: conversationID,
            items: items,
            hasMore: hasMore
        )
    }

    func previewTrade(for item: ConversationSharedMediaItem) -> Trade? {
        guard let tradeID = item.tradeID else { return nil }
        if let message = resolvedMessage(for: item.id),
           let trade = tradeBridge.tradeForMessage(message)
        {
            return trade
        }
        return tradeBridge.tradeForID(tradeID)
    }

    private func enrichAndResolveMessages(_ page: [ConversationSharedMediaItem]) async -> [ConversationSharedMediaItem] {
        await resolveMissingMessages(for: page.map(\.id))
        let enrichmentBridge = ConversationSharedMediaTradeBridge(
            messageForID: { [self] id in resolvedMessage(for: id) },
            tradeForMessage: tradeBridge.tradeForMessage,
            tradeForID: tradeBridge.tradeForID,
            hydrateMessageIDs: tradeBridge.hydrateMessageIDs
        )
        return await ConversationSharedMediaTradeEnrichment.enrichItems(page, bridge: enrichmentBridge)
    }

    private func resolvedMessage(for messageID: MessageID) -> Message? {
        messageLookupCache[messageID] ?? tradeBridge.messageForID(messageID)
    }

    private func resolveMissingMessages(for messageIDs: [MessageID]) async {
        guard let messagesRepo else { return }
        for messageID in messageIDs {
            if resolvedMessage(for: messageID) != nil { continue }
            guard let fetched = try? await messagesRepo.message(id: messageID, in: conversationID) else {
                continue
            }
            messageLookupCache[messageID] = fetched
        }
        let tradeMessageIDs = messageIDs.compactMap { id -> MessageID? in
            guard let message = resolvedMessage(for: id) else { return nil }
            return ConversationSharedMediaTradeEnrichment.isSharedTradeMediaMessage(message) ? id : nil
        }
        guard !tradeMessageIDs.isEmpty else { return }
        await tradeBridge.hydrateMessageIDs(Array(Set(tradeMessageIDs)))
    }
}

