import Foundation

enum ConversationSharedMediaItemKind: String, Equatable, Sendable {
    case image
    case sharedTrade
}

@MainActor
struct ConversationSharedMediaTradeBridge {
    var messageForID: (MessageID) -> Message?
    var tradeForMessage: (Message) -> Trade?
    var tradeForID: (TradeID) -> Trade?
    var hydrateMessageIDs: ([MessageID]) async -> Void

    static let inactive = ConversationSharedMediaTradeBridge(
        messageForID: { _ in nil },
        tradeForMessage: { _ in nil },
        tradeForID: { _ in nil },
        hydrateMessageIDs: { _ in }
    )
}

@MainActor
enum ConversationSharedMediaTradeEnrichment {
    static func isSharedTradeMediaMessage(_ message: Message) -> Bool {
        if message.kind == .tradeShare { return true }
        if message.attachments.first?.tradeID != nil { return true }
        if case .trade = message.sharedContent { return true }
        return false
    }

    static func applyTradeMetadata(
        to item: inout ConversationSharedMediaItem,
        message: Message,
        bridge: ConversationSharedMediaTradeBridge
    ) {
        guard isSharedTradeMediaMessage(message) else {
            item.kind = .image
            item.tradeID = nil
            item.tradeTotalPnL = nil
            return
        }
        guard let tradeID = SharedContentMessageSupport.primaryTradeID(for: message) else {
            item.kind = .image
            item.tradeID = nil
            item.tradeTotalPnL = nil
            return
        }
        item.kind = .sharedTrade
        item.tradeID = tradeID
        if let trade = bridge.tradeForMessage(message) ?? bridge.tradeForID(tradeID) {
            item.tradeTotalPnL = trade.realizedPnL
        } else {
            item.tradeTotalPnL = nil
        }
    }

    static func enrichItems(
        _ items: [ConversationSharedMediaItem],
        bridge: ConversationSharedMediaTradeBridge
    ) async -> [ConversationSharedMediaItem] {
        var output = items
        var pendingHydrate: [MessageID] = []

        for index in output.indices {
            guard let message = bridge.messageForID(output[index].id) else {
                if output[index].kind == .sharedTrade || output[index].tradeID != nil {
                    pendingHydrate.append(output[index].id)
                }
                continue
            }
            applyTradeMetadata(to: &output[index], message: message, bridge: bridge)
            if output[index].kind == .sharedTrade, output[index].tradeTotalPnL == nil {
                pendingHydrate.append(output[index].id)
            }
        }

        guard !pendingHydrate.isEmpty else { return output }
        await bridge.hydrateMessageIDs(Array(Set(pendingHydrate)))

        for index in output.indices {
            guard let message = bridge.messageForID(output[index].id) else { continue }
            applyTradeMetadata(to: &output[index], message: message, bridge: bridge)
        }
        return output
    }
}