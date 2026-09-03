import Foundation

nonisolated struct DefaultTraderDailyCheckInRepository: TraderDailyCheckInRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func checkIn(for profileID: ProfileID, date: String) async throws -> TraderDailyCheckIn? {
        let key = Self.cacheKey(profileID: profileID, date: date)
        if let cached = cache.memory.value(forKey: key, as: TraderDailyCheckIn.self) {
            return cached
        }

        let rows: [TraderDailyCheckInDTO.Row] = try await supabase.database.select(
            TraderDailyCheckInDTO.Row.self,
            from: "trader_daily_check_ins",
            query: [
                SupabaseQuery.select(TraderDailyCheckInDTO.selectColumns),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                SupabaseQuery.eq("check_in_date", date),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first else { return nil }
        let mapped = try TraderDailyCheckInMapper.map(row)
        cache.memory.set(mapped, forKey: key)
        return mapped
    }

    func checkIns(
        for profileID: ProfileID,
        from startDate: String,
        to endDate: String
    ) async throws -> [TraderDailyCheckIn] {
        let rows: [TraderDailyCheckInDTO.Row] = try await supabase.database.select(
            TraderDailyCheckInDTO.Row.self,
            from: "trader_daily_check_ins",
            query: [
                SupabaseQuery.select(TraderDailyCheckInDTO.selectColumns),
                SupabaseQuery.eq("user_id", profileID.rawValue),
                URLQueryItem(name: "check_in_date", value: "gte.\(startDate)"),
                URLQueryItem(name: "check_in_date", value: "lte.\(endDate)"),
                URLQueryItem(name: "order", value: "check_in_date.desc"),
            ]
        )
        return try rows.map { try TraderDailyCheckInMapper.map($0) }
    }

    func upsert(
        _ draft: TraderDailyCheckInDraft,
        for profileID: ProfileID
    ) async throws -> TraderDailyCheckIn {
        if let message = TraderDailyCheckInValidation.validate(draft) {
            throw AppError.domain(.tradeValidation(.message(message)))
        }

        let body = TraderDailyCheckInMapper.upsertBody(draft: draft, profileID: profileID)
        let dto: TraderDailyCheckInDTO.Row = try await supabase.database.upsert(
            body,
            into: "trader_daily_check_ins",
            onConflict: "user_id,check_in_date",
            returning: TraderDailyCheckInDTO.Row.self,
            select: TraderDailyCheckInDTO.selectColumns
        )
        let mapped = try TraderDailyCheckInMapper.map(dto)
        cache.memory.set(mapped, forKey: Self.cacheKey(profileID: profileID, date: draft.checkInDate))
        return mapped
    }

    private static func cacheKey(profileID: ProfileID, date: String) -> String {
        "trader_daily_check_in:\(profileID.rawValue):\(date)"
    }
}
