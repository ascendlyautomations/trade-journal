import Foundation

nonisolated struct DefaultAchievementRepository: AchievementRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func achievements(
        for profileID: ProfileID,
        page: PageRequest
    ) async throws -> CursorPage<Achievement> {
        let rows: [AchievementDTO.Achievement] = try await supabase.database.select(
            AchievementDTO.Achievement.self,
            from: "achievements",
            query: SupabaseQuery.page(page, orderColumn: "achieved_at") + [
                SupabaseQuery.select("*"),
                SupabaseQuery.eq("user_id", profileID.rawValue),
            ]
        )
        let items = rows.compactMap(mapAchievement)
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: page.limit) { $0.achieved_at }
        )
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        let dto: AchievementDTO.Achievement = try await supabase.database.selectOne(
            AchievementDTO.Achievement.self,
            from: "achievements",
            query: [SupabaseQuery.select("*"), SupabaseQuery.eq("id", id.rawValue)]
        )
        guard let mapped = mapAchievement(dto) else {
            throw AppError.domain(.notFound(entity: "achievement", id: id.rawValue))
        }
        return mapped
    }

    func save(_ achievement: Achievement) async throws -> Achievement {
        struct Body: Encodable {
            var id: String
            var user_id: String
            var kind: String
            var title: String
            var tier: String
            var is_public: Bool
            var achieved_at: String
        }
        let body = Body(
            id: achievement.id.rawValue,
            user_id: achievement.ownerProfileID.rawValue,
            kind: achievement.kind.rawValue,
            title: achievement.title,
            tier: achievement.tier.rawValue,
            is_public: achievement.isPublic,
            achieved_at: ISO8601.string(from: achievement.achievedAt)
        )
        let dto: AchievementDTO.Achievement = try await supabase.database.insert(
            body,
            into: "achievements",
            returning: AchievementDTO.Achievement.self
        )
        guard let mapped = mapAchievement(dto) else { return achievement }
        return mapped
    }

    private func mapAchievement(_ dto: AchievementDTO.Achievement) -> Achievement? {
        guard let id = dto.id else { return nil }
        let owner = dto.owner_profile_id ?? dto.user_id
        guard let owner else { return nil }
        return Achievement(
            id: AchievementID(id),
            ownerProfileID: ProfileID(owner),
            kind: AchievementKind(rawValue: dto.kind ?? "") ?? .milestone,
            title: dto.title ?? "Achievement",
            tier: AchievementTier(rawValue: dto.tier ?? "") ?? .bronze,
            value: nil,
            accountID: nil,
            image: nil,
            isPublic: dto.is_public ?? true,
            isFeatured: false,
            achievedAt: ISO8601.date(from: dto.achieved_at) ?? Date()
        )
    }
}
