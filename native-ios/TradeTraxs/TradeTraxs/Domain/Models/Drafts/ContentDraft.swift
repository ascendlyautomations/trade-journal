import Foundation

/// Private composer snapshot. This is not a trade, post, achievement, or story.
nonisolated enum ContentDraftType: String, Codable, Sendable, CaseIterable {
    case trade
    case post
    case achievement
    case story

    var listLabel: String {
        switch self {
        case .trade: return "Trade"
        case .post: return "Post"
        case .achievement: return "Achievement"
        case .story: return "Story"
        }
    }
}

nonisolated struct ContentDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var userID: UserID
    var type: ContentDraftType
    var payload: ContentDraftPayload
    var createdAt: Date
    var updatedAt: Date

    var listTitle: String {
        ContentDraftPreview.title(type: type, payload: payload)
    }

    var updatedLabel: String {
        ContentDraftPreview.updatedLabel(updatedAt)
    }
}

nonisolated struct ContentDraftPayload: Codable, Equatable, Sendable {
    var version: Int = 1
    var trade: TradeComposerDraftState?
    var post: PostComposerDraftState?
    var achievement: AchievementComposerDraftState?
    var story: StoryComposerDraftState?

    init(
        version: Int = 1,
        trade: TradeComposerDraftState? = nil,
        post: PostComposerDraftState? = nil,
        achievement: AchievementComposerDraftState? = nil,
        story: StoryComposerDraftState? = nil
    ) {
        self.version = version
        self.trade = trade
        self.post = post
        self.achievement = achievement
        self.story = story
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        trade = try container.decodeIfPresent(TradeComposerDraftState.self, forKey: .trade)
        post = try container.decodeIfPresent(PostComposerDraftState.self, forKey: .post)
        achievement = try container.decodeIfPresent(AchievementComposerDraftState.self, forKey: .achievement)
        story = try container.decodeIfPresent(StoryComposerDraftState.self, forKey: .story)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(trade, forKey: .trade)
        try container.encodeIfPresent(post, forKey: .post)
        try container.encodeIfPresent(achievement, forKey: .achievement)
        try container.encodeIfPresent(story, forKey: .story)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case trade
        case post
        case achievement
        case story
    }

    var mediaPaths: [String] {
        var paths: [String] = []
        if let path = trade?.imageStoragePath { paths.append(path) }
        if let path = post?.imageStoragePath { paths.append(path) }
        if let path = achievement?.imageStoragePath { paths.append(path) }
        if let path = story?.imageStoragePath { paths.append(path) }
        if let path = story?.videoStoragePath { paths.append(path) }
        return paths
    }

    var isMeaningfullyEmpty: Bool {
        switch (trade, post, achievement, story) {
        case let (trade?, nil, nil, nil):
            return trade.isMeaningfullyEmpty
        case let (nil, post?, nil, nil):
            return post.isMeaningfullyEmpty
        case let (nil, nil, achievement?, nil):
            return achievement.isMeaningfullyEmpty
        case let (nil, nil, nil, story?):
            return story.isMeaningfullyEmpty
        default:
            return true
        }
    }
}

/// Add Trade form fields. Dates are ISO-8601 strings so the row survives the shared JSON decoder.
nonisolated struct TradeComposerDraftState: Codable, Equatable, Sendable {
    var accountID: String?
    var copyGroupID: String?
    var symbol: String = ""
    var side: String = TradeSide.long.rawValue
    var entryPrice: String = ""
    var exitPrice: String = ""
    var contracts: String = ""
    var pnl: String = ""
    var points: String = ""
    var rr: String = ""
    var entryAt: String?
    var exitAt: String?
    var includeExitTime: Bool = false
    var strategy: String = ""
    var notes: String = ""
    var timeframe: String = ""
    var customTimeframe: String = ""
    var newsEvent: Bool = false
    var confidence: Int = 0
    var emotion: String = ""
    var followedPlan: Bool = false
    var marketCondition: String = ""
    var psychologyNotes: String = ""
    var screenshotDisplayMode: String = TradeScreenshotDisplayMode.fit.rawValue
    var publicCaption: String = ""
    var shareToProfile: Bool = false
    var imageStoragePath: String?

    var isMeaningfullyEmpty: Bool {
        let texts = [
            symbol, entryPrice, exitPrice, contracts, pnl, points, rr,
            strategy, notes, timeframe, customTimeframe, emotion,
            marketCondition, psychologyNotes, publicCaption,
        ]
        let hasText = texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !hasText
            && copyGroupID == nil
            && imageStoragePath == nil
            && !includeExitTime
            && !newsEvent
            && !followedPlan
            && !shareToProfile
            && confidence == 0
            && side == TradeSide.long.rawValue
    }
}

