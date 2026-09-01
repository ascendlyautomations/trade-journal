import Foundation

/// Seeds ``DetailPresentationCache`` from `rpc_v1_feed_bootstrap` item payloads — no per-card REST.
enum FeedRpcProjectionSeeder {
    struct SeedResult: Sendable {
        var trades: Int = 0
        var posts: Int = 0
        var reels: Int = 0
        var achievements: Int = 0
        var authors: Int = 0
        var skipped: Int = 0
    }

    @MainActor
    static func seed(
        bootstrap: FeedBootstrapV1,
        detailCache: DetailPresentationCache
    ) -> SeedResult {
        var result = SeedResult()

        for (_, card) in bootstrap.data.authors {
            if seedAuthorCard(card, detailCache: detailCache) {
                result.authors += 1
            }
        }
        for (_, card) in bootstrap.data.story_authors {
            if seedAuthorCard(card, detailCache: detailCache) {
                result.authors += 1
            }
        }

        for row in bootstrap.data.items {
            let kind = FeedBootstrapApplier.feedItemKind(row.kind)
            switch kind {
            case .trade:
                if seedTrade(row, detailCache: detailCache) {
                    result.trades += 1
                } else {
                    result.skipped += 1
                }
            case .post:
                if seedProfilePost(row, detailCache: detailCache) {
                    result.posts += 1
                } else {
                    result.skipped += 1
                }
            case .reel:
                if seedReel(row, detailCache: detailCache) {
                    result.reels += 1
                } else {
                    result.skipped += 1
                }
            case .achievement:
                if seedAchievement(row, detailCache: detailCache) {
                    result.achievements += 1
                } else {
                    result.skipped += 1
                }
            case .story:
                result.skipped += 1
            }
        }

        #if DEBUG
        FeedRpcLoadProbe.recordProjectionSeed(result)
        #endif

        return result
    }

    // MARK: - Trade

    private static func seedTrade(_ row: FeedItemV1, detailCache: DetailPresentationCache) -> Bool {
        guard let tradeID = string(row.payload, keys: ["trade_id"]),
              !tradeID.isEmpty
        else { return false }

        let nested = object(row.payload["trades"]) ?? [:]
        var dto = TradeDTO.Trade()
        dto.id = tradeID
        dto.user_id = string(row.payload, keys: ["user_id"]) ?? row.author_id
        dto.ticker = string(nested, keys: ["ticker"])
        dto.direction = string(nested, keys: ["direction"])
        dto.public_description = string(nested, keys: ["public_description"])
        dto.pnl = flexibleNumber(row.payload["pnl"]) ?? flexibleNumber(nested["pnl"])
        dto.rr = flexibleNumber(row.payload["rr"]) ?? flexibleNumber(nested["rr"])
        dto.points = flexibleNumber(nested["points"])
        dto.image_url = string(row.payload, keys: ["image_url"])
        dto.mode = string(nested, keys: ["mode", "trade_mode"])
        dto.account_type = string(nested, keys: ["account_type"])
        dto.entry_time = string(nested, keys: ["entry_time"]) ?? row.created_at
        dto.exit_time = string(nested, keys: ["exit_time"])
        dto.entry_price = flexibleNumber(nested["entry_price"])
        dto.exit_price = flexibleNumber(nested["exit_price"])
        dto.created_at = row.created_at
        dto.is_public = boolValue(nested["is_public"]) ?? true

        guard let trade = try? TradeMapper.mapToDomain(dto) else { return false }
        detailCache.seed(trade)
        return true
    }

    // MARK: - Profile post

    private static func seedProfilePost(_ row: FeedItemV1, detailCache: DetailPresentationCache) -> Bool {
        guard let created = ISO8601.date(from: row.created_at) else { return false }
        let body = string(row.payload, keys: ["content", "body"]) ?? ""
        let imageURL = string(row.payload, keys: ["image_url"])
        let media: [MediaReference] = {
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [MediaReference(id: imageURL, kind: .image, altText: nil)]
        }()
        let post = Post(
            id: PostID(row.id),
            authorProfileID: ProfileID(row.author_id),
            body: body,
            media: media,
            visibility: .public,
            linkedTradeID: nil,
            isPinned: false,
            createdAt: created,
            updatedAt: created
        )
        detailCache.seed(post)
        return true
    }

    // MARK: - Reel

    private static func seedReel(_ row: FeedItemV1, detailCache: DetailPresentationCache) -> Bool {
        guard let created = ISO8601.date(from: row.created_at) else { return false }
        let videoURL = string(row.payload, keys: ["video_url"]) ?? ""
        let thumbURL = string(row.payload, keys: ["thumbnail_url"]) ?? videoURL
        guard !videoURL.isEmpty || !thumbURL.isEmpty else { return false }

        let tradeID = string(row.payload, keys: ["trade_id"]).flatMap { raw -> TradeID? in
            raw.isEmpty ? nil : TradeID(raw)
        }
        let duration = intValue(row.payload["duration_seconds"])

        let reel = Reel(
            id: ReelID(row.id),
            authorProfileID: ProfileID(row.author_id),
            video: MediaReference(id: videoURL.isEmpty ? thumbURL : videoURL, kind: .video, altText: nil),
            thumbnail: MediaReference(id: thumbURL, kind: .image, altText: nil),
            caption: string(row.payload, keys: ["caption"]),
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: duration,
            createdAt: created
        )
        detailCache.seed(reel)
        return true
    }

    // MARK: - Achievement

