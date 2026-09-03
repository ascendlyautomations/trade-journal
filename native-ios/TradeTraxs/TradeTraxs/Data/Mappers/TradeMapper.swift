import Foundation

nonisolated enum TradeMapper: DTOMapper {
    typealias DTO = TradeDTO.Trade
    typealias DomainModel = Trade

    static func mapToDomain(_ dto: DTO) throws -> Trade {
        guard let id = dto.id, !id.isEmpty else { throw MappingError.missingField("id") }
        guard let owner = dto.user_id, !owner.isEmpty else { throw MappingError.missingField("user_id") }

        let tickerRaw = dto.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if tickerRaw.isEmpty {
            TradeMappingTelemetry.recordMissingTicker()
        }

        let entryAt =
            ISO8601.date(from: dto.entry_time)
            ?? ISO8601.date(from: dto.created_at)
            ?? ISO8601.date(from: dto.date)
            ?? ISO8601.date(from: dto.trade_date)
        guard let entryAt else { throw MappingError.missingField("entry_time") }

        let side = mapSide(dto.direction)
        let mode = mapMode(dto.trade_mode ?? dto.mode ?? dto.account_type)
        let quantity = DecimalParser.parseFlexible(dto.contracts) ?? 0
        let visibility: ContentVisibility = (dto.is_public == true) ? .public : .private
        let createdAt = ISO8601.date(from: dto.created_at) ?? entryAt
        let pnl = DecimalParser.parseFlexible(dto.pnl)

        let note = dto.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = dto.image_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategy = dto.strategy?.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationText = dto.duration_text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationSeconds = DecimalParser.parseFlexible(dto.duration_seconds).map {
            Int(truncating: NSDecimalNumber(decimal: $0))
        }
        let psychologyNotes = dto.psychology_notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exitEmotion = dto.exit_emotion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emotion = dto.emotion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let marketCondition = dto.market_condition?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeframe = dto.timeframe?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = DecimalParser.parseFlexible(dto.confidence).map {
            Int(truncating: NSDecimalNumber(decimal: $0))
        }
        let executionRating = DecimalParser.parseFlexible(dto.execution_rating).map {
            Int(truncating: NSDecimalNumber(decimal: $0))
        }
        let publicBadge = PublicTradeAccountBadge.label(
            tradeMode: dto.mode,
            accountType: dto.account_type
        )

        TradeMappingTelemetry.recordDecoded()
        return Trade(
            id: TradeID(id),
            ownerProfileID: ProfileID(owner),
            accountID: dto.account_id.map { TradingAccountID($0) },
            symbol: Symbol(ticker: tickerRaw),
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
            imageDisplayMode: TradeScreenshotDisplayMode.resolve(dto.image_display_mode),
            notePreview: note.flatMap { $0.isEmpty ? nil : String($0.prefix(360)) },
            notes: note.flatMap { $0.isEmpty ? nil : $0 },
            strategy: strategy.flatMap { $0.isEmpty ? nil : $0 },
            timeframe: timeframe.flatMap { $0.isEmpty ? nil : $0 },
            newsEvent: dto.news_event,
            confidence: confidence.flatMap { $0 > 0 ? $0 : nil },
            emotion: emotion.flatMap { $0.isEmpty ? nil : $0 },
            followedPlan: dto.followed_plan,
            marketCondition: marketCondition.flatMap { $0.isEmpty ? nil : $0 },
            psychologyNotes: psychologyNotes.flatMap { $0.isEmpty ? nil : $0 },
            exitEmotion: exitEmotion.flatMap { $0.isEmpty ? nil : $0 },
            executionRating: executionRating.flatMap { $0 > 0 ? $0 : nil },
            durationText: durationText.flatMap { $0.isEmpty ? nil : $0 },
            durationSeconds: durationSeconds.flatMap { $0 > 0 ? $0 : nil },
            reviewed: dto.reviewed,
            isInitialImport: dto.is_initial_import,
            importSource: mapImportSource(dto.import_source),
            importFingerprint: dto.import_fingerprint,
            publicAccountBadge: publicBadge,
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
            notes: domain.notes ?? domain.notePreview,
            created_at: ISO8601.string(from: domain.createdAt),
            date: ISO8601.string(from: domain.createdAt),
            trade_date: nil,
            account_name: nil,
            strategy: domain.strategy,
            duration_seconds: domain.durationSeconds.map { FlexibleNumber(Decimal($0)) },
            duration_text: domain.durationText,
            trade_mode: domain.mode == .copyTraded ? "copy_traded" : domain.mode.rawValue,
            confidence: domain.confidence.map { FlexibleNumber(Decimal($0)) },
            emotion: domain.emotion,
            followed_plan: domain.followedPlan,
            market_condition: domain.marketCondition,
            timeframe: domain.timeframe,
            news_event: domain.newsEvent,
            psychology_notes: domain.psychologyNotes,
            exit_emotion: domain.exitEmotion,
            execution_rating: domain.executionRating.map { FlexibleNumber(Decimal($0)) },
            image_display_mode: domain.imageDisplayMode.rawValue,
            reviewed: domain.reviewed,
            is_initial_import: domain.isInitialImport,
            import_source: domain.importSource?.rawValue,
            import_fingerprint: domain.importFingerprint
        )
    }

    private static func mapImportSource(_ raw: String?) -> TradeImportSource? {
        guard let raw else { return nil }
        return TradeImportSource(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func durationFields(from draft: TradeDraft) -> (seconds: Int?, text: String?) {
        if let seconds = draft.durationSeconds, let text = draft.durationText {
            return (seconds, text)
        }
        if let computed = TradeHoldDuration.compute(entryAt: draft.entryAt, exitAt: draft.exitAt) {
            return (computed.seconds, computed.text)
        }
        return (nil, nil)
    }

    private static func shouldMarkReviewed(previous: Trade?) -> Bool {
        guard let previous else { return false }
        return previous.isInitialImport == true && previous.reviewed != true
    }

    private static func psychologyDouble(from confidence: Int?) -> Double? {
        guard let confidence, confidence > 0 else { return nil }
        return Double(confidence)
    }

    private static func psychologyFields(from draft: TradeDraft) -> (
        confidence: Double?,
        emotion: String?,
        followedPlan: Bool,
        marketCondition: String?,
        timeframe: String?,
        newsEvent: Bool,
        psychologyNotes: String?,
        exitEmotion: String?,
        executionRating: Int?
    ) {
        (
            confidence: psychologyDouble(from: draft.confidence),
            emotion: nilIfEmpty(draft.emotion),
            followedPlan: draft.followedPlan,
            marketCondition: nilIfEmpty(draft.marketCondition),
            timeframe: nilIfEmpty(draft.timeframe),
            newsEvent: draft.newsEvent,
            psychologyNotes: nilIfEmpty(draft.psychologyNotes),
            exitEmotion: nilIfEmpty(draft.exitEmotion),
            executionRating: draft.executionRating.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    static func insertBody(from draft: TradeDraft, userID: UserID) -> TradeDTO.InsertBody {
        let now = ISO8601.string(from: Date())
        let tradeDate = TradingSessionLabel.easternTradeDateString(from: draft.entryAt)
        let session = draft.sessionLabel
            ?? TradingSessionLabel.session(from: draft.entryAt)
            ?? "NY"
        let modeLabel = draft.accountModeLabel ?? draft.mode.rawValue
        let isPublic = draft.visibility == .public
        let accountFields = PublicAccountPrivacy.sanitizedTradeAccountFieldsForSave(
            accountName: draft.accountName,
            accountSize: draft.accountSizeLabel,
            accountNumber: draft.ownerAccountNumber,
            category: draft.ownerAccountCategory,
            mode: draft.ownerAccountMode,
            isPublic: isPublic
        )
        let psychology = psychologyFields(from: draft)
        let duration = durationFields(from: draft)
        return TradeDTO.InsertBody(
            user_id: userID.rawValue,
            account_id: draft.accountID?.rawValue,
            account_name: accountFields.accountName,
            account_size: accountFields.accountSize,
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
            confidence: psychology.confidence,
            emotion: psychology.emotion,
            followed_plan: psychology.followedPlan,
            market_condition: psychology.marketCondition,
            timeframe: psychology.timeframe,
            news_event: psychology.newsEvent,
            psychology_notes: psychology.psychologyNotes,
            exit_emotion: psychology.exitEmotion,
            execution_rating: psychology.executionRating,
            duration_seconds: duration.seconds,
            duration_text: duration.text,
            image_display_mode: draft.imageDisplayMode.rawValue,
            created_at: now,
            date: now,
            is_initial_import: nil,
            import_source: draft.importSource?.rawValue,
            import_fingerprint: draft.importFingerprint
        )
    }

    /// Web edit save — preserve `created_at`; write denormalized account columns like insert.
    static func updateBody(from draft: TradeDraft, createdAt: Date, previous: Trade? = nil) -> TradeDTO.UpdateBody {
        let tradeDate = TradingSessionLabel.easternTradeDateString(from: draft.entryAt)
        let session = draft.sessionLabel
            ?? TradingSessionLabel.session(from: draft.entryAt)
            ?? "NY"
        let modeLabel = draft.accountModeLabel ?? draft.mode.rawValue
        let isPublic = draft.visibility == .public
        let accountFields = PublicAccountPrivacy.sanitizedTradeAccountFieldsForSave(
            accountName: draft.accountName,
            accountSize: draft.accountSizeLabel,
            accountNumber: draft.ownerAccountNumber,
            category: draft.ownerAccountCategory,
            mode: draft.ownerAccountMode,
            isPublic: isPublic
        )
        let psychology = psychologyFields(from: draft)
        let duration = durationFields(from: draft)
        let markReviewed = shouldMarkReviewed(previous: previous)
        return TradeDTO.UpdateBody(
            account_id: draft.accountID?.rawValue,
            account_name: accountFields.accountName,
            account_size: accountFields.accountSize,
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
            confidence: psychology.confidence,
            emotion: psychology.emotion,
            followed_plan: psychology.followedPlan,
            market_condition: psychology.marketCondition,
            timeframe: psychology.timeframe,
            news_event: psychology.newsEvent,
            psychology_notes: psychology.psychologyNotes,
            exit_emotion: psychology.exitEmotion,
            execution_rating: psychology.executionRating,
            duration_seconds: duration.seconds,
            duration_text: duration.text,
            image_display_mode: draft.imageDisplayMode.rawValue,
            reviewed: markReviewed ? true : nil,
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
        let displayName = dto.name ?? username

        return Profile(
            id: ProfileID(id),
            userID: UserID(id),
            username: username,
            displayName: displayName,
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
        let audioURL = dto.audio_url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isVoice = dto.type?.lowercased() == "voice" || !(audioURL?.isEmpty ?? true)
        let voiceDuration = dto.audio_duration_ms.map { Double($0) / 1_000.0 }
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
            if let audioURL, !audioURL.isEmpty {
                return [
                    MessageAttachment(
                        id: audioURL,
                        media: MediaReference(id: audioURL, kind: .audio, altText: nil),
                        tradeID: nil,
                        durationSeconds: voiceDuration
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
            if isVoice { return .voice }
            if StoryReplyMessageSupport.isStoryReply(
                type: dto.type,
                content: dto.body ?? dto.content
            ) {
                return .storyReply
            }
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
            showInAccountDropdowns: dto.show_in_account_dropdowns ?? true,
            customPublicStatus: normalizedOptionalText(dto.custom_public_status),
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

    private static func normalizedOptionalText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum AccountPayoutEntryMapper {
    static func mapToDomain(_ dto: TradeDTO.AccountPayoutEntryRow) throws -> AccountPayoutEntry {
        guard let id = dto.id else { throw MappingError.missingField("id") }
        guard let accountID = dto.account_id else { throw MappingError.missingField("account_id") }
        guard let amount = DecimalParser.parseFlexible(dto.amount) else {
            throw MappingError.missingField("amount")
        }
        guard let payoutDateRaw = dto.payout_date,
              let payoutDate = ISO8601.date(from: payoutDateRaw)
                ?? ISO8601.date(from: "\(payoutDateRaw)T00:00:00Z") else {
            throw MappingError.missingField("payout_date")
        }
        let note = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AccountPayoutEntry(
            id: AccountPayoutEntryID(id),
            accountID: TradingAccountID(accountID),
            amount: Money(amount: amount, currencyCode: "USD"),
            payoutDate: payoutDate,
            note: (note?.isEmpty == false) ? note : nil
        )
    }

    static func writeBody(
        ownerID: ProfileID,
        accountID: TradingAccountID,
        draft: AccountPayoutEntryDraft
    ) throws -> TradeDTO.AccountPayoutEntryWriteBody {
        let amountDigits = draft.amountDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: amountDigits), amount > 0 else {
            throw AppError.unknown(message: "Enter a payout amount greater than zero.")
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return TradeDTO.AccountPayoutEntryWriteBody(
            account_id: accountID.rawValue,
            user_id: ownerID.rawValue,
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            payout_date: formatter.string(from: draft.payoutDate),
            note: note.isEmpty ? nil : note
        )
    }

    static func updateBody(from draft: AccountPayoutEntryDraft) throws -> TradeDTO.AccountPayoutEntryUpdateBody {
        let amountDigits = draft.amountDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: amountDigits), amount > 0 else {
            throw AppError.unknown(message: "Enter a payout amount greater than zero.")
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return TradeDTO.AccountPayoutEntryUpdateBody(
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            payout_date: formatter.string(from: draft.payoutDate),
            note: note.isEmpty ? nil : note
        )
    }
}

nonisolated enum ProfileAccountInsightMapper {
    struct WireAccount: Decodable, Sendable {
        var id: String
        var name: String?
        var category: String?
        var type: String?
        var custom_status: String?
        var payout_total: FlexibleNumber?
        var payouts: [WirePayout]?
    }

    struct WirePayout: Decodable, Sendable {
        var id: String
        var amount: FlexibleNumber?
        var payout_date: String?
        var note: String?
    }

    struct WireEnvelope: Decodable, Sendable {
        struct Meta: Decodable, Sendable {
            var contract_version: Int?
            var found: Bool?
            var can_view: Bool?
            var is_own: Bool?
        }

        struct DataBlock: Decodable, Sendable {
            var accounts: [WireAccount]?
        }

        var meta: Meta?
        var data: DataBlock?
    }

    static func mapAccounts(from data: Data) throws -> [ProfileAccountInsight] {
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
        guard envelope.meta?.found != false else { return [] }
        guard envelope.meta?.can_view != false else { return [] }
        let rows = envelope.data?.accounts ?? []
        return rows.compactMap { row in
            guard !row.id.isEmpty else { return nil }
            let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let category = mapCategory(row.category)
            let mode = mapMode(row.type)
            let safeName = PublicAccountPrivacy.publicSafeAccountName(
                rawName: name,
                accountNumber: nil,
                category: category,
                mode: mode
            )
            guard !safeName.isEmpty else { return nil }
            let payouts: [AccountPayoutEntry] = (row.payouts ?? []).compactMap { payout in
                guard let amount = DecimalParser.parseFlexible(payout.amount) else { return nil }
                guard let dateRaw = payout.payout_date,
                      let date = ISO8601.date(from: dateRaw)
                        ?? ISO8601.date(from: "\(dateRaw)T00:00:00Z") else { return nil }
                let note = payout.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                return AccountPayoutEntry(
                    id: AccountPayoutEntryID(payout.id),
                    accountID: TradingAccountID(row.id),
                    amount: Money(amount: amount, currencyCode: "USD"),
                    payoutDate: date,
                    note: (note?.isEmpty == false) ? note : nil
                )
            }
            let total = DecimalParser.parseFlexible(row.payout_total)
                ?? payouts.reduce(Decimal.zero) { $0 + $1.amount.amount }
            return ProfileAccountInsight(
                id: TradingAccountID(row.id),
                name: safeName,
                category: category,
                mode: mode,
                customStatus: normalizedOptionalText(row.custom_status),
                payoutTotal: Money(amount: total, currencyCode: "USD"),
                payouts: payouts
            )
        }
    }

    private static func normalizedOptionalText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mapCategory(_ raw: String?) -> TradingAccountCategory {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "propfirm", "prop": return .propFirm
        case "broker": return .broker
        case "backtest": return .backtest
        default: return .personal
        }
    }

    private static func mapMode(_ raw: String?) -> TradingAccountMode {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "eval", "evaluation": return .evaluation
        case "funded": return .funded
        case "sim": return .sim
        case "backtest": return .backtest
        default: return .live
        }
    }
}
