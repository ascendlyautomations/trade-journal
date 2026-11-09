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

    private(set) var phase: Phase = .idle
    private(set) var items: [ConversationSharedMediaItem] = []
    private(set) var hasMore = true
    private(set) var isLoadingMore = false
    private(set) var thumbnailFailedIDs: Set<MessageID> = []

    var selectedItem: ConversationSharedMediaItem?

    private var firstPageLoadGeneration: UInt64 = 0
    private var loadMoreGeneration: UInt64 = 0
    private(set) var openCount = 0

    init(conversationID: ConversationID, rpc: (any RPCClient)?) {
        self.conversationID = conversationID
        self.rpc = rpc
    }

    var visibleItems: [ConversationSharedMediaItem] {
        items
    }

    func isThumbnailFailed(_ item: ConversationSharedMediaItem) -> Bool {
        thumbnailFailedIDs.contains(item.id)
    }

    func open() async {
        openCount += 1
        if let cached = await ConversationSharedMediaSessionCache.shared.snapshot(conversationID: conversationID) {
            items = cached.items
            hasMore = cached.hasMore
            phase = items.isEmpty ? .empty : .loaded
        } else if items.isEmpty {
            hasMore = true
            phase = .loading
        }
        thumbnailFailedIDs = []
        selectedItem = nil
        await refreshFirstPage(background: phase != .loading)
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
            items = ConversationSharedMediaPagination.merged(existing: items, page: page)
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
                phase = .loaded
                await persistCache()
                return
            }
            items = page
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
}
