import Foundation

/// When a Clip becomes eligible for TradeTraxs-owned full-file persistent cache (Phase 12B).
nonisolated enum ClipVideoCacheFillPolicy {
    nonisolated static let minimumWatchedSeconds: Double = 2
    nonisolated static let minimumWatchedFraction: Double = 0.20

    /// Phase 12C — skip redundant full-file fill when AVPlayer already transferred most of a known asset.
    nonisolated static let duplicateRiskAvPlayerFraction: Double = 0.65

    /// Phase 12E.1 — do not start a separate 100% URLSession fill when AVPlayer already consumed a material fraction.
    nonisolated static let maximumAVPlayerFractionForFullCacheFill: Double = 0.40

    /// Phase 12E — defer full-file fill when AVPlayer is below duplicate-risk threshold at first eligibility.
    nonisolated static let deferReevaluationWatchedSeconds: Double = 4
    nonisolated static let deferFinalDecisionWatchedSeconds: Double = 6

    nonisolated enum DecisionStage: String, Sendable {
        case initial
        case reevaluation
        case final
    }

    nonisolated enum CacheFillDecision: Equatable, Sendable {
        case startFill
        case skipDuplicateRisk
        case pending
    }

    nonisolated enum CacheFillDecisionState: String, Equatable, Sendable {
        case notEligible
        case pending
        case fillStarted
        case skippedDuplicateRisk
        case cancelledDuplicateRisk
        case completed
    }

    nonisolated static func isEligible(
        watchedSeconds: Double,
        durationSeconds: Double?
    ) -> Bool {
        guard watchedSeconds > 0 else { return false }
        if watchedSeconds >= minimumWatchedSeconds { return true }
        guard let durationSeconds, durationSeconds > 0 else { return false }
        return (watchedSeconds / durationSeconds) >= minimumWatchedFraction
    }

    /// Uses only known asset size + observed AVPlayer bytes (no guessed percentages when bytes missing).
    nonisolated static func cacheFillDecision(
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64
    ) -> (decision: CacheFillDecision, reason: String, avPlayerObservedPercent: Double?) {
        guard let assetBytes = knownAssetBytes, assetBytes > 0 else {
            return (.startFill, "assetSizeUnknown_allowFill", nil)
        }
        guard avPlayerObservedBytes > 0 else {
            return (.startFill, "avPlayerBytesNotYetObserved", 0)
        }
        let fraction = Double(avPlayerObservedBytes) / Double(assetBytes)
        let percent = fraction
        if fraction >= duplicateRiskAvPlayerFraction {
            return (.skipDuplicateRisk, "avPlayerConsumedHighFractionOfAsset", percent)
        }
        if fraction >= maximumAVPlayerFractionForFullCacheFill {
            return (.skipDuplicateRisk, "avPlayerAlreadyConsumedMaterialFraction", percent)
        }
        return (.startFill, "avPlayerBelowMaterialFractionThreshold", percent)
    }

    nonisolated static func shouldCancelInFlightFillForObservedConsumption(
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64
    ) -> Bool {
        cacheFillDecision(
            knownAssetBytes: knownAssetBytes,
            avPlayerObservedBytes: avPlayerObservedBytes
        ).decision == .skipDuplicateRisk
    }

    nonisolated static func decisionStage(
        watchedSeconds: Double,
        durationSeconds: Double?
    ) -> DecisionStage? {
        guard isEligible(watchedSeconds: watchedSeconds, durationSeconds: durationSeconds) else { return nil }
        if watchedSeconds >= deferFinalDecisionWatchedSeconds { return .final }
        if watchedSeconds >= deferReevaluationWatchedSeconds { return .reevaluation }
        return .initial
    }

    /// Deferred window: below duplicate-risk threshold but not yet allowed to start fill.
    nonisolated static func deferredCacheFillDecision(
        watchedSeconds: Double,
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64,
        avPlayerObservedBytesWhenPendingBegan: Int64?,
        pendingBeganAtWatchedSeconds: Double?,
        durationSeconds: Double?
    ) -> (decision: CacheFillDecision, reason: String, avPlayerObservedPercent: Double?, stage: DecisionStage?) {
        let immediate = cacheFillDecision(
            knownAssetBytes: knownAssetBytes,
            avPlayerObservedBytes: avPlayerObservedBytes
        )
        if immediate.decision == .skipDuplicateRisk {
            return (
                immediate.decision,
                immediate.reason,
                immediate.avPlayerObservedPercent,
                decisionStage(watchedSeconds: watchedSeconds, durationSeconds: durationSeconds)
            )
        }

        guard let stage = decisionStage(watchedSeconds: watchedSeconds, durationSeconds: durationSeconds) else {
            return (.pending, "notYetEligible", immediate.avPlayerObservedPercent, nil)
        }

        if isRapidConsumptionTowardDuplicateRiskThreshold(
            knownAssetBytes: knownAssetBytes,
            avPlayerObservedBytes: avPlayerObservedBytes,
            avPlayerObservedBytesWhenPendingBegan: avPlayerObservedBytesWhenPendingBegan,
            pendingBeganAtWatchedSeconds: pendingBeganAtWatchedSeconds,
            watchedSeconds: watchedSeconds
        ) {
            return (.skipDuplicateRisk, "avPlayerRapidConsumptionTowardAsset", immediate.avPlayerObservedPercent, stage)
        }

        switch stage {
        case .initial, .reevaluation:
            return (.pending, "awaitingMoreAVPlayerEvidence", immediate.avPlayerObservedPercent, stage)
        case .final:
            guard knownAssetBytes != nil, (knownAssetBytes ?? 0) > 0 else {
                return (.pending, "awaitingAssetSizeForFinalDecision", immediate.avPlayerObservedPercent, stage)
            }
            if immediate.decision == .skipDuplicateRisk {
                return (immediate.decision, immediate.reason, immediate.avPlayerObservedPercent, stage)
            }
            return (.startFill, "deferWindowElapsedLowAVPlayerConsumption", immediate.avPlayerObservedPercent, stage)
        }
    }

    /// Skip fill when AVPlayer is gaining bytes quickly enough that duplicate-risk is likely before a fill completes.
    nonisolated static func isRapidConsumptionTowardDuplicateRiskThreshold(
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64,
        avPlayerObservedBytesWhenPendingBegan: Int64?,
        pendingBeganAtWatchedSeconds: Double?,
        watchedSeconds: Double
    ) -> Bool {
        guard let assetBytes = knownAssetBytes, assetBytes > 0 else { return false }
        guard avPlayerObservedBytes > 0 else { return false }
        let thresholdBytes = Int64((Double(assetBytes) * duplicateRiskAvPlayerFraction).rounded(.up))
        if avPlayerObservedBytes >= thresholdBytes { return true }

        guard let pendingStart = pendingBeganAtWatchedSeconds,
              let bytesAtPending = avPlayerObservedBytesWhenPendingBegan
        else { return false }
        let elapsed = watchedSeconds - pendingStart
        guard elapsed >= 0.75 else { return false }
        let gained = avPlayerObservedBytes - bytesAtPending
        guard gained > 0 else { return false }
        let rate = Double(gained) / elapsed
        guard rate > 0 else { return false }
        let remaining = Double(thresholdBytes - avPlayerObservedBytes)
        let secondsToThreshold = remaining / rate
        return secondsToThreshold <= 2.5
    }

    nonisolated static func estimatedDuplicateBytesIfFilled(
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64
    ) -> Int64? {
        guard let assetBytes = knownAssetBytes, assetBytes > 0 else { return nil }
        let overlap = min(avPlayerObservedBytes, assetBytes)
        return max(0, assetBytes - overlap)
    }
}
