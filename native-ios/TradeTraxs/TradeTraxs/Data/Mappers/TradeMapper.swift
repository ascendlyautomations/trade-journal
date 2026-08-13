import Foundation

nonisolated enum TradeMapper: DTOMapper {
    typealias DTO = TradeDTO.Trade
    typealias DomainModel = Trade

    static func mapToDomain(_ dto: DTO) throws -> Trade {
        guard let id = dto.id, !id.isEmpty else { throw MappingError.missingField("id") }
        guard let owner = dto.user_id, !owner.isEmpty else { throw MappingError.missingField("user_id") }

        let ticker = dto.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ticker.isEmpty else { throw MappingError.missingField("ticker") }

        let entryAt =
            ISO8601.date(from: dto.entry_time)
            ?? ISO8601.date(from: dto.created_at)
            ?? ISO8601.date(from: dto.date)
            ?? ISO8601.date(from: dto.trade_date)
        guard let entryAt else { throw MappingError.missingField("entry_time") }

        let side = mapSide(dto.direction)
        let mode = mapMode(dto.mode ?? dto.account_type)
        let quantity = DecimalParser.parseFlexible(dto.contracts) ?? 0
        let visibility: ContentVisibility = (dto.is_public == true) ? .public : .private
        let createdAt = ISO8601.date(from: dto.created_at) ?? entryAt
        let pnl = DecimalParser.parseFlexible(dto.pnl)

        let note = dto.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategy = dto.strategy?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID(owner),
            accountID: dto.account_id.map { TradingAccountID($0) },
            symbol: Symbol(ticker: ticker),
            side: side,
            mode: mode,
            quantity: quantity,
            entryPrice: DecimalParser.parseFlexible(dto.entry_price),
            exitPrice: DecimalParser.parseFlexible(dto.exit_price),
            entryAt: entryAt,
            exitAt: ISO8601.date(from: dto.exit_time),
            realizedPnL: pnl.map { Money(amount: $0, currencyCode: "USD") },
            riskReward: DecimalParser.parseFlexible(dto.rr),
            points: DecimalParser.parseFlexible(dto.points),
            sessionLabel: dto.session,
            visibility: visibility,
            publicCaption: dto.public_description,
            thumbnail: imageURL.flatMap { $0.isEmpty ? nil : MediaReference(id: $0, kind: .image, altText: nil) },
            // Longer preview for journal cards (Profile still line-limits).
            notePreview: note.flatMap { $0.isEmpty ? nil : String($0.prefix(360)) },
            strategy: strategy.flatMap { $0.isEmpty ? nil : $0 },
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func mapToDTO(_ domain: Trade) throws -> DTO {
        TradeDTO.Trade(
            id: domain.id.rawValue,
            user_id: domain.ownerProfileID.rawValue,
            account_id: domain.accountID?.rawValue,
            ticker: domain.symbol.ticker,
            direction: domain.side == .long ? "Long" : "Short",
            mode: domain.mode.rawValue,
            account_type: nil,
            contracts: FlexibleNumber(domain.quantity),
            entry_price: FlexibleNumber(domain.entryPrice),
            exit_price: FlexibleNumber(domain.exitPrice),
            entry_time: ISO8601.string(from: domain.entryAt),
            exit_time: domain.exitAt.map(ISO8601.string(from:)),
            pnl: FlexibleNumber(domain.realizedPnL?.amount),
            rr: FlexibleNumber(domain.riskReward),
            points: FlexibleNumber(domain.points),
            session: domain.sessionLabel,
            is_public: domain.visibility == .public,
            is_pinned: nil,
            public_description: domain.publicCaption,
            image_url: domain.thumbnail?.id,
            notes: domain.notePreview,
            created_at: ISO8601.string(from: domain.createdAt),
            date: ISO8601.string(from: domain.createdAt),
            trade_date: nil,
            account_name: nil,
            strategy: domain.strategy
        )
    }

    static func insertBody(from draft: TradeDraft, userID: UserID) -> TradeDTO.InsertBody {
        let now = ISO8601.string(from: Date())
        let tradeDate = TradingSessionLabel.easternTradeDateString(from: draft.entryAt)
        let session = draft.sessionLabel
            ?? TradingSessionLabel.session(from: draft.entryAt)
            ?? "NY"
        let modeLabel = draft.accountModeLabel ?? draft.mode.rawValue
        return TradeDTO.InsertBody(
            user_id: userID.rawValue,
            account_id: draft.accountID?.rawValue,
            account_name: draft.accountName,
            account_size: draft.accountSizeLabel,
            account_type: modeLabel,
            account_category: draft.accountCategoryLabel,
            ticker: draft.symbol.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            direction: draft.side == .long ? "Long" : "Short",
            mode: modeLabel,
            contracts: NSDecimalNumber(decimal: draft.quantity).doubleValue,
            entry_price: draft.entryPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            exit_price: draft.exitPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            entry_time: ISO8601.string(from: draft.entryAt),
            exit_time: draft.exitAt.map(ISO8601.string(from:)),
            trade_date: tradeDate,
            pnl: draft.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0,
            rr: draft.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue },
            points: draft.points.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
            session: session,
            strategy: Self.nilIfEmpty(draft.strategy),
            notes: Self.nilIfEmpty(draft.noteBody),
            image_url: Self.nilIfEmpty(draft.imageURL),
            is_public: draft.visibility == .public,
            public_description: draft.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            created_at: now,
            date: now
        )
    }

    /// Web edit save — preserve `created_at`; write denormalized account columns like insert.
    static func updateBody(from draft: TradeDraft, createdAt: Date) -> TradeDTO.UpdateBody {
        let tradeDate = TradingSessionLabel.easternTradeDateString(from: draft.entryAt)
        let session = draft.sessionLabel
            ?? TradingSessionLabel.session(from: draft.entryAt)
            ?? "NY"
        let modeLabel = draft.accountModeLabel ?? draft.mode.rawValue
        return TradeDTO.UpdateBody(
            account_id: draft.accountID?.rawValue,
            account_name: draft.accountName,
            account_size: draft.accountSizeLabel,
            account_type: modeLabel,
            account_category: draft.accountCategoryLabel,
            ticker: draft.symbol.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            direction: draft.side == .long ? "Long" : "Short",
            mode: modeLabel,
            contracts: NSDecimalNumber(decimal: draft.quantity).doubleValue,
            entry_price: draft.entryPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            exit_price: draft.exitPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
            entry_time: ISO8601.string(from: draft.entryAt),
            exit_time: draft.exitAt.map(ISO8601.string(from:)),
            trade_date: tradeDate,
            pnl: draft.realizedPnL.map { NSDecimalNumber(decimal: $0.amount).doubleValue } ?? 0,
            rr: draft.riskReward.map { NSDecimalNumber(decimal: $0).doubleValue },
            points: draft.points.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0,
            session: session,
            strategy: Self.nilIfEmpty(draft.strategy),
            notes: Self.nilIfEmpty(draft.noteBody),
            image_url: draft.imageURL,
            is_public: draft.visibility == .public,
            public_description: draft.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            created_at: ISO8601.string(from: createdAt)
        )
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mapSide(_ direction: String?) -> TradeSide {
        switch direction?.lowercased() {
        case "short", "sell", "s":
            return .short
        default:
            return .long
        }
    }

    private static func mapMode(_ raw: String?) -> TradeMode {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "backtest":
            return .backtest
        case "sim":
            return .sim
        case "replay":
            return .replay
        case "copy", "copy_traded", "copytraded":
            return .copyTraded
        default:
            return .live
        }
    }
}

