import Foundation

nonisolated enum ProfileTabBootstrapApplier {
    struct Applied: Sendable {
        var tradeSummaries: [TradeSummary]?
        /// Reels tab joined trade rows — not Profile tab summaries.
        var reelLinkedTrades: [Trade]?
        var posts: [Post]?
        var reels: [Reel]?
        var achievements: [Achievement]?
        var nextCursor: String?
        var tradeEngagement: [String: ProfileBootstrapV1.TradeEngagementWire]?
        var accountNames: [TradingAccountID: String]?
        var accountModes: [TradingAccountID: TradingAccountMode]?
        var accountSizes: [TradingAccountID: Decimal]?
    }

    nonisolated static func apply(
        _ bootstrap: ProfileTabBootstrapV1,
        tab: ProfileTabKind,
        ownerID: ProfileID
    ) -> Applied {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard !bootstrap.data.items.isEmpty,
              let payload = try? encoder.encode(JSONValue.array(bootstrap.data.items))
        else {
            return emptyApplied(tab: tab, bootstrap: bootstrap)
        }

        switch tab {
        case .trades:
            guard let wires = try? decoder.decode([DashboardTradeWireV1].self, from: payload) else {
                return emptyApplied(tab: tab, bootstrap: bootstrap)
            }
            var summaries: [TradeSummary] = []
            for row in wires {
                let dto = row.asTradeDTO(ownerID: ownerID.rawValue)
                if let trade = try? TradeMapper.mapToDomain(dto) {
                    summaries.append(TradeSummaryMapper.summary(fromPartialListTrade: trade))
                }
            }
            var names: [TradingAccountID: String] = [:]
            var modes: [TradingAccountID: TradingAccountMode] = [:]
            var sizes: [TradingAccountID: Decimal] = [:]
            for row in wires {
                guard let idRaw = row.account_id?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !idRaw.isEmpty
                else { continue }
                let accountID = TradingAccountID(idRaw)
                if let accountName = row.account_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !accountName.isEmpty
                {
                    names[accountID] = accountName
                }
                if let modeLabel = row.account_type ?? row.mode,
                   let parsed = TradingAccountMode.parseWireValue(modeLabel)
                {
                    modes[accountID] = parsed
                }
                if let size = row.account_size?.decimal {
                    sizes[accountID] = size
                }
            }
            #if DEBUG
            TradeSummaryProfileTelemetry.recordDecode(
                path: "v1.rpc.mappedSummary",
                tradeCount: summaries.count,
                skipped: wires.count - summaries.count
            )
            #endif
            return Applied(
                tradeSummaries: summaries,
                reelLinkedTrades: nil,
                nextCursor: bootstrap.data.next_cursor,
                tradeEngagement: bootstrap.data.engagement,
                accountNames: names,
                accountModes: modes,
                accountSizes: sizes
            )

        case .posts:
            guard let wires = try? decoder.decode([FeedDTO.ProfileWallPost].self, from: payload) else {
                return emptyApplied(tab: tab, bootstrap: bootstrap)
            }
            let posts = wires.compactMap(ProfileTabWireMapping.mapWallPost)
            return Applied(posts: posts, nextCursor: bootstrap.data.next_cursor)

        case .reels:
            guard let wires = try? decoder.decode([ProfileTabWireMapping.ReelWire].self, from: payload) else {
                return emptyApplied(tab: tab, bootstrap: bootstrap)
            }
            var reels: [Reel] = []
            var linkedTrades: [Trade] = []
            for wire in wires {
                guard let reel = ProfileTabWireMapping.mapReel(wire, ownerID: ownerID) else { continue }
                reels.append(reel)
                if let trade = ProfileTabWireMapping.mapLinkedTrade(from: wire, ownerID: ownerID) {
                    linkedTrades.append(trade)
                }
            }
            return Applied(
                tradeSummaries: nil,
                reelLinkedTrades: linkedTrades.isEmpty ? nil : linkedTrades,
                reels: reels,
                nextCursor: bootstrap.data.next_cursor
            )

        case .achievements:
            guard let wires = try? decoder.decode([AchievementDTO.Achievement].self, from: payload) else {
                return emptyApplied(tab: tab, bootstrap: bootstrap)
            }
            let achievements = wires.compactMap { ProfileTabWireMapping.mapAchievement($0) }
            return Applied(achievements: achievements, nextCursor: bootstrap.data.next_cursor)
        }
    }

    private static func emptyApplied(tab: ProfileTabKind, bootstrap: ProfileTabBootstrapV1) -> Applied {
        Applied(
            tradeSummaries: tab == .trades ? [] : nil,
            reelLinkedTrades: nil,
            posts: tab == .posts ? [] : nil,
            reels: tab == .reels ? [] : nil,
            achievements: tab == .achievements ? [] : nil,
            nextCursor: bootstrap.data.next_cursor,
            tradeEngagement: bootstrap.data.engagement
        )
    }
}

