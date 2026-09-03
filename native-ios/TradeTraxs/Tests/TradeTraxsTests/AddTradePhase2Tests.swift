import XCTest
@testable import TradeTraxs

final class TradeHoldDurationTests: XCTestCase {
    func testComputeDurationFromEntryExit() {
        let entry = Date(timeIntervalSince1970: 0)
        let exit = Date(timeIntervalSince1970: 3_600 + 900)
        let computed = TradeHoldDuration.compute(entryAt: entry, exitAt: exit)
        XCTAssertEqual(computed?.seconds, 4_500)
        XCTAssertEqual(computed?.text, "1h 15m")
    }

    func testComputeReturnsNilWithoutExit() {
        XCTAssertNil(TradeHoldDuration.compute(entryAt: .now, exitAt: nil))
    }

    func testFormatSecondsUsesDayHourForLongHolds() {
        XCTAssertEqual(TradeHoldDuration.formatSeconds(90000), "1d 1h")
    }
}

final class TradeScreenshotDisplayModeTests: XCTestCase {
    func testResolveDefaultsToFit() {
        XCTAssertEqual(TradeScreenshotDisplayMode.resolve(nil), .fit)
        XCTAssertEqual(TradeScreenshotDisplayMode.resolve(""), .fit)
        XCTAssertEqual(TradeScreenshotDisplayMode.resolve("FIT"), .fit)
    }

    func testResolveFill() {
        XCTAssertEqual(TradeScreenshotDisplayMode.resolve("fill"), .fill)
        XCTAssertEqual(TradeScreenshotDisplayMode.resolve(" Fill "), .fill)
    }
}

final class TradePhase2MapperTests: XCTestCase {
    func testInsertBodyIncludesDurationAndDisplayMode() {
        var draft = TradeDraft(
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: Date(timeIntervalSince1970: 0),
            exitAt: Date(timeIntervalSince1970: 1_800),
            visibility: .private
        )
        draft.imageDisplayMode = .fill
        draft.durationSeconds = 1_800
        draft.durationText = "30m"

        let body = TradeMapper.insertBody(from: draft, userID: UserID("user-1"))
        XCTAssertEqual(body.duration_seconds, 1_800)
        XCTAssertEqual(body.duration_text, "30m")
        XCTAssertEqual(body.image_display_mode, "fill")
    }

    func testUpdateBodyMarksCsvImportReviewed() {
        var draft = TradeDraft(
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: .now,
            visibility: .private
        )
        draft.noteBody = "Reviewed import"
        let previous = Trade(
            id: TradeID("csv-1"),
            ownerProfileID: ProfileID("viewer"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: .now,
            exitAt: nil,
            realizedPnL: nil,
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            reviewed: false,
            isInitialImport: true,
            createdAt: .now,
            updatedAt: .now
        )

        let body = TradeMapper.updateBody(from: draft, createdAt: previous.createdAt, previous: previous)
        XCTAssertEqual(body.reviewed, true)
    }

    func testUpdateBodyDoesNotMarkReviewedForManualTrade() {
        let draft = TradeDraft(
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryAt: .now,
            visibility: .private
        )
        let previous = Trade(
            id: TradeID("manual-1"),
            ownerProfileID: ProfileID("viewer"),
            accountID: nil,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: .now,
            exitAt: nil,
            realizedPnL: nil,
            riskReward: nil,
            points: nil,
            sessionLabel: nil,
            visibility: .private,
            publicCaption: nil,
            thumbnail: nil,
            notePreview: nil,
            createdAt: .now,
            updatedAt: .now
        )

        let body = TradeMapper.updateBody(from: draft, createdAt: previous.createdAt, previous: previous)
        XCTAssertNil(body.reviewed)
    }

    func testMapToDomainRoundTripsDisplayModeAndReviewFlags() throws {
        let dto = TradeDTO.Trade(
            id: "t1",
            user_id: "user-1",
            ticker: "NQ",
            direction: "Long",
            contracts: FlexibleNumber(1),
            entry_time: ISO8601.string(from: Date()),
            created_at: ISO8601.string(from: Date()),
            date: ISO8601.string(from: Date()),
            image_display_mode: "fill",
            reviewed: true,
            is_initial_import: true
        )

        let trade = try TradeMapper.mapToDomain(dto)
        XCTAssertEqual(trade.imageDisplayMode, .fill)
        XCTAssertEqual(trade.reviewed, true)
        XCTAssertEqual(trade.isInitialImport, true)
    }
}