nonisolated enum ProfileMapper: DTOMapper {
    typealias DTO = ProfileDTO.Profile
    typealias DomainModel = Profile

    static func mapToDomain(_ dto: DTO) throws -> Profile {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        let username = dto.username ?? id

        return Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: username,
            displayName: dto.name ?? username,
            bio: dto.bio,
            avatar: dto.avatar_url.flatMap { url in
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : MediaReference(id: trimmed, kind: .image, altText: nil)
            },
            traderType: TraderType.parse(dto.trader_type),
            tradingStyle: dto.trading_style,
            primaryMarket: dto.primary_market,
            startedTradingAt: ISO8601.date(from: dto.started_trading),
            isPrivate: dto.is_private ?? false,
            // Web Profile does not select `is_creator` (column absent in production).
            isCreator: false,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(timeIntervalSince1970: 0)
        )
    }

    static func mapToDTO(_ domain: Profile) throws -> DTO {
        ProfileDTO.Profile(
            id: domain.id.rawValue,
            username: domain.username,
            name: domain.displayName,
            bio: domain.bio,
            avatar_url: domain.avatar?.id,
            trader_type: domain.traderType?.rawValue,
            trading_style: domain.tradingStyle,
            primary_market: domain.primaryMarket,
            started_trading: domain.startedTradingAt.map(ISO8601.string(from:)),
            is_private: domain.isPrivate,
            is_creator: nil,
            is_pro: nil,
            subscription_status: nil,
            created_at: ISO8601.string(from: domain.createdAt),
            referral_code: nil
        )
    }
}

