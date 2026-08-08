import Foundation

nonisolated struct DefaultCalendarRepository: CalendarRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func events(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> [CalendarEvent] {
        let rows: [TradeDTO.Trade] = try await supabase.database.select(
            TradeDTO.Trade.self,
            from: "trades",
            query: [
                SupabaseQuery.select("id,user_id,ticker,pnl,created_at,entry_time"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "created_at", value: "gte.\(ISO8601.string(from: interval.start))"),
                URLQueryItem(name: "created_at", value: "lte.\(ISO8601.string(from: interval.end))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: "500"),
            ]
        )
        return rows.compactMap { dto in
            guard let id = dto.id, let ticker = dto.ticker else { return nil }
            let day = ISO8601.date(from: dto.entry_time)
                ?? ISO8601.date(from: dto.created_at)
                ?? Date()
            return CalendarEvent(
                id: CalendarEventID(id),
                ownerProfileID: ProfileID(profileID.rawValue),
                kind: .tradingDay,
                title: ticker,
                day: day,
                tradeIDs: [TradeID(id)],
                realizedPnL: DecimalParser.parseFlexible(dto.pnl).map { Money(amount: $0) },
                note: nil
            )
        }
    }

    func event(id: CalendarEventID) async throws -> CalendarEvent {
        let dto: TradeDTO.Trade = try await supabase.database.selectOne(
            TradeDTO.Trade.self,
            from: "trades",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        let trade = try TradeMapper.mapToDomain(dto)
        return CalendarEvent(
            id: id,
            ownerProfileID: trade.ownerProfileID,
            kind: .tradingDay,
            title: trade.symbol.ticker,
            day: trade.entryAt,
            tradeIDs: [trade.id],
            realizedPnL: trade.realizedPnL,
            note: nil
        )
    }

    func upsert(_ event: CalendarEvent) async throws -> CalendarEvent {
        event
    }

    func delete(id: CalendarEventID) async throws {
        _ = id
    }
}
