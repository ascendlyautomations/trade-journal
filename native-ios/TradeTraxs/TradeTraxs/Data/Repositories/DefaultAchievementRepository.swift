import Foundation
import OSLog

nonisolated struct DefaultAchievementRepository: AchievementRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    /// Web multi-column order: featured → achieved_at → sort_order.
    private static let profileOrder =
        "is_featured.desc,achieved_at.desc.nullslast,sort_order.asc.nullslast"

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        // Web Profile loads the full list (no range). Use a high ceiling for parity.
        let limit = max(page.limit, 500)
        var query: [URLQueryItem] = [
            SupabaseQuery.select(publicOnly ? AchievementDTO.publicSelect : AchievementDTO.ownerSelect),
            SupabaseQuery.eq("user_id", profileID.rawValue),
            URLQueryItem(name: "order", value: Self.profileOrder),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if publicOnly {
            query.append(SupabaseQuery.eq("is_public", "true"))
        }
        if let cursor = page.cursor, !cursor.isEmpty {
            query.append(URLQueryItem(name: "achieved_at", value: "lt.\(cursor)"))
        }

        let rows: [AchievementDTO.Achievement] = try await supabase.database.select(
            AchievementDTO.Achievement.self,
            from: "achievements",
            query: query
        )
        let items = rows.compactMap { dto -> Achievement? in
            do {
                return try Self.mapAchievement(dto)
            } catch {
                AppLog.networking.error(
                    "Skipping achievement \(dto.id ?? "unknown", privacy: .public) — \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        return CursorPage(
            items: items,
            nextCursor: SupabaseQuery.nextCursor(items: rows, limit: limit) { $0.achieved_at }
        )
    }

    func achievement(id: AchievementID) async throws -> Achievement {
        let dto: AchievementDTO.Achievement = try await supabase.database.selectOne(
            AchievementDTO.Achievement.self,
            from: "achievements",
            query: [
                SupabaseQuery.select(AchievementDTO.ownerSelect),
                SupabaseQuery.eq("id", id.rawValue),
            ]
        )
        return try Self.mapAchievement(dto)
    }

    func save(_ achievement: Achievement) async throws -> Achievement {
        struct Body: Encodable {
            var id: String
            var user_id: String
            var achievement_type: String
            var title: String
            var tier: String
            var is_public: Bool
            var is_featured: Bool
            var achieved_at: String
        }
        let body = Body(
            id: achievement.id.rawValue,
            user_id: achievement.ownerProfileID.rawValue,
            achievement_type: achievement.kind.rawValue,
            title: achievement.title,
            tier: achievement.tier.rawValue,
            is_public: achievement.isPublic,
            is_featured: achievement.isFeatured,
            achieved_at: ISO8601.string(from: achievement.achievedAt)
        )
        let dto: AchievementDTO.Achievement = try await supabase.database.insert(
            body,
            into: "achievements",
            returning: AchievementDTO.Achievement.self
        )
        return (try? Self.mapAchievement(dto)) ?? achievement
    }

    // MARK: - Mapping (web achievement_type → Domain)

    private static func mapAchievement(_ dto: AchievementDTO.Achievement) throws -> Achievement {
        guard let id = dto.id, !id.isEmpty else { throw MappingError.missingField("id") }
        guard let owner = dto.user_id, !owner.isEmpty else { throw MappingError.missingField("user_id") }

        let kind = canonicalKind(dto.achievement_type)
        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : defaultTitle(for: kind)

        let currency = dto.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = DecimalParser.parseFlexible(dto.value_numeric)
        let value = amount.map { Money(amount: $0, currencyCode: (currency?.isEmpty == false) ? currency! : "USD") }

        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let achievedAt =
            ISO8601.date(from: dto.achieved_at)
            ?? ISO8601.date(from: dto.created_at)
            ?? Date()

        return Achievement(
            id: AchievementID(id),
            ownerProfileID: ProfileID(owner),
            kind: kind,
            title: resolvedTitle,
            description: dto.description,
            tier: AchievementTier(rawValue: (dto.tier ?? "").lowercased()) ?? .bronze,
            value: value,
            valueText: dto.value_text,
            firm: dto.firm,
            accountID: dto.account_id.map { TradingAccountID($0) },
            image: imageURL.flatMap { $0.isEmpty ? nil : MediaReference(id: $0, kind: .image, altText: nil) },
            isPublic: dto.is_public ?? true,
            isFeatured: dto.is_featured ?? false,
            sortOrder: dto.sort_order ?? 0,
            achievedAt: achievedAt
        )
    }

    /// Mirrors web `canonicalAchievementType`.
    private static func canonicalKind(_ raw: String?) -> AchievementKind {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "prop_firm_payout":
            return .propFirmPayout
        case "live_trading_payout", "payout":
            return .liveTradingPayout
        case "passed_eval", "passed_evals":
            return .passedEvaluation
        case "milestone", "milestones":
            return .milestone
        default:
            if t.contains("payout") { return .liveTradingPayout }
            return .milestone
        }
    }

    private static func defaultTitle(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Eval"
        case .milestone: return "Milestone"
        }
    }
}
