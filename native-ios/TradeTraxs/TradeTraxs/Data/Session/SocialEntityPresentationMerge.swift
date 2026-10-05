import Foundation

/// Merge rules for cross-surface entity persistence — partial patches must not erase richer fields.
nonisolated enum SocialEntityPresentationMerge {
    static func tradeSummary(replace existing: TradeSummary, with incoming: TradeSummary) -> TradeSummary {
        var merged = existing
        merged.ownerProfileID = incoming.ownerProfileID
        merged.symbol = incoming.symbol
        merged.side = incoming.side
        merged.quantity = preferNonZeroQuantity(incoming.quantity, existing.quantity)
        merged.entryAt = incoming.entryAt
        merged.exitAt = incoming.exitAt ?? existing.exitAt
        merged.entryPrice = incoming.entryPrice ?? existing.entryPrice
        merged.exitPrice = incoming.exitPrice ?? existing.exitPrice
        merged.createdAt = incoming.createdAt
        merged.visibility = incoming.visibility
        merged.mode = incoming.mode
        merged.accountMode = incoming.accountMode ?? existing.accountMode
        merged.copyTradePublicModeSummary = preferNonEmpty(
            incoming.copyTradePublicModeSummary,
            existing.copyTradePublicModeSummary
        )
        merged.imageDisplayMode = incoming.imageDisplayMode
        merged.realizedPnL = incoming.realizedPnL ?? existing.realizedPnL
        merged.riskReward = incoming.riskReward ?? existing.riskReward
        merged.points = incoming.points ?? existing.points
        merged.publicCaption = preferNonEmpty(incoming.publicCaption, existing.publicCaption)
        merged.notePreview = preferNonEmpty(incoming.notePreview, existing.notePreview)
        merged.thumbnail = incoming.thumbnail ?? existing.thumbnail
        merged.publicAccountBadge = preferNonEmpty(incoming.publicAccountBadge, existing.publicAccountBadge)
        merged.durationSeconds = incoming.durationSeconds ?? existing.durationSeconds
        merged.durationText = preferNonEmpty(incoming.durationText, existing.durationText)
        return merged
    }

    static func post(replace existing: Post, with incoming: Post) -> Post {
        var merged = existing
        merged.authorProfileID = incoming.authorProfileID
        merged.visibility = incoming.visibility
        merged.isPinned = incoming.isPinned
        merged.createdAt = incoming.createdAt
        if incoming.updatedAt >= existing.updatedAt {
            merged.updatedAt = incoming.updatedAt
            if !incoming.body.isEmpty { merged.body = incoming.body }
            if !incoming.media.isEmpty { merged.media = incoming.media }
            merged.linkedTradeID = incoming.linkedTradeID ?? existing.linkedTradeID
        } else {
            if merged.body.isEmpty, !incoming.body.isEmpty { merged.body = incoming.body }
            if merged.media.isEmpty, !incoming.media.isEmpty { merged.media = incoming.media }
            merged.linkedTradeID = merged.linkedTradeID ?? incoming.linkedTradeID
        }
        return merged
    }

    static func reel(replace existing: Reel, with incoming: Reel) -> Reel {
        var merged = existing
        merged.authorProfileID = incoming.authorProfileID
        merged.visibility = incoming.visibility
        merged.createdAt = incoming.createdAt
        if !incoming.video.id.isEmpty { merged.video = incoming.video }
        merged.thumbnail = incoming.thumbnail ?? existing.thumbnail
        merged.linkedTradeID = incoming.linkedTradeID ?? existing.linkedTradeID
        merged.durationSeconds = incoming.durationSeconds ?? existing.durationSeconds
        merged.caption = preferNonEmpty(incoming.caption, existing.caption)
        return merged
    }

    static func achievement(replace existing: Achievement, with incoming: Achievement) -> Achievement {
        var merged = existing
        merged.ownerProfileID = incoming.ownerProfileID
        merged.kind = incoming.kind
        merged.tier = incoming.tier
        merged.isPublic = incoming.isPublic
        merged.isFeatured = incoming.isFeatured
        merged.sortOrder = incoming.sortOrder
        merged.achievedAt = incoming.achievedAt
        if !incoming.title.isEmpty { merged.title = incoming.title }
        merged.description = preferNonEmpty(incoming.description, existing.description)
        merged.value = incoming.value ?? existing.value
        merged.valueText = preferNonEmpty(incoming.valueText, existing.valueText)
        merged.firm = preferNonEmpty(incoming.firm, existing.firm)
        merged.accountID = incoming.accountID ?? existing.accountID
        merged.image = incoming.image ?? existing.image
        return merged
    }

    static func profile(replace existing: Profile, with incoming: Profile) -> Profile {
        existing.mergingCachedPresentation(with: incoming)
    }

    /// Presentation seed / list preview enriched with authoritative detail — incoming wins when present.
    static func trade(replace existing: Trade, with incoming: Trade) -> Trade {
        var merged = incoming
        merged.quantity = preferNonZeroQuantity(incoming.quantity, existing.quantity)
        merged.entryPrice = incoming.entryPrice ?? existing.entryPrice
        merged.exitPrice = incoming.exitPrice ?? existing.exitPrice
        merged.exitAt = incoming.exitAt ?? existing.exitAt
        merged.realizedPnL = incoming.realizedPnL ?? existing.realizedPnL
        merged.riskReward = incoming.riskReward ?? existing.riskReward
        merged.points = incoming.points ?? existing.points
        merged.durationSeconds = incoming.durationSeconds ?? existing.durationSeconds
        merged.durationText = preferNonEmpty(incoming.durationText, existing.durationText)
        merged.thumbnail = incoming.thumbnail ?? existing.thumbnail
        merged.notePreview = preferNonEmpty(incoming.notePreview, existing.notePreview)
        merged.publicCaption = preferNonEmpty(incoming.publicCaption, existing.publicCaption)
        merged.accountMode = incoming.accountMode ?? existing.accountMode
        merged.publicAccountBadge = preferNonEmpty(incoming.publicAccountBadge, existing.publicAccountBadge)
        merged.sessionLabel = preferNonEmpty(incoming.sessionLabel, existing.sessionLabel)
        merged.copyTrade = mergeCopyTradeMetadata(incoming: incoming.copyTrade, existing: existing.copyTrade)
        merged.imageDisplayMode = incoming.imageDisplayMode
        return merged
    }

    private static func mergeCopyTradeMetadata(
        incoming: CopyTradeJournalMetadata?,
        existing: CopyTradeJournalMetadata?
    ) -> CopyTradeJournalMetadata? {
        switch (incoming, existing) {
        case (nil, nil):
            return nil
        case (let inc?, nil):
            return inc
        case (nil, let ext?):
            return ext
        case (var inc?, let ext?):
            if inc.sourceAccountID == nil { inc.sourceAccountID = ext.sourceAccountID }
            if inc.copiedAccountIDs.isEmpty { inc.copiedAccountIDs = ext.copiedAccountIDs }
            if inc.copyTradingGroupID == nil { inc.copyTradingGroupID = ext.copyTradingGroupID }
            inc.participatingAccountModesByID.merge(ext.participatingAccountModesByID) { left, _ in left }
            return inc
        }
    }

    private static func preferNonZeroQuantity(_ incoming: Decimal, _ existing: Decimal) -> Decimal {
        if incoming > 0 { return incoming }
        if existing > 0 { return existing }
        return incoming
    }

    private static func preferNonEmpty(_ incoming: String?, _ existing: String?) -> String? {
        if let incoming, !incoming.isEmpty { return incoming }
        return existing
    }
}