    private static func seedAchievement(_ row: FeedItemV1, detailCache: DetailPresentationCache) -> Bool {
        let achievementID = string(row.payload, keys: ["achievement_id"]) ?? row.id
        var dto: AchievementDTO.Achievement? = decodePayloadObject(
            object(row.payload["achievements"]) ?? [:],
            as: AchievementDTO.Achievement.self
        )
        if dto == nil, let nested = object(row.payload["achievements"]), !nested.isEmpty {
            dto = AchievementDTO.Achievement(
                id: achievementID,
                user_id: row.author_id,
                achievement_type: string(nested, keys: ["achievement_type"]),
                title: string(nested, keys: ["title"]),
                description: string(nested, keys: ["description"]),
                badge_key: string(nested, keys: ["badge_key"]),
                tier: string(nested, keys: ["tier"]),
                category: string(nested, keys: ["category"]),
                value_numeric: flexibleNumber(nested["value_numeric"]),
                value_text: string(nested, keys: ["value_text"]),
                currency: string(nested, keys: ["currency"]),
                account_type: string(nested, keys: ["account_type"]),
                account_name: nil,
                account_size: nil,
                account_id: nil,
                mode: string(nested, keys: ["mode"]),
                firm: string(nested, keys: ["firm"]),
                image_url: string(nested, keys: ["image_url"]),
                achieved_at: string(nested, keys: ["achieved_at"]) ?? row.created_at,
                created_at: string(nested, keys: ["created_at"]) ?? row.created_at,
                updated_at: string(nested, keys: ["updated_at"]),
                is_featured: boolValue(nested["is_featured"]),
                is_public: boolValue(nested["is_public"]) ?? true,
                sort_order: intValue(nested["sort_order"]),
                metadata: nil
            )
        }
        guard var dto else { return false }
        if dto.id == nil || dto.id?.isEmpty == true { dto.id = achievementID }
        if dto.user_id == nil || dto.user_id?.isEmpty == true { dto.user_id = row.author_id }

        guard let achievement = try? mapAchievementDTO(dto) else { return false }
        detailCache.seed(achievement)
        return true
    }

    private static func mapAchievementDTO(_ dto: AchievementDTO.Achievement) throws -> Achievement {
        guard let id = dto.id, !id.isEmpty else { throw MappingError.missingField("id") }
        guard let owner = dto.user_id, !owner.isEmpty else { throw MappingError.missingField("user_id") }

        let kindRaw = (dto.achievement_type ?? "milestone").lowercased()
        let kind: AchievementKind = {
            switch kindRaw {
            case "prop_firm_payout": return .propFirmPayout
            case "live_trading_payout", "payout": return .liveTradingPayout
            case "passed_eval", "passed_evals": return .passedEvaluation
            default: return .milestone
            }
        }()

        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : "Achievement"
        let amount = DecimalParser.parseFlexible(dto.value_numeric)
        let value = amount.map { Money(amount: $0, currencyCode: dto.currency ?? "USD") }
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

    // MARK: - Authors

    @MainActor
    private static func seedAuthorCard(_ card: AuthorCardV1, detailCache: DetailPresentationCache) -> Bool {
        let profileID = ProfileID(card.id)
        if detailCache.profile(id: profileID) != nil { return false }
        let username = card.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "user"
        let display = card.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        detailCache.seed(
            Profile(
                id: profileID,
                userID: UserID(card.id),
                username: username,
                displayName: (display?.isEmpty == false) ? display! : username,
                bio: nil,
                avatar: card.avatar_url.flatMap {
                    MediaReference(id: $0, kind: .image, altText: nil)
                },
                traderType: .futures,
                tradingStyle: nil,
                primaryMarket: nil,
                startedTradingAt: nil,
                isPrivate: false,
                isCreator: false,
                createdAt: .now
            )
        )
        return true
    }

    // MARK: - JSON helpers

    private static func object(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let dict) = value else { return nil }
        return dict
    }

    private static func string(_ payload: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if case .string(let value) = payload[key] {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func flexibleNumber(_ value: JSONValue?) -> FlexibleNumber? {
        guard let value else { return nil }
        switch value {
        case .number(let n): return FlexibleNumber(Decimal(n))
        case .string(let s):
            guard let parsed = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return FlexibleNumber(Decimal(parsed))
        case .bool(let b): return FlexibleNumber(Decimal(b ? 1 : 0))
        default: return nil
        }
    }

    private static func boolValue(_ value: JSONValue?) -> Bool? {
        guard let value else { return nil }
        switch value {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s):
            switch s.lowercased() {
            case "true", "t", "1": return true
            case "false", "f", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    private static func intValue(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private static func decodePayloadObject<T: Decodable>(
        _ object: [String: JSONValue],
        as type: T.Type
    ) -> T? {
        guard !object.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(JSONValue.object(object)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

#if DEBUG
nonisolated enum FeedRpcLoadProbe {
    nonisolated(unsafe) private(set) static var lastProjectionSeed: FeedRpcProjectionSeeder.SeedResult?
    nonisolated(unsafe) private(set) static var usedNetworkHydrate = false

    static func recordProjectionSeed(_ result: FeedRpcProjectionSeeder.SeedResult) {
        lastProjectionSeed = result
    }

    static func recordNetworkHydrate() {
        usedNetworkHydrate = true
    }

    static func resetForTesting() {
        lastProjectionSeed = nil
        usedNetworkHydrate = false
    }
}
#endif
