import Foundation

/// Merge rules for cross-surface entity persistence — partial patches must not erase richer fields.
nonisolated enum SocialEntityPresentationMerge {
    static func tradeSummary(replace existing: TradeSummary, with incoming: TradeSummary) -> TradeSummary {
        var merged = existing
        merged.ownerProfileID = incoming.ownerProfileID
        merged.symbol = incoming.symbol
        merged.side = incoming.side
        merged.quantity = incoming.quantity
        merged.entryAt = incoming.entryAt
        merged.exitAt = incoming.exitAt ?? existing.exitAt
        merged.createdAt = incoming.createdAt
        merged.visibility = incoming.visibility
        merged.mode = incoming.mode
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

    private static func preferNonEmpty(_ incoming: String?, _ existing: String?) -> String? {
        if let incoming, !incoming.isEmpty { return incoming }
        return existing
    }
}