nonisolated enum MessageMapper: DTOMapper {
    typealias DTO = MessageDTO.Message
    typealias DomainModel = Message

    static func mapToDomain(_ dto: DTO) throws -> Message {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        guard let conversationID = dto.conversation_id else {
            throw MappingError.missingField("conversation_id")
        }
        let sender = dto.sender_profile_id ?? dto.sender_id
        guard let sender else { throw MappingError.missingField("sender_id") }
        guard let createdAt = ISO8601.date(from: dto.created_at) else {
            throw MappingError.missingField("created_at")
        }

        let tradeID = dto.trade_id.flatMap { raw -> TradeID? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : TradeID(trimmed)
        }
        let isTrade = (dto.type?.lowercased() == "trade") || tradeID != nil
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments: [MessageAttachment] = {
            if let tradeID {
                return [
                    MessageAttachment(
                        id: tradeID.rawValue,
                        media: MediaReference(id: tradeID.rawValue, kind: .file, altText: "Shared trade"),
                        tradeID: tradeID
                    ),
                ]
            }
            guard let imageURL, !imageURL.isEmpty else { return [] }
            return [
                MessageAttachment(
                    id: imageURL,
                    media: MediaReference(id: imageURL, kind: .image, altText: nil),
                    tradeID: nil
                ),
            ]
        }()
        let kind: MessageKind = {
            if isTrade { return .tradeShare }
            if let raw = dto.kind, let parsed = MessageKind(rawValue: raw) { return parsed }
            return attachments.isEmpty ? .text : .media
        }()

        return Message(
            id: MessageID(id),
            conversationID: ConversationID(conversationID),
            senderProfileID: ProfileID(sender),
            kind: kind,
            body: isTrade ? nil : (dto.body ?? dto.content),
            attachments: attachments,
            replyToMessageID: nil,
            createdAt: createdAt,
            isReadByViewer: dto.is_read ?? false
        )
    }

    static func mapToDTO(_ domain: Message) throws -> DTO {
        MessageDTO.Message(
            id: domain.id.rawValue,
            conversation_id: domain.conversationID.rawValue,
            sender_id: domain.senderProfileID.rawValue,
            sender_profile_id: domain.senderProfileID.rawValue,
            kind: domain.kind.rawValue,
            type: domain.kind == .tradeShare ? "trade" : nil,
            body: domain.body,
            content: domain.body,
            image_url: domain.kind == .tradeShare ? nil : domain.attachments.first?.media.id,
            trade_id: domain.attachments.first?.tradeID?.rawValue,
            created_at: ISO8601.string(from: domain.createdAt),
            is_read: domain.isReadByViewer
        )
    }
}