nonisolated struct PostComposerDraftState: Codable, Equatable, Sendable {
    var body: String = ""
    var imageStoragePath: String?

    var isMeaningfullyEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageStoragePath == nil
    }
}

nonisolated struct AchievementComposerDraftState: Codable, Equatable, Sendable {
    var kind: String = AchievementKind.milestone.rawValue
    var title: String = ""
    var body: String = ""
    var payoutAmount: String = ""
    var achievedAt: String?
    var isPublic: Bool = true
    var accountID: String?
    var lockKind: Bool = false
    var imageStoragePath: String?
    var withdrawalLedgerEntryID: String?
    var withdrawalCycleID: String?

    var isMeaningfullyEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && payoutAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountID == nil
            && imageStoragePath == nil
            && withdrawalLedgerEntryID == nil
            && withdrawalCycleID == nil
            && kind == AchievementKind.milestone.rawValue
            && isPublic
            && !lockKind
    }
}

nonisolated struct StoryComposerDraftState: Codable, Equatable, Sendable {
    var mediaKind: String = "image"
    var imageStoragePath: String?
    var videoStoragePath: String?
    var contentType: String = "image/jpeg"
    var fileName: String = "story.jpg"
    var imageScale: Double = 1
    var imageOffsetWidth: Double = 0
    var imageOffsetHeight: Double = 0
    var textOverlays: [StoryTextOverlayRecord] = []

    var isMeaningfullyEmpty: Bool {
        imageStoragePath == nil
            && videoStoragePath == nil
            && !textOverlays.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }
}

nonisolated enum ContentDraftPreview {
    static func title(type: ContentDraftType, payload: ContentDraftPayload) -> String {
        switch type {
        case .trade:
            let symbol = payload.trade?.symbol.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return symbol.isEmpty ? "Trade" : "Trade • \(symbol)"
        case .post:
            if let snippet = quotedSnippet(payload.post?.body ?? "") {
                return "Post • \(snippet)"
            }
            return payload.post?.imageStoragePath == nil ? "Post" : "Post • Photo"
        case .achievement:
            let title = payload.achievement?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return "Achievement • \(title)" }
            if let kind = payload.achievement?.kind,
               let parsed = AchievementKind(rawValue: kind) {
                return "Achievement • \(CreateAchievementKindTitle.title(for: parsed))"
            }
            return "Achievement"
        case .story:
            if let snippet = quotedSnippet(payload.story?.textOverlays.map(\.text).joined(separator: " ") ?? "") {
                return "Story • \(snippet)"
            }
            if payload.story?.videoStoragePath != nil { return "Story • Video" }
            if payload.story?.imageStoragePath != nil { return "Story • Photo" }
            return "Story"
        }
    }

    static func updatedLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func quotedSnippet(_ text: String, limit: Int = 48) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit {
            return "\"\(collapsed)\""
        }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        let clipped = collapsed[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\"\(clipped)...\""
    }
}

/// Keeps achievement kind labels next to the draft preview without pulling the view model into the model layer.
nonisolated enum CreateAchievementKindTitle {
    static func title(for kind: AchievementKind) -> String {
        switch kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Evaluation"
        case .milestone: return "Milestone"
        }
    }
}

nonisolated enum ContentDraftDateCodec {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
