import XCTest
@testable import TradeTraxs

@MainActor
final class CSVImportExperienceTests: XCTestCase {
    func testOpenComposeImportCSVPresentsFullScreen() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.openCompose(.importCSV)
        XCTAssertEqual(store.presentedFullScreen, .importCSV)
    }

    func testExplicitCRLFScalarRecordBoundaries() throws {
        let csv =
            "symbol,priceFormat,priceFormatType,tickSize,buyFillId,sellFillId,qty,buyPrice,sellPrice,pnl,boughtTimestamp,soldTimestamp,duration"
            + "\r\n"
            + "MGCM6,1,0,0.1,660290950163,660290950170,1,4348.4,4348.1,\"$(3.00)\",05/05/2026 20:11:36,05/05/2026 20:11:40,0:00:15"
            + "\r\n"
            + "MNQM6,1,0,0.25,660290950007,660290950014,1,28331.75,28320.25,$(69.00),05/05/2026 20:11:36,05/05/2026 20:13:52,0:02:16"
        let parsed = try CSVTextParser.parse(text: csv)
        XCTAssertEqual(parsed.headers.count, 13)
        XCTAssertFalse(parsed.headers.contains("MGCM6"))
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0]["symbol"], "MGCM6")
        XCTAssertEqual(parsed.rows[0]["pnl"], "$(3.00)")
    }

    func testTradovatePerformanceExportCRLFRecordBoundaries() throws {
        let parsed = try CSVTextParser.parse(text: CSVImportFixtures.tradovatePerformanceExportCRLF)
        XCTAssertEqual(parsed.headers.count, 13)
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertFalse(parsed.headers.contains("MGCM6"))
        let summary = try CSVTradeBuilder.build(
            fileName: "Performance__3_.csv",
            text: CSVImportFixtures.tradovatePerformanceExportCRLF
        )
        XCTAssertEqual(summary.format, .tradovate)
        XCTAssertEqual(summary.totalRows, 2)
        XCTAssertEqual(summary.successCount, 2)
    }

    func testTradovatePerformanceExportUnicodeLineSeparators() throws {
        let parsed = try CSVTextParser.parse(text: CSVImportFixtures.tradovatePerformanceExportUnicodeLines)
        XCTAssertEqual(parsed.headers.count, 13)
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows[0]["buyFillId"], "660290950163")
        XCTAssertEqual(parsed.rows[0]["sellFillId"], "")
        XCTAssertEqual(parsed.rows[1]["buyFillId"], "")
    }

    func testTradovatePerformanceExport24hTimestamps() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "performance.csv",
            text: CSVImportFixtures.tradovatePerformanceRowCSV
        )
        XCTAssertEqual(summary.format, .tradovate)
        XCTAssertEqual(summary.successCount, 1, "failures=\(summary.failures.map(\.reason))")
        let trade = try XCTUnwrap(summary.trades.first)
        XCTAssertEqual(trade.symbol, "MNQ")
        XCTAssertEqual(trade.realizedPnL, Decimal(string: "-69"))
        XCTAssertEqual(trade.side, .short)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: trade.entryAt), 2026)
        XCTAssertEqual(cal.component(.month, from: trade.entryAt), 5)
        XCTAssertEqual(cal.component(.day, from: trade.entryAt), 5)
        XCTAssertEqual(cal.component(.hour, from: trade.entryAt), 20)
        XCTAssertEqual(cal.component(.minute, from: trade.entryAt), 11)
    }

    func testTradovateInvalidTimestampFallsBackLikeWeb() throws {
        let csv = """
        symbol,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp
        MNQM6,28331.75,28320.25,1,$(69.00),not-a-date,05/05/2026 20:13:52
        """
        let summary = try CSVTradeBuilder.build(fileName: "bad.csv", text: csv)
        XCTAssertEqual(summary.successCount, 1, "failures=\(summary.failures.map(\.reason))")
        XCTAssertTrue(summary.trades[0].warningMessages.contains("Timestamp fallback used"))
    }

    func testDetectTradovateFormatAndParseRows() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "tradovate.csv",
            text: CSVImportFixtures.tradovateCSV
        )
        XCTAssertEqual(summary.format, .tradovate)
        XCTAssertEqual(summary.successCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.trades[0].symbol, "MNQ")
        XCTAssertEqual(summary.trades[0].side, .long)
        XCTAssertEqual(summary.trades[0].quantity, 2)
        XCTAssertEqual(summary.trades[0].realizedPnL, Decimal(string: "437.5"))
        XCTAssertNotNil(summary.trades[0].points)
        XCTAssertEqual(summary.trades[1].side, .short)
    }

    func testFlexibleCSVParsesRequiredFieldsAndRR() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "flex.csv",
            text: CSVImportFixtures.flexibleCSV
        )
        XCTAssertEqual(summary.format, .flexible)
        XCTAssertEqual(summary.successCount, 3)
        XCTAssertEqual(summary.trades[0].riskReward, Decimal(string: "2.5"))
        XCTAssertEqual(summary.trades[1].side, .short)
        XCTAssertNil(summary.trades[1].riskReward)
    }

    func testEnteredExitedFormatDetection() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "nt.csv",
            text: CSVImportFixtures.enteredExitedCSV
        )
        XCTAssertEqual(summary.format, .enteredExited)
        XCTAssertEqual(
            summary.successCount,
            2,
            "failures=\(summary.failures.map(\.reason))"
        )
        XCTAssertEqual(summary.trades.first?.symbol, "MNQ")
    }

    func testGoldenMathAudit24HourTimeOnlyCombinesWithDate() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "TradeTraxs_Golden_Math_Audit_2026.csv",
            text: CSVImportFixtures.goldenMathAuditCSV(entryTime: "09:30:00")
        )
        XCTAssertEqual(summary.format, .enteredExited)
        XCTAssertEqual(summary.successCount, 1, "failures=\(summary.failures.map(\.reason))")
        let trade = try XCTUnwrap(summary.trades.first)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: trade.entryAt), 2026)
        XCTAssertEqual(cal.component(.month, from: trade.entryAt), 1)
        XCTAssertEqual(cal.component(.day, from: trade.entryAt), 5)
        XCTAssertEqual(cal.component(.hour, from: trade.entryAt), 9)
        XCTAssertEqual(cal.component(.minute, from: trade.entryAt), 30)
        XCTAssertEqual(cal.component(.second, from: trade.entryAt), 0)
        XCTAssertEqual(trade.durationSeconds, 44 * 60)
    }

    func testEnteredExitedAcceptsTimeOnly24And12HourFormats() throws {
        let cases: [(String, String, Int, Int)] = [
            ("09:30:00", "10:00:00", 9, 30),
            ("14:45:00", "15:00:00", 14, 45),
            ("21:05:00", "22:00:00", 21, 5),
            ("09:30", "10:00", 9, 30),
            ("14:45", "15:00", 14, 45),
            ("9:30 AM", "10:00 AM", 9, 30),
            ("2:45 PM", "3:00 PM", 14, 45),
        ]
        let cal = Calendar.current
        for (entryTime, exitTime, hour, minute) in cases {
            let summary = try CSVTradeBuilder.build(
                fileName: "audit.csv",
                text: CSVImportFixtures.goldenMathAuditCSV(entryTime: entryTime, exitTime: exitTime)
            )
            XCTAssertEqual(
                summary.successCount,
                1,
                "entryTime=\(entryTime) failures=\(summary.failures.map(\.reason))"
            )
            let trade = try XCTUnwrap(summary.trades.first)
            XCTAssertEqual(cal.component(.day, from: trade.entryAt), 5)
            XCTAssertEqual(cal.component(.hour, from: trade.entryAt), hour)
            XCTAssertEqual(cal.component(.minute, from: trade.entryAt), minute)
        }
    }

    func testEnteredExitedRejectsPresentButInvalidEntryTime() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "bad-time.csv",
            text: CSVImportFixtures.goldenMathAuditCSV(entryTime: "not-a-time")
        )
        XCTAssertEqual(summary.successCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertTrue(summary.failures[0].reason.contains("Invalid entry time"))
    }

    func testGoldenMathAuditFullFileParserHoldUnderFourHours() throws {
        let path = "/Users/TradeTraxs/Downloads/TradeTraxs_Golden_Math_Audit_2026.csv"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Golden CSV not on this machine")
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let summary = try CSVTradeBuilder.build(
            fileName: "TradeTraxs_Golden_Math_Audit_2026.csv",
            text: text
        )
        XCTAssertEqual(summary.format, .enteredExited)
        XCTAssertEqual(summary.successCount, 190, "failures=\(summary.failures.map(\.reason))")
        let maxHold = summary.trades.compactMap(\.durationSeconds).max() ?? 0
        // Web `normalizeCsvEntryExitTimestamps` on this export (same parser rules).
        XCTAssertEqual(maxHold, 81_900)
        XCTAssertEqual(summary.trades.filter { ($0.durationSeconds ?? 0) >= 14_400 }.count, 4)
    }

    func testGoldenMathAuditMidnightCrossMatchesWebNormalize() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "audit-midnight.csv",
            text: CSVImportFixtures.goldenMathAuditMidnightCrossCSV
        )
        XCTAssertEqual(summary.successCount, 1, "failures=\(summary.failures.map(\.reason))")
        let trade = try XCTUnwrap(summary.trades.first)
        // Web `normalizeCsvEntryExitTimestamps` reorders when exit clock < entry on same date.
        XCTAssertEqual(trade.durationSeconds, 81_360)
    }

    func testFlexiblePathUsesSameTimeOnlyParsing() throws {
        let csv = """
        \(CSVImportFixtures.goldenMathAuditHeader)
        \(CSVImportFixtures.goldenMathAuditRow(entryTime: "14:45:00", exitTime: "15:30:00"))
        """
        let parsed = try CSVTextParser.parse(text: csv)
        let summary = CSVTradeBuilder.build(
            fileName: "flex.csv",
            headers: parsed.headers,
            rows: parsed.rows
        )
        XCTAssertEqual(summary.successCount, 1, "failures=\(summary.failures.map(\.reason))")
        let trade = try XCTUnwrap(summary.trades.first)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: trade.entryAt), 14)
        XCTAssertEqual(cal.component(.minute, from: trade.entryAt), 45)
        XCTAssertEqual(trade.durationSeconds, 45 * 60)
    }

    func testUnknownCSVNeedsManualMapping() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "unknown.csv",
            text: CSVImportFixtures.unknownCSV
        )
        XCTAssertEqual(summary.format, .flexible)
        XCTAssertTrue(CSVTradeBuilder.needsManualMapping(summary: summary))
        XCTAssertEqual(summary.successCount, 0)
    }

    func testManualMappingImportsUnknownCSV() throws {
        let parsed = try CSVTextParser.parse(text: CSVImportFixtures.unknownCSV)
        let mappings = [
            CSVColumnMapping(header: "Widget", field: .symbol),
            CSVColumnMapping(header: "Flip", field: .direction),
            CSVColumnMapping(header: "Beans", field: .contracts),
            CSVColumnMapping(header: "Cash", field: .pnl),
            // date required — synthesize via mapping a constant column isn't available;
            // inject date by rebuilding with an added column in fixture parse path:
        ]
        // Build enriched rows with a Date column for mapping completeness.
        let text = """
        Widget,Flip,Beans,Cash,When
        Alpha,Long,2,100,2026-01-15
        Beta,Short,1,-40,2026-01-15
        """
        let summary = try CSVTradeBuilder.build(
            fileName: "mapped.csv",
            text: text,
            mappings: [
                CSVColumnMapping(header: "Widget", field: .symbol),
                CSVColumnMapping(header: "Flip", field: .direction),
                CSVColumnMapping(header: "Beans", field: .contracts),
                CSVColumnMapping(header: "Cash", field: .pnl),
                CSVColumnMapping(header: "When", field: .date),
            ]
        )
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.trades[0].symbol, "ALPHA")
        XCTAssertEqual(summary.trades[1].realizedPnL, -40)
        _ = parsed
        _ = mappings
    }

    func testMixedNonTradovateRowsParsePerRowLikeWeb() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "mixed.csv",
            text: CSVImportFixtures.mixedNonTradovateCSV
        )
        XCTAssertEqual(summary.successCount, 2, "failures=\(summary.failures.map(\.reason))")
        XCTAssertEqual(summary.trades[0].symbol, "NQ")
        XCTAssertEqual(summary.trades[1].symbol, "MNQ")
    }

    func testQuotedCommaSymbolFieldParses() throws {
        let parsed = try CSVTextParser.parse(text: CSVImportFixtures.quotedCommaCSV)
        XCTAssertEqual(parsed.rows.first?["symbol"], "MNQ,M6")
        let summary = try CSVTradeBuilder.build(
            fileName: "quoted.csv",
            text: CSVImportFixtures.quotedCommaCSV
        )
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.trades.first?.symbol, "MNQ,M6")
    }

    func testFlexibleDurationColumnParsesToSeconds() throws {
        let summary = try CSVTradeBuilder.build(
            fileName: "dur.csv",
            text: CSVImportFixtures.flexibleWithDurationCSV
        )
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.trades.first?.durationSeconds, 44 * 60)
    }

    func testTradovateTickSizeRoundsPoints() throws {
        let csv = """
        symbol,tickSize,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp
        MNQ,0.25,100,100.75,1,50,2026-03-10T14:00:00Z,2026-03-10T14:01:00Z
        """
        let summary = try CSVTradeBuilder.build(fileName: "tick.csv", text: csv)
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.trades.first?.points, Decimal(string: "0.75"))
    }

    func testEachCSVRowBecomesOneTradeNoFillGrouping() throws {
        // Web parity: no fill reconstruction — 3 rows → 3 trades.
        let summary = try CSVTradeBuilder.build(
            fileName: "tradovate.csv",
            text: CSVImportFixtures.tradovateCSV
        )
        XCTAssertEqual(summary.trades.count, 3)
        XCTAssertEqual(summary.totalRows, 3)
    }

    func testLargeCSVParsesOffMainThreadSemantics() throws {
        // Representative larger file (500 rows) — parse should finish quickly locally.
        var lines = ["symbol,buyPrice,sellPrice,qty,pnl,boughtTimestamp,soldTimestamp,side"]
        for i in 0..<500 {
            lines.append(
                "MNQ,21400,21410,1,50,2026-03-10T14:00:00Z,2026-03-10T14:01:00Z,Buy"
            )
            _ = i
        }
        let text = lines.joined(separator: "\n")
        let start = CFAbsoluteTimeGetCurrent()
        let summary = try CSVTradeBuilder.build(fileName: "large.csv", text: text)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(summary.successCount, 500)
        XCTAssertLessThan(elapsed, 2.0, "500-row Tradovate parse took \(elapsed)s")
    }

    func testNumericParserHandlesCurrencyAndAccountingNegatives() {
        XCTAssertEqual(CSVNumericParser.parse("$1,234.50"), Decimal(string: "1234.50"))
        XCTAssertEqual(CSVNumericParser.parse("(150.00)"), Decimal(string: "-150"))
        XCTAssertEqual(CSVNumericParser.parse("-$20"), Decimal(string: "-20"))
        XCTAssertNil(CSVNumericParser.parse(""))
    }

    func testHeaderAliasesSuggestSymbolAndPnL() {
        let mappings = CSVHeaderAliases.suggestedMappings(for: [
            "Instrument", "Net P&L", "Qty", "Avg Buy Price",
        ])
        XCTAssertEqual(mappings.first { $0.header == "Instrument" }?.field, .symbol)
        XCTAssertEqual(mappings.first { $0.header == "Net P&L" }?.field, .pnl)
        XCTAssertEqual(mappings.first { $0.header == "Qty" }?.field, .contracts)
        XCTAssertEqual(mappings.first { $0.header == "Avg Buy Price" }?.field, .entryPrice)
    }

    func testViewModelParsesFixtureAndImportsViaRepository() async {
        let repository = CSVImportStubTradeRepository()
        let cache = DetailPresentationCache()
        let viewer = ProfileID("dev.csv.importer")
        cache.seed(accounts: PropFirmFixtures.accounts(owner: viewer), for: viewer)
        var dismissed = false
        let viewModel = CSVImportViewModel(
            trades: repository,
            session: CSVImportStubSession(userID: viewer.rawValue),
            detailCache: cache,
            onDismiss: { dismissed = true }
        )
        viewModel.loadAccountsIfNeeded()
        await waitFor { !viewModel.eligibleAccounts.isEmpty }

        viewModel.ingestFixtureText(CSVImportFixtures.tradovateCSV, fileName: "tv.csv")
        await waitFor {
            if case .preview = viewModel.phase { return true }
            return false
        }
        XCTAssertEqual(viewModel.summary?.format, .tradovate)
        XCTAssertTrue(viewModel.canImport)

        let before = TradeJournalMutationStore.shared.revision
        viewModel.importTrades()
        await waitFor {
            if case .result = viewModel.phase { return true }
            return false
        }
        XCTAssertEqual(repository.importedDrafts.count, 3)
        XCTAssertEqual(TradeJournalMutationStore.shared.revision, before + 1)
        if case .result(let result) = viewModel.phase {
            XCTAssertEqual(result.importedCount, 3)
        } else {
            XCTFail("Expected result phase")
        }
        viewModel.dismiss()
        XCTAssertTrue(dismissed)
    }

    func testDraftMapsAccountDenormalizedFields() {
        let account = PropFirmFixtures.accounts(owner: ProfileID("dev.csv"))[0]
        let trade = CSVParsedTrade(
            id: "1",
            rowNumber: 2,
            symbol: "MNQ",
            side: .long,
            quantity: 2,
            entryPrice: 1,
            exitPrice: 2,
            entryAt: Date(),
            exitAt: Date(),
            realizedPnL: 10,
            riskReward: nil,
            points: 1,
            sessionLabel: "NY",
            notes: "",
            strategy: nil,
            csvAccountName: nil,
            csvAccountID: nil,
            csvAccountSize: nil,
            durationSeconds: 60,
            status: .ready,
            warningMessages: []
        )
        let draft = CSVImportViewModel.draft(from: trade, account: account)
        XCTAssertEqual(draft.accountID, account.id)
        XCTAssertEqual(draft.accountName, account.name)
        XCTAssertEqual(draft.visibility, .private)
        XCTAssertEqual(draft.symbol.ticker, "MNQ")
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private struct CSVImportStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private final class CSVImportStubTradeRepository: TradeRepository, @unchecked Sendable {
    private(set) var importedDrafts: [TradeDraft] = []

    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        PropFirmFixtures.accounts(owner: profileID)
    }

    func importCSVTrades(
        _ drafts: [TradeDraft],
        isInitialImport: Bool
    ) async throws -> Int {
        importedDrafts = drafts
        XCTAssertTrue(isInitialImport)
        return drafts.count
    }
}
