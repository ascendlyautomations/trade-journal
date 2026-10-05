import Foundation

#if DEBUG
/// Narrow shared-message hydration tracing (Trade Room / DM cards).
enum SharedContentTrace {
    static func messageEncountered(
        message: Message,
        sharedPosts: [PostID: Post],
        sharedTrades: [TradeID: Trade],
        includedInTradeBatch: Bool,
        dropReason: String?
    ) {
        let tradeIDs = SharedContentMessageSupport.referencedTradeIDs(
            for: message,
            sharedPosts: sharedPosts
        )
        let primaryTradeID = tradeIDs.first?.rawValue ?? "nil"
        let sharedType = message.sharedContent.map { String(describing: $0) } ?? "nil"
        let snapshotAvailable = tradeIDs.contains { sharedTrades[$0] != nil }
        var line =
            "[SharedContentTrace] messageID=\(message.id.rawValue) kind=\(message.kind.rawValue) sharedContentType=\(sharedType) tradeIDs=\(tradeIDs.map(\.rawValue).joined(separator: ",")) primaryTradeID=\(primaryTradeID) snapshotAvailable=\(snapshotAvailable) requiresHydration=\(!tradeIDs.isEmpty && !tradeIDs.allSatisfy { sharedTrades[$0] != nil }) includedInTradeBatch=\(includedInTradeBatch)"
        if let dropReason, !dropReason.isEmpty {
            line += " dropReason=\(dropReason)"
        }
        print(line)
    }

    static func hydrateTradeBatch(tradeIDs: [TradeID]) {
        let ids = tradeIDs.map(\.rawValue).joined(separator: ",")
        print("[SharedContentTrace] hydrateTradeBatch tradeCount=\(tradeIDs.count) tradeIDs=[\(ids)]")
    }

    static func cardRender(messageID: MessageID, tradeID: TradeID, tradeLoaded: Bool) {
        let state = tradeLoaded ? "hydrated" : "loading"
        print(
            "[SharedContentTrace] cardRender messageID=\(messageID.rawValue) tradeID=\(tradeID.rawValue) renderState=\(state) reason=\(tradeLoaded ? "tradeNonNil" : "awaitingHydration")"
        )
    }
}
#endif
