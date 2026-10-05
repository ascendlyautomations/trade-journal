import Foundation

/// Temporary device diagnostics — Profile Trades journal hydration (no private fields).
enum ProfileTradesHydrationDiagnostics {
    enum Source: String, Sendable {
        case bootstrap
        case v1
        case v2
        case repository
    }

    #if DEBUG
    static func logHydration(source: Source, count: Int, journalCount: Int) {
        print("[ProfileTradesHydration] source=\(source.rawValue) count=\(count) journalCount=\(journalCount)")
    }

    static func logV2Request(requested: Bool, reason: String) {
        print("[ProfileTradesHydration] v2Requested=\(requested) reason=\(reason)")
    }

    static func logPerformLoadStart(reset: Bool, journalCount: Int) {
        print("[ProfileTradesHydration] performLoadStart reset=\(reset) journalCount=\(journalCount)")
    }

    static func logPerformLoadFinished(usedV2: Bool, pageCount: Int, journalCount: Int, error: String?) {
        if let error {
            print(
                "[ProfileTradesHydration] performLoadFinished usedV2=\(usedV2) pageCount=\(pageCount) journalCount=\(journalCount) error=\(error)"
            )
        } else {
            print(
                "[ProfileTradesHydration] performLoadFinished usedV2=\(usedV2) pageCount=\(pageCount) journalCount=\(journalCount)"
            )
        }
    }
    #else
    static func logHydration(source: Source, count: Int, journalCount: Int) {}
    static func logV2Request(requested: Bool, reason: String) {}
    static func logPerformLoadStart(reset: Bool, journalCount: Int) {}
    static func logPerformLoadFinished(usedV2: Bool, pageCount: Int, journalCount: Int, error: String?) {}
    #endif
}

#if DEBUG
enum ProfileCopySummaryDiagnostics {
    nonisolated static func logSiblingsBeforeCollapse(_ members: [TradeOwnerJournalSummary]) {
        print("[ProfileCopySummary] siblings=\(members.count)")
        for member in members {
            let tradeID = shortID(member.id.rawValue)
            let accountID = member.accountID.map { shortID($0.rawValue) } ?? "nil"
            let mode = modeLabel(member.summary.accountMode)
            let source = member.copyTrade?.sourceAccountID.map { shortID($0.rawValue) } ?? "nil"
            let copied = member.copyTrade?.copiedAccountIDs.map { shortID($0.rawValue) }.joined(separator: ",") ?? "nil"
            let groupID = member.copyTrade?.copyTradingGroupID.map { shortID($0) } ?? "nil"
            print(
                "[ProfileCopySummary] tradeID=\(tradeID) accountID=\(accountID) accountMode=\(mode) sourceAccountID=\(source) copiedAccountIDs=[\(copied)] groupID=\(groupID)"
            )
        }
    }

    nonisolated static func logGroupedCopyTrade(
        siblingCount: Int,
        participatingCount: Int,
        finalCounts: CopyTradePresentation.ModeCounts,
        summary: String?
    ) {
        let counts =
            "{funded:\(finalCounts.funded),eval:\(finalCounts.eval),live:\(finalCounts.live),sim:\(finalCounts.sim),backtest:\(finalCounts.backtest)}"
        let line = summary ?? "nil"
        print(
            "[ProfileCopySummary] siblings=\(siblingCount) participating=\(participatingCount) finalCounts=\(counts) summary=\"\(line)\""
        )
    }

    nonisolated private static func shortID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return String(trimmed.prefix(8)) + "..."
    }

    nonisolated static func logCopyTradeCardRender(
        tradeID: String,
        isCopyTraded: Bool,
        accountMode: TradingAccountMode?,
        copySummary: String?,
        renderedText: String?
    ) {
        let mode = modeLabel(accountMode)
        let summary = copySummary ?? "nil"
        let rendered = renderedText ?? "nil"
        print(
            "[ProfileCopyCardRender] tradeID=\(shortID(tradeID)) isCopy=\(isCopyTraded) accountMode=\(mode) copySummary=\"\(summary)\" renderedText=\"\(rendered)\""
        )
    }

    nonisolated static func modeLabel(_ mode: TradingAccountMode?) -> String {
        guard let mode else { return "nil" }
        switch mode {
        case .live: return "live"
        case .funded: return "funded"
        case .evaluation: return "eval"
        case .sim: return "sim"
        case .backtest: return "backtest"
        }
    }
}
#endif