nonisolated enum FeedItemMapper: DTOMapper {
    typealias DTO = FeedDTO.Item
    typealias DomainModel = FeedItem

    static func mapToDomain(_ dto: DTO) throws -> FeedItem {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        let author = dto.author_profile_id ?? dto.user_id
        guard let author else { throw MappingError.missingField("user_id") }
        guard let createdAt = ISO8601.date(from: dto.created_at) else {
            throw MappingError.missingField("created_at")
        }

        return FeedItem(
            id: id,
            kind: FeedItemKind(rawValue: dto.kind ?? "") ?? .post,
            authorProfileID: ProfileID(author),
            createdAt: createdAt,
            tradeID: dto.trade_id.map { TradeID($0) },
            postID: dto.post_id.map { PostID($0) },
            reelID: dto.reel_id.map { ReelID($0) },
            storyID: nil,
            achievementID: nil,
            caption: dto.caption ?? dto.content,
            likeCount: dto.like_count ?? 0,
            commentCount: dto.comment_count ?? 0,
            viewerHasLiked: dto.viewer_has_liked ?? false
        )
    }

    static func mapToDTO(_ domain: FeedItem) throws -> DTO {
        FeedDTO.Item(
            id: domain.id,
            kind: domain.kind.rawValue,
            author_profile_id: domain.authorProfileID.rawValue,
            user_id: domain.authorProfileID.rawValue,
            created_at: ISO8601.string(from: domain.createdAt),
            trade_id: domain.tradeID?.rawValue,
            post_id: domain.postID?.rawValue,
            reel_id: domain.reelID?.rawValue,
            caption: domain.caption,
            content: domain.caption,
            like_count: domain.likeCount,
            comment_count: domain.commentCount,
            viewer_has_liked: domain.viewerHasLiked
        )
    }
}

nonisolated enum CalendarEventMapper: DTOMapper {
    typealias DTO = CalendarDTO.Event
    typealias DomainModel = CalendarEvent

    static func mapToDomain(_ dto: DTO) throws -> CalendarEvent {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        guard let title = dto.title else { throw MappingError.missingField("title") }
        guard let day = ISO8601.date(from: dto.day) else { throw MappingError.missingField("day") }

        return CalendarEvent(
            id: CalendarEventID(id),
            ownerProfileID: (dto.owner_profile_id ?? dto.user_id).map { ProfileID($0) },
            kind: CalendarEventKind(rawValue: dto.kind ?? "") ?? .tradingDay,
            title: title,
            day: day,
            tradeIDs: (dto.trade_ids ?? []).map { TradeID($0) },
            realizedPnL: nil,
            note: dto.note
        )
    }

    static func mapToDTO(_ domain: CalendarEvent) throws -> DTO {
        CalendarDTO.Event(
            id: domain.id.rawValue,
            owner_profile_id: domain.ownerProfileID?.rawValue,
            user_id: domain.ownerProfileID?.rawValue,
            kind: domain.kind.rawValue,
            title: domain.title,
            day: ISO8601.string(from: domain.day),
            trade_ids: domain.tradeIDs.map(\.rawValue),
            note: domain.note
        )
    }
}

