import Foundation

/// Canonical viewer-scoped social entity disk read/write — single merge + generation discipline.
nonisolated enum SocialEntityPersistedCacheCoordinator {
    enum MergeMode: String, Sendable {
        case replace
        case merge
    }

    enum SaveSource: String, Sendable {
        case feed
        case profile
        case detail
        case mutation
        case sessionTrade
        case share
    }

    private static let diskWriteQueue = DispatchQueue(label: "SocialEntityPersistedCache.disk", qos: .utility)

    // MARK: - Load (telemetry)

    static func loadTradeSummary(
        id: TradeID,
        viewerID: ProfileID,
        purpose: String
    ) -> TradeSummary? {
        if let summary = SocialEntityDiskCache.loadTradeSummary(id: id, viewerID: viewerID) {
            logHit(kind: .trade, id: id.rawValue, viewerID: viewerID, purpose: purpose)
            return summary
        }
        logMiss(kind: .trade, id: id.rawValue, viewerID: viewerID, purpose: purpose)
        return nil
    }

    static func loadPost(id: PostID, viewerID: ProfileID, purpose: String) -> Post? {
        if let post = SocialEntityDiskCache.loadPost(id: id, viewerID: viewerID) {
            logHit(kind: .post, id: id.rawValue, viewerID: viewerID, purpose: purpose)
            return post
        }
        logMiss(kind: .post, id: id.rawValue, viewerID: viewerID, purpose: purpose)
        return nil
    }

    static func loadReel(id: ReelID, viewerID: ProfileID, purpose: String) -> Reel? {
        if let reel = SocialEntityDiskCache.loadReel(id: id, viewerID: viewerID) {
            logHit(kind: .reel, id: id.rawValue, viewerID: viewerID, purpose: purpose)
            return reel
        }
        logMiss(kind: .reel, id: id.rawValue, viewerID: viewerID, purpose: purpose)
        return nil
    }

    static func loadAchievement(id: AchievementID, viewerID: ProfileID, purpose: String) -> Achievement? {
        if let achievement = SocialEntityDiskCache.loadAchievement(id: id, viewerID: viewerID) {
            logHit(kind: .achievement, id: id.rawValue, viewerID: viewerID, purpose: purpose)
            return achievement
        }
        logMiss(kind: .achievement, id: id.rawValue, viewerID: viewerID, purpose: purpose)
        return nil
    }

    static func loadProfile(id: ProfileID, viewerID: ProfileID, purpose: String) -> Profile? {
        if let profile = SocialEntityDiskCache.loadProfile(id: id, viewerID: viewerID) {
            logHit(kind: .profile, id: id.rawValue, viewerID: viewerID, purpose: purpose)
            return profile
        }
        logMiss(kind: .profile, id: id.rawValue, viewerID: viewerID, purpose: purpose)
        return nil
    }

    // MARK: - Save

    static func saveTradeSummary(
        _ summary: TradeSummary,
        viewerID: ProfileID,
        source: SaveSource,
        mergeMode: MergeMode = .replace
    ) {
        persist(
            viewerID: viewerID,
            kind: .trade,
            entityID: summary.id.rawValue,
            source: source,
            mergeMode: mergeMode
        ) { existing in
            guard let existing, mergeMode == .merge, let prior = existing.tradeSummary else {
                return makeRecord(viewerID: viewerID, kind: .trade, entityID: summary.id.rawValue, tradeSummary: summary)
            }
            let merged = SocialEntityPresentationMerge.tradeSummary(replace: prior, with: summary)
            return makeRecord(viewerID: viewerID, kind: .trade, entityID: summary.id.rawValue, tradeSummary: merged)
        }
    }

    static func savePost(
        _ post: Post,
        viewerID: ProfileID,
        source: SaveSource,
        mergeMode: MergeMode = .replace
    ) {
        persist(
            viewerID: viewerID,
            kind: .post,
            entityID: post.id.rawValue,
            source: source,
            mergeMode: mergeMode
        ) { existing in
            guard let existing, mergeMode == .merge, let prior = existing.post else {
                return makeRecord(viewerID: viewerID, kind: .post, entityID: post.id.rawValue, post: post)
            }
            let merged = SocialEntityPresentationMerge.post(replace: prior, with: post)
            return makeRecord(viewerID: viewerID, kind: .post, entityID: post.id.rawValue, post: merged)
        }
    }

    static func saveReel(
        _ reel: Reel,
        viewerID: ProfileID,
        source: SaveSource,
        mergeMode: MergeMode = .replace
    ) {
        persist(
            viewerID: viewerID,
            kind: .reel,
            entityID: reel.id.rawValue,
            source: source,
            mergeMode: mergeMode
        ) { existing in
            guard let existing, mergeMode == .merge, let prior = existing.reel else {
                return makeRecord(viewerID: viewerID, kind: .reel, entityID: reel.id.rawValue, reel: reel)
            }
            let merged = SocialEntityPresentationMerge.reel(replace: prior, with: reel)
            return makeRecord(viewerID: viewerID, kind: .reel, entityID: reel.id.rawValue, reel: merged)
        }
    }

    static func saveAchievement(
        _ achievement: Achievement,
        viewerID: ProfileID,
        source: SaveSource,
        mergeMode: MergeMode = .replace
    ) {
        persist(
            viewerID: viewerID,
            kind: .achievement,
            entityID: achievement.id.rawValue,
            source: source,
            mergeMode: mergeMode
        ) { existing in
            guard let existing, mergeMode == .merge, let prior = existing.achievement else {
                return makeRecord(
                    viewerID: viewerID,
                    kind: .achievement,
                    entityID: achievement.id.rawValue,
                    achievement: achievement
                )
            }
            let merged = SocialEntityPresentationMerge.achievement(replace: prior, with: achievement)
            return makeRecord(
                viewerID: viewerID,
                kind: .achievement,
                entityID: achievement.id.rawValue,
                achievement: merged
            )
        }
    }

    static func saveProfile(
        _ profile: Profile,
        viewerID: ProfileID,
        source: SaveSource,
        mergeMode: MergeMode = .replace
    ) {
        persist(
            viewerID: viewerID,
            kind: .profile,
            entityID: profile.id.rawValue,
            source: source,
            mergeMode: mergeMode
        ) { existing in
            guard let existing, mergeMode == .merge, let prior = existing.profile else {
                return makeRecord(viewerID: viewerID, kind: .profile, entityID: profile.id.rawValue, profile: profile)
            }
            let merged = SocialEntityPresentationMerge.profile(replace: prior, with: profile)
            return makeRecord(viewerID: viewerID, kind: .profile, entityID: profile.id.rawValue, profile: merged)
        }
    }

    /// List/card trade rows — never authoritative detail.
    static func saveTradeFromListRow(_ trade: Trade, viewerID: ProfileID, source: SaveSource) {
        saveTradeSummary(
            TradeSummaryMapper.summary(fromPartialListTrade: trade),
            viewerID: viewerID,
            source: source,
            mergeMode: .merge
        )
    }

    static func persistFeedTimelineEntities(entries: [FeedTimelineEntry], viewerID: ProfileID) {
        for entry in entries {
            switch entry {
            case .trade(_, let summary):
                saveTradeSummary(summary, viewerID: viewerID, source: .feed, mergeMode: .replace)
            case .post(_, let post):
                savePost(post, viewerID: viewerID, source: .feed, mergeMode: .replace)
            case .clip(_, let reel):
                saveReel(reel, viewerID: viewerID, source: .feed, mergeMode: .replace)
            case .achievement(_, let achievement):
                saveAchievement(achievement, viewerID: viewerID, source: .feed, mergeMode: .replace)
            }
        }
    }

    // MARK: - Remove

    static func removeTrade(id: TradeID, viewerID: ProfileID) {
        remove(kind: .trade, entityID: id.rawValue, viewerID: viewerID)
    }

    static func removePost(id: PostID, viewerID: ProfileID) {
        remove(kind: .post, entityID: id.rawValue, viewerID: viewerID)
    }

    static func removeReel(id: ReelID, viewerID: ProfileID) {
        remove(kind: .reel, entityID: id.rawValue, viewerID: viewerID)
    }

    static func removeAchievement(id: AchievementID, viewerID: ProfileID) {
        remove(kind: .achievement, entityID: id.rawValue, viewerID: viewerID)
    }

    static func clear(viewerID: ProfileID) {
        SocialEntityDiskCache.clear(viewerID: viewerID)
    }

    static func clearAll() {
        SocialEntityDiskCache.clearAll()
    }

    static func flushPendingDiskWritesForTesting() {
        diskWriteQueue.sync {}
    }

    // MARK: - Hydration telemetry

    static func logHydrationAvoided(type: SocialEntityDiskCache.EntityKind, id: String, purpose: String, oldPath: String) {
        #if DEBUG
        print(
            """
            [SocialEntity][HydrationAvoided] type=\(type.rawValue) id=\(id) purpose=\(purpose) oldPath=\(oldPath)
            """
        )
        #else
        _ = (type, id, purpose, oldPath)
        #endif
    }

    // MARK: - Internals

    private static func persist(
        viewerID: ProfileID,
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String,
        source: SaveSource,
        mergeMode: MergeMode,
        build: @escaping @Sendable (SocialEntityDiskCache.Record?) -> SocialEntityDiskCache.Record
    ) {
        let started = CFAbsoluteTimeGetCurrent()
        let generation = SocialEntityWriteGeneration.bump(viewerID: viewerID, kind: kind, entityID: entityID)
        let viewerCopy = viewerID
        let work: @Sendable () -> Void = {
            guard !SocialEntityWriteGeneration.isStale(
                viewerID: viewerCopy,
                kind: kind,
                entityID: entityID,
                generation: generation
            ) else { return }
            let existing = SocialEntityDiskCache.loadRecordForMerge(
                kind: kind,
                entityID: entityID,
                viewerID: viewerCopy
            )
            let record = build(existing)
            SocialEntityDiskCache.writeRecord(record)
            #if DEBUG
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            print(
                """
                [SocialEntity][Save] viewer=\(viewerCopy.rawValue) type=\(kind.rawValue) id=\(entityID) \
                source=\(source.rawValue) mergeMode=\(mergeMode.rawValue) elapsedMs=\(elapsedMs)
                """
            )
            #endif
        }
        if shouldWriteSynchronously {
            diskWriteQueue.sync(execute: work)
        } else {
            diskWriteQueue.async(execute: work)
        }
    }

    private static func remove(
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String,
        viewerID: ProfileID
    ) {
        _ = SocialEntityWriteGeneration.bump(viewerID: viewerID, kind: kind, entityID: entityID)
        let viewerCopy = viewerID
        diskWriteQueue.async {
            SocialEntityDiskCache.remove(kind: kind, entityID: entityID, viewerID: viewerCopy)
            #if DEBUG
            print("[SocialEntity][Remove] viewer=\(viewerCopy.rawValue) type=\(kind.rawValue) id=\(entityID)")
            #endif
        }
    }

    private static var shouldWriteSynchronously: Bool {
        if SocialEntityPersistedCacheTestHooks.forceSynchronousDiskWrites { return true }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        return false
    }

    private static func makeRecord(
        viewerID: ProfileID,
        kind: SocialEntityDiskCache.EntityKind,
        entityID: String,
        tradeSummary: TradeSummary? = nil,
        post: Post? = nil,
        reel: Reel? = nil,
        achievement: Achievement? = nil,
        profile: Profile? = nil
    ) -> SocialEntityDiskCache.Record {
        SocialEntityDiskCache.Record(
            schemaVersion: SocialEntityDiskCache.schemaVersion,
            viewerID: viewerID.rawValue,
            kind: kind,
            entityID: entityID,
            savedAt: Date(),
            lastAccessedAt: Date(),
            tradeSummary: tradeSummary,
            trade: nil,
            post: post,
            reel: reel,
            achievement: achievement,
            profile: profile
        )
    }

    private static func logHit(
        kind: SocialEntityDiskCache.EntityKind,
        id: String,
        viewerID: ProfileID,
        purpose: String
    ) {
        #if DEBUG
        print(
            """
            [SocialEntity][Hit] viewer=\(viewerID.rawValue) type=\(kind.rawValue) id=\(id) \
            source=disk purpose=\(purpose)
            """
        )
        #endif
    }

    private static func logMiss(
        kind: SocialEntityDiskCache.EntityKind,
        id: String,
        viewerID: ProfileID,
        purpose: String
    ) {
        #if DEBUG
        print(
            """
            [SocialEntity][Miss] viewer=\(viewerID.rawValue) type=\(kind.rawValue) id=\(id) purpose=\(purpose)
            """
        )
        #endif
    }
}
