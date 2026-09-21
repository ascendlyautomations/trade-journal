import Foundation

nonisolated enum TradeSummaryMapper {
    static func map(from wire: TradeSummaryWireV1) throws -> TradeSummary {
        try wire.validateSchema()
        guard let entryAt = parseFirstDate(
            wire.entry_time,
            wire.created_at
        ) else {
            throw MappingError.missingField("entry_time")
        }
        let createdAt = ISO8601.date(from: wire.created_at) ?? entryAt
        let side = TradeMapper.mapSide(wire.direction)
        let mode = TradeMapper.mapMode(wire.trade_mode ?? wire.mode ?? wire.account_type)
        let visibility: ContentVisibility = (wire.is_public?.value == true) ? .public : .private
        let badge = PublicTradeAccountBadge.label(
            tradeMode: wire.mode,
            accountType: wire.account_type
        )
        return TradeSummary(
            id: TradeID(wire.id),
            ownerProfileID: ProfileID(wire.user_id),
            symbol: Symbol(ticker: wire.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
            side: side,
            realizedPnL: flexDecimal(wire.pnl).map { Money(amount: $0, currencyCode: "USD") },
            riskReward: flexDecimal(wire.rr),
            points: flexDecimal(wire.points),
            quantity: flexDecimal(wire.contracts) ?? 0,
            entryAt: entryAt,
            exitAt: ISO8601.date(from: wire.exit_time),
            createdAt: createdAt,
            visibility: visibility,
            publicCaption: wire.public_description,
            notePreview: wire.note_preview,
            thumbnail: ContentImagePresentation.mediaReference(
                url: wire.image_url,
                crop: ContentImagePresentationCodec.decode(from: wire.image_crop)
            ),
            imageDisplayMode: TradeScreenshotDisplayMode.resolve(wire.image_display_mode),
            mode: mode,
            publicAccountBadge: badge,
            durationSeconds: flexDecimal(wire.duration_seconds).map {
                Int(truncating: NSDecimalNumber(decimal: $0))
            },
            durationText: wire.duration_text?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func summary(from detail: TradeDetail) -> TradeSummary {
        TradeSummary(
            id: detail.id,
            ownerProfileID: detail.ownerProfileID,
            symbol: detail.symbol,
            side: detail.side,
            realizedPnL: detail.realizedPnL,
            riskReward: detail.riskReward,
            points: detail.points,
            quantity: detail.quantity,
            entryAt: detail.entryAt,
            exitAt: detail.exitAt,
            createdAt: detail.createdAt,
            visibility: detail.visibility,
            publicCaption: detail.publicCaption,
            notePreview: detail.notePreview,
            thumbnail: detail.thumbnail,
            imageDisplayMode: detail.imageDisplayMode,
            mode: detail.mode,
            publicAccountBadge: detail.publicAccountBadge,
            durationSeconds: detail.durationSeconds,
            durationText: detail.durationText
        )
    }

    static func presentationSeed(from detail: TradeDetail) -> DetailPresentationSeed {
        DetailPresentationSeed(summary: summary(from: detail))
    }

    /// List `Trade` rows (partial hydration allowed) → non-authoritative seed.
    static func presentationSeed(fromListTrade trade: Trade) -> DetailPresentationSeed {
        DetailPresentationSeed(summary: summary(fromPartialListTrade: trade))
    }

    static func mapOwnerJournal(from wire: TradeOwnerJournalSummaryWireV1) throws -> TradeOwnerJournalSummary {
        let coreWire = TradeSummaryWireV1(
            summary_schema: wire.summary_schema,
            id: wire.id,
            user_id: wire.user_id,
            ticker: wire.ticker,
            direction: wire.direction,
            pnl: wire.pnl,
            rr: wire.rr,
            points: wire.points,
            contracts: wire.contracts,
            entry_time: wire.entry_time,
            exit_time: wire.exit_time,
            created_at: wire.created_at,
            is_public: wire.is_public,
            public_description: wire.public_description,
            note_preview: wire.note_preview,
            image_url: wire.image_url,
            image_crop: wire.image_crop,
            image_display_mode: wire.image_display_mode,
            mode: wire.mode,
            account_type: wire.account_type,
            trade_mode: wire.trade_mode,
            duration_seconds: wire.duration_seconds,
            duration_text: wire.duration_text
        )
        let summary = try map(from: coreWire)
        let accountID = wire.account_id.flatMap { raw -> TradingAccountID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradingAccountID(trimmed)
        }
        return TradeOwnerJournalSummary(
            summary: summary,
            accountID: accountID,
            accountName: trimmedOptional(wire.account_name),
            strategy: trimmedOptional(wire.strategy),
            entryPrice: flexDecimal(wire.entry_price),
            exitPrice: flexDecimal(wire.exit_price),
            sessionLabel: trimmedOptional(wire.session)
        )
    }

    static func ownerJournal(from detail: TradeDetail) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: summary(from: detail),
            accountID: detail.accountID,
            accountName: nil,
            strategy: detail.strategy,
            entryPrice: detail.entryPrice,
            exitPrice: detail.exitPrice,
            sessionLabel: detail.sessionLabel
        )
    }

    static func ownerJournal(fromListTrade trade: Trade) -> TradeOwnerJournalSummary {
        TradeOwnerJournalSummary(
            summary: summary(fromPartialListTrade: trade),
            accountID: trade.accountID,
            accountName: nil,
            strategy: trade.strategy,
            entryPrice: trade.entryPrice,
            exitPrice: trade.exitPrice,
            sessionLabel: trade.sessionLabel
        )
    }

    static func presentationSeed(from item: TradeOwnerJournalSummary) -> DetailPresentationSeed {
        DetailPresentationSeed(summary: item.summary)
    }

    static func summary(fromPartialListTrade trade: Trade) -> TradeSummary {
        TradeSummary(
            id: trade.id,
            ownerProfileID: trade.ownerProfileID,
            symbol: trade.symbol,
            side: trade.side,
            realizedPnL: trade.realizedPnL,
            riskReward: trade.riskReward,
            points: trade.points,
            quantity: trade.quantity,
            entryAt: trade.entryAt,
            exitAt: trade.exitAt,
            createdAt: trade.createdAt,
            visibility: trade.visibility,
            publicCaption: trade.publicCaption,
            notePreview: trade.notePreview,
            thumbnail: trade.thumbnail,
            imageDisplayMode: trade.imageDisplayMode,
            mode: trade.mode,
            publicAccountBadge: trade.publicAccountBadge,
            durationSeconds: trade.durationSeconds,
            durationText: trade.durationText
        )
    }

    /// Local filter/search parity — includes owner journal fields without full detail hydration.
    static func listMatchTrade(from item: TradeOwnerJournalSummary) -> Trade {
        var trade = previewTrade(from: item.summary)
        trade.accountID = item.accountID
        trade.strategy = item.strategy
        trade.entryPrice = item.entryPrice
        trade.exitPrice = item.exitPrice
        trade.sessionLabel = item.sessionLabel
        return trade
    }

    static func previewTrade(from summary: TradeSummary) -> Trade {
        Trade(
            id: summary.id,
            ownerProfileID: summary.ownerProfileID,
            accountID: nil,
            symbol: summary.symbol,
            side: summary.side,
            mode: summary.mode,
            quantity: summary.quantity,
            entryPrice: nil,
            exitPrice: nil,
            entryAt: summary.entryAt,
            exitAt: summary.exitAt,
            realizedPnL: summary.realizedPnL,
            riskReward: summary.riskReward,
            points: summary.points,
            sessionLabel: nil,
            visibility: summary.visibility,
            publicCaption: summary.publicCaption,
            thumbnail: summary.thumbnail,
            imageDisplayMode: summary.imageDisplayMode,
            notePreview: summary.notePreview,
            notes: nil,
            strategy: nil,
            timeframe: nil,
            newsEvent: nil,
            confidence: nil,
            emotion: nil,
            followedPlan: nil,
            marketCondition: nil,
            psychologyNotes: nil,
            exitEmotion: nil,
            executionRating: nil,
            durationText: summary.durationText,
            durationSeconds: summary.durationSeconds,
            reviewed: nil,
            isInitialImport: nil,
            importSource: nil,
            importFingerprint: nil,
            accountMode: nil,
            publicAccountBadge: summary.publicAccountBadge,
            createdAt: summary.createdAt,
            updatedAt: summary.createdAt
        )
    }

    private static func parseFirstDate(_ values: String?...) -> Date? {
        for value in values {
            if let value, let date = ISO8601.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func flexDecimal(_ value: PostgresFlexibleDouble?) -> Decimal? {
        guard let value, let raw = value.value else { return nil }
        return Decimal(raw)
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