nonisolated enum TradingAccountMapper {
    static func mapToDomain(_ dto: TradeDTO.Account) throws -> TradingAccount {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        guard let owner = dto.user_id else { throw MappingError.missingField("user_id") }
        // Web `accounts.name` is canonical; `account_name` is only the free-plan registry.
        guard let name = dto.name ?? dto.account_name, !name.isEmpty else {
            throw MappingError.missingField("name")
        }
        let sizeValue = DecimalParser.parseFlexible(dto.account_size)
            ?? DecimalParser.parseFlexible(dto.size)
        let category = mapCategory(dto.category ?? dto.account_type)
        let rules: PropFirmAccountRules? = {
            guard category == .propFirm else { return nil }
            return PropFirmAccountRules(
                consistencyPercent: DecimalParser.parseFlexible(dto.consistency),
                maxDrawdown: DecimalParser.parseFlexible(dto.max_drawdown),
                dailyDrawdown: DecimalParser.parseFlexible(dto.daily_drawdown),
                profitTarget: DecimalParser.parseFlexible(dto.profit_target),
                winningDaysRequired: DecimalParser.parseFlexible(dto.winning_days).map {
                    NSDecimalNumber(decimal: $0).intValue
                },
                winningDayThreshold: DecimalParser.parseFlexible(dto.winning_day_threshold),
                payoutDrawdownBehavior: dto.payout_drawdown_behavior
            )
        }()
        let number = dto.account_number?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TradingAccount(
            id: TradingAccountID(id),
            ownerProfileID: ProfileID(owner),
            name: name,
            category: category,
            mode: mapAccountMode(dto.mode),
            size: sizeValue.map { Money(amount: $0) },
            isActive: dto.is_active ?? true,
            canAddTrades: dto.can_add_trades ?? true,
            accountNumber: (number?.isEmpty == false) ? number : nil,
            note: (note?.isEmpty == false) ? note : nil,
            propFirmRules: rules
        )
    }

    /// Web insert/update wire strings for `accounts.category` / `accounts.mode`.
    static func webCategory(_ category: TradingAccountCategory) -> String {
        switch category {
        case .personal: return "Personal"
        case .broker: return "Broker"
        case .propFirm: return "Prop Firm"
        case .backtest: return "Backtest"
        }
    }

    static func webMode(_ mode: TradingAccountMode, category: TradingAccountCategory) -> String {
        switch category {
        case .backtest:
            return "backtest"
        case .propFirm:
            switch mode {
            case .funded: return "Funded"
            default: return "Eval"
            }
        case .personal, .broker:
            switch mode {
            case .sim: return "Sim"
            default: return "Live"
            }
        }
    }

    static func writeBody(
        ownerID: ProfileID?,
        draft: TradingAccountDraft,
        isActive: Bool? = nil,
        canAddTrades: Bool? = nil
    ) -> TradeDTO.AccountWriteBody {
        let rules = draft.category == .propFirm ? draft.propFirmRules : nil
        let size = draft.sizeDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = draft.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return TradeDTO.AccountWriteBody(
            user_id: ownerID?.rawValue,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            account_size: size.isEmpty ? nil : size,
            account_number: number.isEmpty ? nil : number,
            category: webCategory(draft.category),
            mode: webMode(draft.mode, category: draft.category),
            is_active: isActive,
            can_add_trades: canAddTrades,
            note: note.isEmpty ? nil : note,
            consistency: rules?.consistencyPercent.map { NSDecimalNumber(decimal: $0).doubleValue },
            max_drawdown: rules?.maxDrawdown.map { NSDecimalNumber(decimal: $0).doubleValue },
            daily_drawdown: rules?.dailyDrawdown.map { NSDecimalNumber(decimal: $0).doubleValue },
            profit_target: rules?.profitTarget.map { NSDecimalNumber(decimal: $0).doubleValue },
            winning_days: rules?.winningDaysRequired.map { Double($0) },
            winning_day_threshold: rules?.winningDayThreshold.map { NSDecimalNumber(decimal: $0).doubleValue }
        )
    }

    /// Web account mode strings — case-insensitive (`Funded` / `Evaluation` / `Live`).
    private static func mapAccountMode(_ raw: String?) -> TradingAccountMode {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "eval", "evaluation":
            return .evaluation
        case "funded":
            return .funded
        case "sim":
            return .sim
        case "backtest":
            return .backtest
        default:
            return .live
        }
    }

    /// Normalizes DB / web category strings (`Prop Firm`, `prop_firm`, `propFirm`).
    private static func mapCategory(_ raw: String?) -> TradingAccountCategory {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "propfirm", "prop":
            return .propFirm
        case "broker":
            return .broker
        case "backtest":
            return .backtest
        default:
            return .personal
        }
    }
}
