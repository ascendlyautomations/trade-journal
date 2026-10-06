import XCTest
@testable import TradeTraxs

final class CopyTradePresentationModeSummaryTests: XCTestCase {
    private let profileID = ProfileID("11111111-1111-1111-1111-111111111111")
    private let sourceID = TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
    private let copyB = TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
    private let copyC = TradingAccountID("cccccccc-cccc-cccc-cccc-cccccccccccc")
    private let copyD = TradingAccountID("dddddddd-dddd-dddd-dddd-dddddddddddd")

    private let metadata = CopyTradeJournalMetadata(
        sourceAccountID: TradingAccountID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        copiedAccountIDs: [
            TradingAccountID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            TradingAccountID("cccccccc-cccc-cccc-cccc-cccccccccccc"),
        ],
        copyTradingGroupID: "group-1"
    )

    func testThreeAccountsTwoFundedOneEval() {
        let members = [
            journalRow(id: "1", account: sourceID, mode: .funded),
            journalRow(id: "2", account: copyB, mode: .funded),
            journalRow(id: "3", account: copyC, mode: .evaluation),
        ]
        let line = CopyTradePresentation.publicAcrossAccountsSummary(for: members)
        XCTAssertEqual(line, "Copy Traded across 3 accounts • 2 Funded • 1 Eval")
    }

