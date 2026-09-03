import Foundation

/// Wire trade row — mirrors `rpc_v1_dashboard_bootstrap` `trade_window` SQL projection.
nonisolated struct DashboardTradeWireV1: Codable, Sendable, Equatable {
    var id: String
    var date: String?
    var direction: String?
    var pnl: PostgresFlexibleDouble?
    var notes: String?
    var created_at: String?
    var image_url: String?
    var ticker: String?
    var rr: PostgresFlexibleDouble?
    var points: PostgresFlexibleDouble?
    var session: String?
    var account_type: String?
    var account_id: String?
    var user_id: String?
    var account_size: PostgresAccountSizeWire?
    var entry_price: PostgresFlexibleDouble?
    var exit_price: PostgresFlexibleDouble?
    var entry_time: String?
    var exit_time: String?
    var contracts: PostgresFlexibleDouble?
    var reviewed: PostgresFlexibleBool?
    var confidence: PostgresFlexibleDouble?
    var emotion: String?
    var followed_plan: PostgresFlexibleBool?
    var mistake_type: String?
    var market_condition: String?
    var news_event: PostgresFlexibleBool?
    var timeframe: String?
    var psychology_notes: String?
    var trade_type: String?
    var public_description: String?
    var is_pinned: PostgresFlexibleBool?
    var account_name: String?
    var mode: String?
    var strategy: String?
    var duration_seconds: PostgresFlexibleDouble?
    var duration_text: String?
    var image_display_mode: String?
    var is_public: PostgresFlexibleBool?
    var account_category: String?
    var top_confluences: String?
    var trade_date: String?
    var is_initial_import: PostgresFlexibleBool?
    var copy_trading_group_id: String?
    var trade_mode: String?
    var source_account_id: String?
    var copied_account_ids: [String]?

    func asTradeDTO(ownerID: String) -> TradeDTO.Trade {
        TradeDTO.Trade(
            id: id,
            user_id: user_id ?? ownerID,
            account_id: account_id,
            ticker: ticker,
            direction: direction,
            mode: mode,
            account_type: account_type,
            contracts: flex(contracts),
            entry_price: flex(entry_price),
            exit_price: flex(exit_price),
            entry_time: entry_time,
            exit_time: exit_time,
            pnl: flex(pnl),
            rr: flex(rr),
            points: flex(points),
            session: session,
            is_public: is_public?.value,
            is_pinned: is_pinned?.value,
            public_description: public_description,
            image_url: image_url,
            notes: notes,
            created_at: created_at,
            date: date,
            trade_date: trade_date,
            account_name: account_name,
            strategy: strategy,
            duration_seconds: flex(duration_seconds),
            duration_text: duration_text,
            trade_mode: trade_mode,
            confidence: flex(confidence),
            emotion: emotion,
            followed_plan: followed_plan?.value,
            market_condition: market_condition,
            timeframe: timeframe,
            news_event: news_event?.value,
            psychology_notes: psychology_notes,
            image_display_mode: image_display_mode,
            reviewed: reviewed?.value,
            is_initial_import: is_initial_import?.value
        )
    }

    private func flex(_ value: PostgresFlexibleDouble?) -> FlexibleNumber? {
        guard let value else { return nil }
        return FlexibleNumber(value.decimal)
    }
}

extension DashboardTradeWireV1 {
    /// Merge journal fields from a domain trade after Edit Trade / local mutation.
    mutating func mergeJournalFields(from trade: Trade) {
        ticker = trade.symbol.ticker
        direction = trade.side == .long ? "Long" : "Short"
        mode = trade.mode.rawValue
        contracts = PostgresFlexibleDouble(NSDecimalNumber(decimal: trade.quantity).doubleValue)
        entry_price = PostgresFlexibleDouble(trade.entryPrice.map { NSDecimalNumber(decimal: $0).doubleValue })
        exit_price = PostgresFlexibleDouble(trade.exitPrice.map { NSDecimalNumber(decimal: $0).doubleValue })
        entry_time = ISO8601.string(from: trade.entryAt)
        exit_time = trade.exitAt.map(ISO8601.string(from:))
        pnl = PostgresFlexibleDouble(trade.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue })
        rr = PostgresFlexibleDouble(trade.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue })
        points = PostgresFlexibleDouble(trade.points.map { NSDecimalNumber(decimal: $0).doubleValue })
        session = trade.sessionLabel
        strategy = trade.strategy
        notes = trade.notes ?? trade.notePreview
        image_url = trade.thumbnail?.id
        public_description = trade.publicCaption
        is_public = PostgresFlexibleBool(trade.visibility == .public)
        account_id = trade.accountID?.rawValue
        trade_mode = trade.mode == .copyTraded ? "copy_traded" : trade.mode.rawValue
        trade_date = TradingSessionLabel.easternTradeDateString(from: trade.entryAt)
        created_at = ISO8601.string(from: trade.createdAt)
        date = ISO8601.string(from: trade.createdAt)
        duration_text = trade.durationText
        duration_seconds = PostgresFlexibleDouble(trade.durationSeconds.map { Double($0) })
        confidence = PostgresFlexibleDouble(trade.confidence.map { Double($0) })
        emotion = trade.emotion
        followed_plan = PostgresFlexibleBool(trade.followedPlan)
        market_condition = trade.marketCondition
        timeframe = trade.timeframe
        news_event = PostgresFlexibleBool(trade.newsEvent)
        psychology_notes = trade.psychologyNotes
        image_display_mode = trade.imageDisplayMode.rawValue
        reviewed = PostgresFlexibleBool(trade.reviewed)
        is_initial_import = PostgresFlexibleBool(trade.isInitialImport)
    }
}