nonisolated enum ProfileTabWireMapping {
    struct ReelWire: Codable, Sendable {
        var id: String?
        var user_id: String?
        var caption: String?
        var video_url: String?
        var thumbnail_url: String?
        var duration_seconds: Int?
        var visibility: String?
        var trade_id: String?
        var created_at: String?
        /// Joined trade row when `rpc_v1_profile_tab_reels` embeds `trades`.
        var trades: ReelTradeJoinBox?
    }

    struct ReelTradeJoinWire: Codable, Sendable {
        var id: String?
        var public_description: String?
        var is_public: Bool?
        var ticker: String?
        var direction: String?
        var pnl: FlexibleNumber?
        var rr: FlexibleNumber?
    }

    /// PostgREST / RPC may return a single trade object or a one-element array.
    struct ReelTradeJoinBox: Codable, Sendable {
        var trades: [ReelTradeJoinWire]

        init(from decoder: Decoder) throws {
            if let single = try? ReelTradeJoinWire(from: decoder) {
                trades = [single]
                return
            }
            trades = try [ReelTradeJoinWire](from: decoder)
        }
    }

    static func mapWallPost(_ dto: FeedDTO.ProfileWallPost) -> Post? {
        guard let id = dto.id, let author = dto.user_id else { return nil }
        let created = ISO8601.date(from: dto.created_at) ?? Date()
        let media: [MediaReference] = {
            guard let url = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else { return [] }
            return [
                MediaReference(
                    id: url,
                    kind: .image,
                    altText: nil,
                    imagePresentation: dto.image_crop
                )
            ]
        }()
        return Post(
            id: PostID(id),
            authorProfileID: ProfileID(author),
            body: dto.content ?? "",
            media: media,
            visibility: .public,
            linkedTradeID: nil,
            isPinned: dto.is_pinned ?? false,
            createdAt: created,
            updatedAt: created
        )
    }

    static func mapReel(_ row: ReelWire, ownerID: ProfileID) -> Reel? {
        guard let reelID = row.id,
              let video = row.video_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !video.isEmpty else { return nil }
        let thumb = row.thumbnail_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibility: ContentVisibility = (row.visibility?.lowercased() == "private") ? .private : .public
        let caption = row.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Reel(
            id: ReelID(reelID),
            authorProfileID: ownerID,
            video: MediaReference(id: video, kind: .video, altText: nil),
            thumbnail: thumb.flatMap { $0.isEmpty ? nil : MediaReference(id: $0, kind: .image, altText: nil) },
            caption: (caption?.isEmpty == false) ? caption : nil,
            visibility: visibility,
            linkedTradeID: row.trade_id.map { TradeID($0) },
            durationSeconds: row.duration_seconds,
            createdAt: ISO8601.date(from: row.created_at) ?? Date()
        )
    }

    static func mapLinkedTrade(from row: ReelWire, ownerID: ProfileID) -> Trade? {
        let tradeIDRaw = row.trade_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tradeIDRaw.isEmpty else { return nil }
        guard let join = row.trades?.trades.first else { return nil }
        guard join.is_public != false else { return nil }

        var dto = TradeDTO.Trade()
        dto.id = join.id ?? tradeIDRaw
        dto.user_id = ownerID.rawValue
        dto.ticker = join.ticker
        dto.direction = join.direction
        dto.public_description = join.public_description
        dto.pnl = join.pnl
        dto.rr = join.rr
        dto.is_public = join.is_public ?? true
        dto.created_at = row.created_at
        return try? TradeMapper.mapToDomain(dto)
    }

    static func mapAchievement(_ dto: AchievementDTO.Achievement) -> Achievement? {
        guard let id = dto.id, !id.isEmpty,
              let owner = dto.user_id, !owner.isEmpty else { return nil }
        let kind = canonicalKind(dto.achievement_type)
        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : "Achievement"
        let currency = dto.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = DecimalParser.parseFlexible(dto.value_numeric)
        let value = amount.map {
            Money(amount: $0, currencyCode: (currency?.isEmpty == false) ? currency! : "USD")
        }
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
            image: ContentImagePresentation.mediaReference(url: imageURL, crop: dto.image_crop),
            isPublic: dto.is_public ?? true,
            isFeatured: dto.is_featured ?? false,
            sortOrder: dto.sort_order ?? 0,
            achievedAt: achievedAt
        )
    }

    private static func canonicalKind(_ raw: String?) -> AchievementKind {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "prop_firm_payout": return .propFirmPayout
        case "live_trading_payout", "payout": return .liveTradingPayout
        case "passed_eval", "passed_evals": return .passedEvaluation
        default:
            if t.contains("payout") { return .liveTradingPayout }
            return .milestone
        }
    }
}