    func testTwoAccountsFundedAndEval() {
        let twoMemberMetadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB],
            copyTradingGroupID: "group-2"
        )
        let members = [
            journalRow(id: "1", account: sourceID, mode: .funded, metadata: twoMemberMetadata),
            journalRow(id: "2", account: copyB, mode: .evaluation, metadata: twoMemberMetadata),
        ]
        let line = CopyTradePresentation.publicAcrossAccountsSummary(for: members)
        XCTAssertEqual(line, "Copy Traded across 2 accounts • 1 Funded • 1 Eval")
    }

    func testFourAccountsMixedModes() {
        let fourMetadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC, copyD],
            copyTradingGroupID: "group-3"
        )
        let members = [
            journalRow(id: "1", account: sourceID, mode: .live, metadata: fourMetadata),
            journalRow(id: "2", account: copyB, mode: .funded, metadata: fourMetadata),
            journalRow(id: "3", account: copyC, mode: .funded, metadata: fourMetadata),
            journalRow(id: "4", account: copyD, mode: .evaluation, metadata: fourMetadata),
        ]
        let line = CopyTradePresentation.publicAcrossAccountsSummary(for: members)
        XCTAssertEqual(line, "Copy Traded across 4 accounts • 1 Live • 2 Funded • 1 Eval")
    }

    func testSingleRowParticipatingModesPayloadProducesCanonicalSummary() {
        let payloadMetadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "group-feed",
            participatingAccountModesByID: [
                sourceID: .evaluation,
                copyB: .funded,
                copyC: .funded,
            ]
        )
        let members = [
            journalRow(id: "feed-1", account: sourceID, mode: .evaluation, metadata: payloadMetadata),
        ]
        let line = CopyTradePresentation.publicAcrossAccountsSummary(for: members)
        XCTAssertEqual(line, "Copy Traded across 3 accounts • 2 Funded • 1 Eval")
    }

    func testParticipatingIDsForCopyGroupMergesLinkageAcrossSiblings() {
        let metadata = CopyTradeJournalMetadata(
            sourceAccountID: sourceID,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "group-1"
        )
        let members = [
            journalRow(id: "1", account: sourceID, mode: .evaluation, metadata: metadata),
            journalRow(id: "2", account: copyB, mode: .funded, metadata: metadata),
            journalRow(id: "3", account: copyC, mode: .funded, metadata: metadata),
        ]
        let ids = CopyTradePresentation.participatingAccountIDsForCopyGroup(members)
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains(sourceID))
        XCTAssertTrue(ids.contains(copyB))
        XCTAssertTrue(ids.contains(copyC))
    }

    func testParticipatingIDsForCopyGroupUsesCopiedFromBootstrapRowsWithoutSource() {
        let bootstrapMetadata = CopyTradeJournalMetadata(
            sourceAccountID: nil,
            copiedAccountIDs: [copyB, copyC],
            copyTradingGroupID: "group-1"
        )
        let members = (1...3).map { index in
            journalRow(
                id: "\(index)",
                account: nil,
                mode: .funded,
                metadata: bootstrapMetadata
            )
        }
        let ids = CopyTradePresentation.participatingAccountIDsForCopyGroup(members)
        XCTAssertEqual(Set(ids.map(\.rawValue)), Set([copyB.rawValue, copyC.rawValue]))
    }

    func testParticipatingIDsIncludeFullCopySet() {
        let ids = CopyTradePresentation.participatingAccountIDs(
            metadata: metadata,
            rowAccountID: nil
        )
        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains(sourceID))
        XCTAssertTrue(ids.contains(copyB))
        XCTAssertTrue(ids.contains(copyC))
    }

    func testFeedModeSuffixUsesCanonicalCountsOnly() {
        let mixed = CopyTradePresentation.publicAcrossAccountsSummary(
            participatingAccountCount: 3,
            counts: .init(live: 0, funded: 2, eval: 1, sim: 0, backtest: 0)
        )
        XCTAssertEqual(
            CopyTradePresentation.modeCountSegment(fromPublicSummary: mixed),
            "2 Funded • 1 Eval"
        )

        let fundedOnly = CopyTradePresentation.publicAcrossAccountsSummary(
            participatingAccountCount: 3,
            counts: .init(live: 0, funded: 3, eval: 0, sim: 0, backtest: 0)
        )
        XCTAssertEqual(
            CopyTradePresentation.modeCountSegment(fromPublicSummary: fundedOnly),
            "3 Funded"
        )

        let ordered = CopyTradePresentation.publicModeSummary(
            counts: .init(live: 1, funded: 2, eval: 0, sim: 0, backtest: 0)
        )
        XCTAssertEqual(
            CopyTradePresentation.modeCountSegment(fromPublicSummary: ordered),
            "1 Live • 2 Funded"
        )

        let evalSim = CopyTradePresentation.modeCountSegment(
            from: .init(live: 0, funded: 0, eval: 2, sim: 1, backtest: 0)
        )
        XCTAssertEqual(evalSim, "2 Eval • 1 Sim")

        let accountsOnly = CopyTradePresentation.publicAcrossAccountsSummary(
            participatingAccountCount: 2,
            counts: .init()
        )
        XCTAssertNil(CopyTradePresentation.modeCountSegment(fromPublicSummary: accountsOnly))
        XCTAssertNil(CopyTradePresentation.modeCountSegment(fromPublicSummary: nil))
        XCTAssertNil(CopyTradePresentation.modeCountSegment(fromPublicSummary: " "))
    }

    func testFeedCopyExecutionMetadataUsesEntryAndExitTimes() {
        let entry = Date(timeIntervalSince1970: 1_700_000_000)
        let exit = entry.addingTimeInterval(90 * 60)
        let line = TradeDisplay.feedCopyExecutionMetadata(entryAt: entry, exitAt: exit)
        XCTAssertEqual(
            line,
            "\(TradeDisplay.socialSharedExecutionTimeRangeText(entryAt: entry, exitAt: exit)) • \(TradeDisplay.dateText(entry))"
        )
        XCTAssertFalse(line.contains("Long"))
        XCTAssertFalse(line.contains("Short"))

        let open = TradeDisplay.feedCopyExecutionMetadata(entryAt: entry, exitAt: nil)
        XCTAssertEqual(
            open,
            "\(TradeDisplay.socialSharedExecutionTimeRangeText(entryAt: entry, exitAt: nil)) • \(TradeDisplay.dateText(entry))"
        )
        XCTAssertFalse(open.contains("–"))
    }

    private func journalRow(
        id: String,
        account: TradingAccountID?,
        mode: TradingAccountMode,
        metadata: CopyTradeJournalMetadata? = nil
    ) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: TradeSummary(
                id: TradeID(id),
                ownerProfileID: profileID,
                symbol: Symbol(ticker: "MNQ"),
                side: .long,
                realizedPnL: nil,
                riskReward: nil,
                points: nil,
                quantity: 1,
                entryAt: Date(),
                exitAt: nil,
                createdAt: Date(),
                visibility: .public,
                publicCaption: nil,
                notePreview: nil,
                thumbnail: nil,
                imageDisplayMode: .fit,
                mode: .copyTraded,
                accountMode: mode,
                publicAccountBadge: nil,
                durationSeconds: nil,
                durationText: nil
            ),
            accountID: account,
            accountName: nil,
            strategy: nil,
            entryPrice: nil,
            exitPrice: nil,
            sessionLabel: nil,
            copyTrade: metadata ?? self.metadata
        )
    }
}