extension Trade {
    func asDashboardWireV1() -> DashboardTradeWireV1 {
        var row = DashboardTradeWireV1(id: id.rawValue)
        row.user_id = ownerProfileID.rawValue
        row.mergeJournalFields(from: self)
        return row
    }
}

/// Wire account row — mirrors `accounts` columns returned by the Dashboard RPC.
nonisolated struct DashboardAccountWireV1: Codable, Sendable, Equatable {
    var id: String
    var account_number: PostgresAccountSizeWire?
    var name: String?
    var account_size: PostgresAccountSizeWire?
    var mode: String?
    var category: String?
    var is_active: PostgresFlexibleBool?
    var can_add_trades: PostgresFlexibleBool?
    var note: String?
    var consistency: PostgresFlexibleDouble?
    var max_drawdown: PostgresFlexibleDouble?
    var daily_drawdown: PostgresFlexibleDouble?
    var profit_target: PostgresFlexibleDouble?
    var winning_days: PostgresFlexibleDouble?
    var winning_day_threshold: PostgresFlexibleDouble?
    var show_in_account_dropdowns: PostgresFlexibleBool?
    var custom_public_status: String?
    var payout_drawdown_behavior: String?
    var remember_payout_drawdown_behavior: PostgresFlexibleBool?
    var type: String?
    var currency: String?

    func asAccountDTO(ownerID: String) -> TradeDTO.Account {
        TradeDTO.Account(
            id: id,
            user_id: ownerID,
            name: name,
            account_name: nil,
            account_type: type,
            category: category,
            mode: mode,
            account_size: account_size.map { FlexibleNumber($0.decimal) },
            size: nil,
            account_number: account_number?.raw,
            note: note,
            is_active: is_active?.value,
            can_add_trades: can_add_trades?.value,
            show_in_account_dropdowns: show_in_account_dropdowns?.value,
            custom_public_status: custom_public_status,
            consistency: consistency.map { FlexibleNumber($0.decimal) },
            max_drawdown: max_drawdown.map { FlexibleNumber($0.decimal) },
            daily_drawdown: daily_drawdown.map { FlexibleNumber($0.decimal) },
            profit_target: profit_target.map { FlexibleNumber($0.decimal) },
            winning_days: winning_days.map { FlexibleNumber($0.decimal) },
            winning_day_threshold: winning_day_threshold.map { FlexibleNumber($0.decimal) },
            payout_drawdown_behavior: payout_drawdown_behavior
        )
    }
}

nonisolated struct DashboardMetricsWireV1: Codable, Sendable, Equatable {
    var total_trades: PostgresFlexibleDouble?
    var wins: PostgresFlexibleDouble?
    var losses: PostgresFlexibleDouble?
    var win_rate: PostgresFlexibleDouble?
    var net_pnl: PostgresFlexibleDouble?
    var avg_rr: PostgresFlexibleDouble?
    var avg_win: PostgresFlexibleDouble?
    var avg_loss: PostgresFlexibleDouble?
    var biggest_win: PostgresFlexibleDouble?
    var biggest_loss: PostgresFlexibleDouble?
}

nonisolated struct DashboardEquityPointWireV1: Codable, Sendable, Equatable {
    var t: String
    var v: PostgresFlexibleDouble

    var numericValue: Double? { v.value }
}

nonisolated struct DashboardRecentTradeWireV1: Codable, Sendable, Equatable {
    var id: String?
}
