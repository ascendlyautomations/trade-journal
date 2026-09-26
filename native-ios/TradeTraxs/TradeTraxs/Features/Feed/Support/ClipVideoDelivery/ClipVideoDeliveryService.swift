import Foundation

nonisolated enum ClipVideoDeliveryRole: Sendable {
    case active
    case prefetch
    case detail
}

nonisolated enum ClipVideoPlaybackSource: Sendable, Equatable {
    case persistentDisk
    case network
}

/// Resolves reel playback URLs; full-file cache fill is decoupled from playback (Phase 12B).
actor ClipVideoDeliveryService {
    private struct ClipState {
        var clipID: String
        var remoteURL: URL
        var urlIdentity: String
        var isActiveConsumer: Bool
        var prefetchPrepared: Bool
        var watchedSeconds: Double = 0
        var durationSeconds: Double?
        var fillEligible: Bool = false
        var fillStarted: Bool = false
        var fillSkippedDuplicateRisk: Bool = false
        var cacheDecisionState: ClipVideoCacheFillPolicy.CacheFillDecisionState = .notEligible
        var pendingBeganAtWatchedSeconds: Double?
        var avPlayerObservedBytesWhenPendingBegan: Int64?
        var lastLoggedDecisionStage: ClipVideoCacheFillPolicy.DecisionStage?
        var knownAssetBytes: Int64?
        /// Best-estimate unique AVPlayer bytes for this item session (access-log high-water).
        var avPlayerObservedBytes: Int64 = 0
        /// Cumulative access-log deltas (can over-count overlapping requests).
        var avPlayerRawReportedBytes: Int64 = 0
        var assetLengthProbeStarted: Bool = false
        var didDeferFillForNetwork: Bool = false
    }

    static let shared: ClipVideoDeliveryService = {
        do {
            let store = try ClipPersistentVideoCacheStore()
            return ClipVideoDeliveryService(store: store)
        } catch {
            return ClipVideoDeliveryService(store: nil)
        }
    }()

    private let store: ClipPersistentVideoCacheStore?
    private let allowsPersistentFullFileFill: @Sendable () -> Bool
    private var clipStates: [String: ClipState] = [:]
    private var inFlightDownloads: [String: Task<Int64?, Never>] = [:]
    private var hadNetworkPlaybackByKey: Set<String> = []
    private var prefetchKeysPending: Set<String> = []

    init(
        store: ClipPersistentVideoCacheStore?,
        allowsPersistentFullFileFill: @escaping @Sendable () -> Bool = {
            ClipPlaybackBufferConfiguration.allowsPersistentFullFileFill()
        }
    ) {
        self.store = store
        self.allowsPersistentFullFileFill = allowsPersistentFullFileFill
    }

    init(
        testStore: ClipPersistentVideoCacheStore,
        allowsPersistentFullFileFill: @escaping @Sendable () -> Bool = {
            ClipPlaybackBufferConfiguration.allowsPersistentFullFileFill()
        }
    ) {
        self.store = testStore
        self.allowsPersistentFullFileFill = allowsPersistentFullFileFill
    }

    static var maxDiskBudgetBytes: Int64 {
        ClipPersistentVideoCacheStore.defaultMaxDiskBytes
    }

    func playbackURL(
        remoteURL: URL,
        clipID: String,
        role: ClipVideoDeliveryRole
    ) async -> (url: URL, source: ClipVideoPlaybackSource) {
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        let identity = ClipVideoCacheIdentity.canonicalIdentity(for: remoteURL)

        if let store, let local = await store.readyFileURL(for: cacheKey) {
            registerState(
                cacheKey: cacheKey,
                clipID: clipID,
                remoteURL: remoteURL,
                identity: identity,
                role: role,
                fromDisk: true
            )
            let isReentry = hadNetworkPlaybackByKey.contains(cacheKey)
            ClipVideoDeliveryTelemetry.record(.persistentCacheHit)
            ClipVideoDeliveryTelemetry.record(.cacheReuse)
            if isReentry {
                ClipVideoDeliveryTelemetry.record(.repeatReentryReuse)
            }
            let fileSize = Int64((try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            logPlayback(
                clipID: clipID,
                role: role,
                cacheHit: true,
                source: "disk",
                assetBytes: fileSize
            )
            ClipVideoTransferTelemetry.logTransferOwnership(
                clipID: clipID,
                playbackSource: "disk",
                networkOwner: .shared,
                assetBytes: fileSize > 0 ? fileSize : nil,
                avPlayerObservedBytes: 0,
                deliveryDownloadBytes: 0,
                duplicateBytesEstimated: nil,
                persistentCacheResult: .alreadyCached,
                strategy: .diskReuse
            )
            return (local, .persistentDisk)
        }

        registerState(
            cacheKey: cacheKey,
            clipID: clipID,
            remoteURL: remoteURL,
            identity: identity,
            role: role,
            fromDisk: false
        )

        ClipVideoDeliveryTelemetry.record(.persistentCacheMiss)
        ClipVideoDeliveryTelemetry.record(.networkBackedLoad)
        hadNetworkPlaybackByKey.insert(cacheKey)

        if role == .prefetch {
            ClipVideoDeliveryTelemetry.record(.prefetchStarted)
            prefetchKeysPending.insert(cacheKey)
            ClipPrefetchTrace.started(clipID: clipID, fullCacheDownloadStarted: false)
        }

        #if DEBUG
        let coldRole = coldTestRoleLabel(role)
        ClipColdTestTrace.log(
            clipID: clipID,
            canonicalKey: cacheKey,
            role: coldRole,
            event: .cacheMiss,
            requestPurpose: .playback,
            url: remoteURL
        )
        ClipColdTestTrace.log(
            clipID: clipID,
            canonicalKey: cacheKey,
            role: coldRole,
            event: .remotePlaybackStarted,
            requestPurpose: .playback,
            url: remoteURL,
            requestID: "avplayer-\(clipID)-session"
        )
        #endif

        logPlayback(clipID: clipID, role: role, cacheHit: false, source: "network", assetBytes: nil)
        scheduleAssetLengthProbeIfNeeded(cacheKey: cacheKey, remoteURL: remoteURL)
        // Phase 12B: no TradeTraxs full-file cache fill from playback resolution alone.
        return (remoteURL, .network)
    }

    func noteKnownAssetBytes(clipID: String, remoteURL: URL, bytes: Int64) {
        guard bytes > 0 else { return }
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        if var state = clipStates[cacheKey] {
            state.knownAssetBytes = bytes
            clipStates[cacheKey] = state
        }
        ClipAVPlayerEgressTelemetry.noteKnownAssetBytes(clipID: clipID, bytes: bytes)
        #if DEBUG
        ClipColdTestTrace.noteKnownAssetBytes(clipID: clipID, bytes: bytes)
        #endif
    }

    func knownAssetBytes(for remoteURL: URL) -> Int64? {
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return clipStates[cacheKey]?.knownAssetBytes
    }

    func recordAVPlayerNetworkBytes(
        clipID: String,
        remoteURL: URL,
        deltaBytes: Int64,
        sessionItemBytes: Int64 = 0
    ) async {
        guard deltaBytes > 0 || sessionItemBytes > 0 else { return }
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        guard var state = clipStates[cacheKey], state.clipID == clipID else { return }
        if deltaBytes > 0 {
            state.avPlayerRawReportedBytes += deltaBytes
            ClipVideoTransferTelemetry.recordAVPlayerBytes(deltaBytes)
            ClipVideoByteAccounting.recordAVPlayerDelta(
                clipID: clipID,
                bytes: deltaBytes,
                role: state.isActiveConsumer ? "active" : "prefetch"
            )
        }
        if sessionItemBytes > 0 {
            state.avPlayerObservedBytes = max(state.avPlayerObservedBytes, sessionItemBytes)
        } else if deltaBytes > 0 {
            state.avPlayerObservedBytes = max(state.avPlayerObservedBytes, state.avPlayerRawReportedBytes)
        }
        clipStates[cacheKey] = state

        if state.isActiveConsumer {
            await reevaluateDeferredCacheFillDecision(cacheKey: cacheKey, trigger: "avPlayerBytes")
            await cancelInFlightFillIfDuplicateRiskEmerges(cacheKey: cacheKey)
        }
    }

    func updateConsumption(
        clipID: String,
        remoteURL: URL,
        watchedSeconds: Double,
        durationSeconds: Double?
    ) async {
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        guard var state = clipStates[cacheKey], state.clipID == clipID else { return }
        guard state.isActiveConsumer else { return }

        state.watchedSeconds = max(state.watchedSeconds, watchedSeconds)
        if let durationSeconds, durationSeconds > 0 {
            state.durationSeconds = durationSeconds
        }

        let eligible = ClipVideoCacheFillPolicy.isEligible(
            watchedSeconds: state.watchedSeconds,
            durationSeconds: state.durationSeconds
        )
        if eligible, !state.fillEligible {
            state.fillEligible = true
            ClipVideoDeliveryTrace.log(
                "cacheFillEligible clipID=\(clipID)",
                cacheFillEligible: true,
                watchedSeconds: state.watchedSeconds,
                watchedPercent: watchedFraction(state)
            )
        }
        clipStates[cacheKey] = state

        if state.fillEligible {
            await reevaluateDeferredCacheFillDecision(cacheKey: cacheKey, trigger: "consumptionTick")
        }
    }

    func notePrefetchViewed(cacheKey: String) {
        if prefetchKeysPending.remove(cacheKey) != nil {
            ClipVideoDeliveryTelemetry.record(.prefetchViewed)
        }
        if var state = clipStates[cacheKey] {
            state.isActiveConsumer = true
            state.prefetchPrepared = false
            clipStates[cacheKey] = state
            ClipPrefetchTrace.becameActive(clipID: state.clipID)
        }
    }

    func notePrefetchDiscarded(cacheKey: String) async {
        if prefetchKeysPending.remove(cacheKey) != nil {
            ClipVideoDeliveryTelemetry.record(.prefetchDiscarded)
        }
        if let state = clipStates[cacheKey] {
            ClipPrefetchTrace.discarded(clipID: state.clipID)
        }
        await cancelCacheFill(cacheKey: cacheKey)
        if var state = clipStates[cacheKey] {
            state.prefetchPrepared = false
            if !state.isActiveConsumer {
                clipStates.removeValue(forKey: cacheKey)
            } else {
                clipStates[cacheKey] = state
            }
        }
    }

    /// Active clip player released — cancel pending decision and in-flight fill (Phase 12E).
    func activeClipReleased(cacheKey: String) async {
        guard var state = clipStates[cacheKey] else { return }
        state.isActiveConsumer = false
        clipStates[cacheKey] = state

        switch state.cacheDecisionState {
        case .completed, .skippedDuplicateRisk, .cancelledDuplicateRisk:
            return
        case .fillStarted:
            await cancelCacheFill(cacheKey: cacheKey, reason: "activeClipReleased")
            if var updated = clipStates[cacheKey] {
                updated.cacheDecisionState = .cancelledDuplicateRisk
                clipStates[cacheKey] = updated
            }
        case .pending, .notEligible:
            await cancelCacheFill(cacheKey: cacheKey, reason: "activeClipReleased")
            clipStates.removeValue(forKey: cacheKey)
        }
    }

    func cacheKey(for remoteURL: URL) -> String {
        ClipVideoCacheIdentity.cacheKey(for: remoteURL)
    }

    /// DEBUG cold-cache test: wipe disk Clip cache and reset delivery actor state.
    func clearPersistentCacheForColdTest() async {
        for (_, task) in inFlightDownloads {
            task.cancel()
        }
        inFlightDownloads.removeAll()

        if let store {
            await store.clearAllContents()
        }

        clipStates.removeAll()
        hadNetworkPlaybackByKey.removeAll()
        prefetchKeysPending.removeAll()

        ClipVideoDeliveryTelemetry.resetViewerSession()
        #if DEBUG
        ClipColdTestTrace.resetAll()
        ClipPlayerIdentityTrace.resetSession()
        ClipAVPlayerEgressTelemetry.resetSession()
        #endif
    }

#if DEBUG
    func debug_isPersisted(remoteURL: URL) async -> Bool {
        guard let store else { return false }
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return await store.readyFileURL(for: key) != nil
    }
#endif

#if DEBUG
    func testing_fillStarted(for remoteURL: URL) -> Bool {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return clipStates[key]?.fillStarted ?? false
    }

    func testing_fillEligible(for remoteURL: URL) -> Bool {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return clipStates[key]?.fillEligible ?? false
    }

    func testing_isFillInFlight(for remoteURL: URL) -> Bool {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return inFlightDownloads[key] != nil
    }

    func testing_fillSkippedDuplicateRisk(for remoteURL: URL) -> Bool {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return clipStates[key]?.fillSkippedDuplicateRisk ?? false
    }

    func testing_cacheDecisionState(for remoteURL: URL) -> ClipVideoCacheFillPolicy.CacheFillDecisionState {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        return clipStates[key]?.cacheDecisionState ?? .notEligible
    }

    func testing_cancelInFlightFillIfDuplicateRisk(for remoteURL: URL) async {
        let key = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        await cancelInFlightFillIfDuplicateRiskEmerges(cacheKey: key)
    }

    func testing_simulateFillInFlight(remoteURL: URL, clipID: String) async {
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        guard clipStates[cacheKey] != nil else { return }
        clipStates[cacheKey]?.fillStarted = true
        clipStates[cacheKey]?.cacheDecisionState = .fillStarted
        let task = Task<Int64?, Never> {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            return nil
        }
        inFlightDownloads[cacheKey] = task
    }

    func testing_recordAvPlayerSessionBytes(
        remoteURL: URL,
        clipID: String,
        sessionItemBytes: Int64,
        deltaBytes: Int64 = 0
    ) async {
        await recordAVPlayerNetworkBytes(
            clipID: clipID,
            remoteURL: remoteURL,
            deltaBytes: deltaBytes,
            sessionItemBytes: sessionItemBytes
        )
    }

    func testing_seedNetworkMetrics(
        remoteURL: URL,
        clipID: String,
        knownAssetBytes: Int64?,
        avPlayerObservedBytes: Int64
    ) {
        let cacheKey = ClipVideoCacheIdentity.cacheKey(for: remoteURL)
        let identity = ClipVideoCacheIdentity.canonicalIdentity(for: remoteURL)
        if clipStates[cacheKey] == nil {
            registerState(
                cacheKey: cacheKey,
                clipID: clipID,
                remoteURL: remoteURL,
                identity: identity,
                role: .active,
                fromDisk: false
            )
        }
        clipStates[cacheKey]?.knownAssetBytes = knownAssetBytes
        clipStates[cacheKey]?.avPlayerObservedBytes = avPlayerObservedBytes
    }
#endif

    // MARK: - Private

    private func registerState(
        cacheKey: String,
        clipID: String,
        remoteURL: URL,
        identity: String,
        role: ClipVideoDeliveryRole,
        fromDisk: Bool
    ) {
        var state = clipStates[cacheKey] ?? ClipState(
            clipID: clipID,
            remoteURL: remoteURL,
            urlIdentity: identity,
            isActiveConsumer: false,
            prefetchPrepared: false
        )
        state.clipID = clipID
        state.remoteURL = remoteURL
        state.urlIdentity = identity

        switch role {
        case .prefetch:
            state.prefetchPrepared = true
        case .active, .detail:
            state.isActiveConsumer = true
            state.prefetchPrepared = false
        }
        if fromDisk {
            state.fillStarted = true
            state.fillEligible = true
            state.cacheDecisionState = .completed
        }
        clipStates[cacheKey] = state
    }

    private func reevaluateDeferredCacheFillDecision(cacheKey: String, trigger: String) async {
        guard let store else { return }
        guard var state = clipStates[cacheKey] else { return }
        guard state.isActiveConsumer, state.fillEligible else { return }

        switch state.cacheDecisionState {
        case .skippedDuplicateRisk, .cancelledDuplicateRisk, .completed:
            return
        case .fillStarted:
            return
        case .notEligible, .pending:
            break
        }

        guard await store.readyFileURL(for: cacheKey) == nil else {
            markFillCompleteAlreadyCached(cacheKey: cacheKey, state: state)
            return
        }
        guard inFlightDownloads[cacheKey] == nil else { return }

        if state.knownAssetBytes == nil, !state.assetLengthProbeStarted {
            scheduleAssetLengthProbeIfNeeded(cacheKey: cacheKey, remoteURL: state.remoteURL)
        }

        if state.cacheDecisionState == .notEligible {
            state.cacheDecisionState = .pending
            state.pendingBeganAtWatchedSeconds = state.watchedSeconds
            state.avPlayerObservedBytesWhenPendingBegan = state.avPlayerObservedBytes
        }

        let deferred = ClipVideoCacheFillPolicy.deferredCacheFillDecision(
            watchedSeconds: state.watchedSeconds,
            knownAssetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes,
            avPlayerObservedBytesWhenPendingBegan: state.avPlayerObservedBytesWhenPendingBegan,
            pendingBeganAtWatchedSeconds: state.pendingBeganAtWatchedSeconds,
            durationSeconds: state.durationSeconds
        )

        let shouldLogStage = deferred.stage != state.lastLoggedDecisionStage
            || deferred.decision != .pending
        if shouldLogStage {
            logDeferredCacheFillDecision(state: state, deferred: deferred)
            if let stage = deferred.stage {
                state.lastLoggedDecisionStage = stage
            }
        }

        switch deferred.decision {
        case .skipDuplicateRisk:
            clipStates[cacheKey] = state
            await markSkippedDuplicateRisk(cacheKey: cacheKey, reason: deferred.reason)
        case .pending:
            state.cacheDecisionState = .pending
            clipStates[cacheKey] = state
        case .startFill:
            guard state.isActiveConsumer else { return }
            clipStates[cacheKey] = state
            await startCacheFillDownload(
                cacheKey: cacheKey,
                reason: "deferWindowElapsedLowAVPlayerConsumption|\(trigger)",
                state: state
            )
        }
    }

    private func markSkippedDuplicateRisk(cacheKey: String, reason: String) async {
        guard var state = clipStates[cacheKey] else { return }
        guard !state.fillSkippedDuplicateRisk else { return }
        state.fillStarted = true
        state.fillSkippedDuplicateRisk = true
        state.cacheDecisionState = .skippedDuplicateRisk
        clipStates[cacheKey] = state

        let estimatedDup = ClipVideoCacheFillPolicy.estimatedDuplicateBytesIfFilled(
            knownAssetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes
        ) ?? state.knownAssetBytes ?? 0
        ClipVideoTransferTelemetry.recordDuplicateRiskSkip(estimatedDuplicateBytes: estimatedDup)
        ClipVideoTransferTelemetry.logTransferOwnership(
            clipID: state.clipID,
            playbackSource: "network",
            networkOwner: .avplayer,
            assetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes,
            avPlayerRawReportedBytes: state.avPlayerRawReportedBytes,
            deliveryDownloadBytes: 0,
            duplicateBytesEstimated: estimatedDup,
            persistentCacheResult: .skippedDuplicateRisk,
            strategy: .duplicateRiskSkip,
            cacheDecisionState: state.cacheDecisionState.rawValue
        )
        ClipVideoDeliveryTrace.cache(
            "fillSkippedDuplicateRisk clipID=\(state.clipID) key=\(cacheKey.prefix(8)) reason=\(reason)"
        )
    }

    private func cancelInFlightFillIfDuplicateRiskEmerges(cacheKey: String) async {
        guard var state = clipStates[cacheKey] else { return }
        guard state.cacheDecisionState == .fillStarted, inFlightDownloads[cacheKey] != nil else { return }

        guard ClipVideoCacheFillPolicy.shouldCancelInFlightFillForObservedConsumption(
            knownAssetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes
        ) else { return }
        let policy = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes
        )

        await cancelCacheFill(cacheKey: cacheKey, reason: "avPlayerCrossedThresholdDuringFill")
        state = clipStates[cacheKey] ?? state
        state.fillStarted = true
        state.fillSkippedDuplicateRisk = true
        state.cacheDecisionState = .cancelledDuplicateRisk
        clipStates[cacheKey] = state

        logDeferredCacheFillDecision(
            state: state,
            deferred: (
                .skipDuplicateRisk,
                "avPlayerCrossedThresholdDuringFill",
                policy.avPlayerObservedPercent,
                ClipVideoCacheFillPolicy.decisionStage(
                    watchedSeconds: state.watchedSeconds,
                    durationSeconds: state.durationSeconds
                )
            ),
            decisionOverride: .cancelFillDuplicateRisk
        )

        let estimatedDup = ClipVideoCacheFillPolicy.estimatedDuplicateBytesIfFilled(
            knownAssetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes
        ) ?? state.knownAssetBytes ?? 0
        ClipVideoTransferTelemetry.recordDuplicateRiskSkip(estimatedDuplicateBytes: estimatedDup)
        ClipVideoTransferTelemetry.logTransferOwnership(
            clipID: state.clipID,
            playbackSource: "network",
            networkOwner: .avplayer,
            assetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes,
            avPlayerRawReportedBytes: state.avPlayerRawReportedBytes,
            deliveryDownloadBytes: 0,
            duplicateBytesEstimated: estimatedDup,
            persistentCacheResult: .skippedDuplicateRisk,
            strategy: .duplicateRiskSkip,
            cacheDecisionState: state.cacheDecisionState.rawValue
        )
    }

    private func startCacheFillDownload(cacheKey: String, reason: String, state: ClipState) async {
        guard let store else { return }
        var state = state
        guard state.isActiveConsumer, state.fillEligible, !state.fillStarted else { return }
        guard inFlightDownloads[cacheKey] == nil else { return }
        guard allowsPersistentFullFileFill() else {
            if !state.didDeferFillForNetwork {
                state.didDeferFillForNetwork = true
                clipStates[cacheKey] = state
                let networkClass = ClipPlaybackLiveNetworkPosture().currentPosture().networkClass
                ClipVideoDeliveryTrace.cache(
                    "fillDeferredNetwork clipID=\(state.clipID) reason=conserveBandwidth networkClass=\(networkClass)"
                )
            }
            return
        }

        if state.prefetchPrepared, !state.isActiveConsumer {
            ClipVideoDeliveryTelemetry.record(.prefetchFullDownload)
        }

        state.fillStarted = true
        state.cacheDecisionState = .fillStarted
        clipStates[cacheKey] = state

        ClipVideoDeliveryTelemetry.record(.cacheFillStarted)
        ClipVideoDeliveryTrace.cache(
            "fillStarted clipID=\(state.clipID) reason=\(reason) key=\(cacheKey.prefix(8))"
        )
        ClipVideoDeliveryTrace.log(
            "cacheFillStarted clipID=\(state.clipID)",
            cacheFillStarted: true,
            cacheFillReason: reason,
            watchedSeconds: state.watchedSeconds,
            watchedPercent: watchedFraction(state)
        )

        let fillRequestID = UUID().uuidString
        #if DEBUG
        ClipColdTestTrace.log(
            clipID: state.clipID,
            canonicalKey: cacheKey,
            role: "active",
            event: .cacheFillStarted,
            requestPurpose: .cacheFill,
            url: state.remoteURL,
            requestID: fillRequestID
        )
        #endif

        let remoteURL = state.remoteURL
        let urlIdentity = state.urlIdentity
        let clipID = state.clipID

        let task = Task<Int64?, Never> {
            await Self.downloadToCache(
                remoteURL: remoteURL,
                cacheKey: cacheKey,
                urlIdentity: urlIdentity,
                clipID: clipID,
                store: store,
                cacheFillRequestID: fillRequestID
            )
        }
        inFlightDownloads[cacheKey] = task
        Task { [weak self] in
            _ = await task.value
            await self?.clearInFlight(cacheKey: cacheKey)
        }
    }

    private func cancelCacheFill(cacheKey: String, reason: String = "cancelled") async {
        if let task = inFlightDownloads.removeValue(forKey: cacheKey) {
            task.cancel()
            ClipVideoDeliveryTelemetry.record(.cacheFillCancelled)
            if let state = clipStates[cacheKey] {
                ClipVideoDeliveryTrace.cache(
                    "fillCancelled clipID=\(state.clipID) key=\(cacheKey.prefix(8)) reason=\(reason)"
                )
                #if DEBUG
                ClipColdTestTrace.log(
                    clipID: state.clipID,
                    canonicalKey: cacheKey,
                    role: "active",
                    event: .cacheFillCancelled,
                    requestPurpose: .cacheFill,
                    url: state.remoteURL
                )
                #endif
            }
        }
        if let store {
            let partURL = await store.partFileURL(for: cacheKey)
            try? FileManager.default.removeItem(at: partURL)
        }
        if var state = clipStates[cacheKey] {
            state.fillStarted = false
            clipStates[cacheKey] = state
        }
    }

    private func clearInFlight(cacheKey: String) {
        inFlightDownloads.removeValue(forKey: cacheKey)
    }

    private func watchedFraction(_ state: ClipState) -> Double? {
        guard let duration = state.durationSeconds, duration > 0 else { return nil }
        return state.watchedSeconds / duration
    }

    private func coldTestRoleLabel(_ role: ClipVideoDeliveryRole) -> String {
        switch role {
        case .prefetch: return "prefetch"
        case .active, .detail: return "active"
        }
    }

    private func logPlayback(
        clipID: String,
        role: ClipVideoDeliveryRole,
        cacheHit: Bool,
        source: String,
        assetBytes: Int64?
    ) {
        let roleLabel: String
        switch role {
        case .active: roleLabel = "active"
        case .prefetch: roleLabel = "prefetch"
        case .detail: roleLabel = "detail"
        }
        ClipVideoDeliveryTrace.log(
            "playback clipID=\(clipID) role=\(roleLabel)",
            cacheHit: cacheHit,
            source: source,
            assetBytes: assetBytes,
            prefetch: role == .prefetch
        )
    }

    private static func downloadToCache(
        remoteURL: URL,
        cacheKey: String,
        urlIdentity: String,
        clipID: String,
        store: ClipPersistentVideoCacheStore,
        cacheFillRequestID: String? = nil
    ) async -> Int64? {
        if Task.isCancelled {
            #if DEBUG
            ClipColdTestTrace.log(
                clipID: clipID,
                canonicalKey: cacheKey,
                role: "active",
                event: .cacheFillCancelled,
                requestPurpose: .cacheFill,
                url: remoteURL,
                requestID: cacheFillRequestID
            )
            #endif
            return nil
        }
        if await store.readyFileURL(for: cacheKey) != nil {
            return nil
        }

        let path = remoteURL.path.isEmpty ? "/storage/v1/object/" : remoteURL.path
        let host = remoteURL.host ?? "supabase"

        let partURL = await store.partFileURL(for: cacheKey)

        do {
            let bytes: Int64? = try await NetworkConcurrencyCoordinator.shared.runWithSlot(
                priority: .background,
                path: path,
                host: host,
                method: .get
            ) {
                if Task.isCancelled { return nil as Int64? }

                let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                if Task.isCancelled { return nil }

                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode) || http.statusCode == 206
                else {
                    ClipVideoDeliveryTrace.cache("downloadFailed clipID=\(clipID) status=invalid")
                    return nil
                }

                if FileManager.default.fileExists(atPath: partURL.path) {
                    try? FileManager.default.removeItem(at: partURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: partURL)

                let written = try await store.completeDownload(
                    cacheKey: cacheKey,
                    urlIdentity: urlIdentity,
                    stagedFileURL: partURL
                )
                return written
            }

            guard let bytes, bytes > 0 else {
                if Task.isCancelled {
                    #if DEBUG
                    ClipColdTestTrace.log(
                        clipID: clipID,
                        canonicalKey: cacheKey,
                        role: "active",
                        event: .cacheFillCancelled,
                        requestPurpose: .cacheFill,
                        url: remoteURL,
                        requestID: cacheFillRequestID
                    )
                    #endif
                }
                return nil
            }

            ClipVideoDeliveryTelemetry.record(.bytesWrittenToCache(bytes))
            ClipVideoDeliveryTelemetry.record(.cacheFillCompleted)
            ClipVideoTransferTelemetry.recordCacheFillBytes(bytes)
            ClipVideoTransferTelemetry.recordClipPersisted()
            ClipVideoByteAccounting.recordCacheFill(clipID: clipID, bytes: bytes)
            ClipVideoDeliveryTrace.cache(
                "complete clipID=\(clipID) key=\(cacheKey.prefix(8)) bytes=\(bytes) assetBytes=\(bytes)"
            )
            await ClipVideoDeliveryService.shared.noteCacheFillCompleted(
                cacheKey: cacheKey,
                clipID: clipID,
                bytes: bytes
            )
            #if DEBUG
            ClipColdTestTrace.log(
                clipID: clipID,
                canonicalKey: cacheKey,
                role: "active",
                event: .cacheFillCompleted,
                requestPurpose: .cacheFill,
                url: remoteURL,
                expectedAssetBytes: bytes,
                transferredBytes: bytes,
                requestID: cacheFillRequestID
            )
            ClipColdTestTrace.noteCachePersisted(clipID: clipID, assetBytes: bytes)
            #endif
            return bytes
        } catch {
            if Task.isCancelled {
                #if DEBUG
                ClipColdTestTrace.log(
                    clipID: clipID,
                    canonicalKey: cacheKey,
                    role: "active",
                    event: .cacheFillCancelled,
                    requestPurpose: .cacheFill,
                    url: remoteURL,
                    requestID: cacheFillRequestID
                )
                #endif
            } else {
                ClipVideoDeliveryTrace.cache("downloadError clipID=\(clipID) error=\(error.localizedDescription)")
                await store.invalidate(cacheKey: cacheKey)
            }
            return nil
        }
    }

    func noteCacheFillCompleted(cacheKey: String, clipID: String, bytes: Int64) {
        if var state = clipStates[cacheKey] {
            state.knownAssetBytes = bytes
            state.cacheDecisionState = .completed
            clipStates[cacheKey] = state
        }
        let avPlayerBytes = clipStates[cacheKey]?.avPlayerObservedBytes ?? 0
        let rawBytes = clipStates[cacheKey]?.avPlayerRawReportedBytes ?? 0
        let decisionState = clipStates[cacheKey]?.cacheDecisionState.rawValue ?? "completed"
        let dup = ClipVideoCacheFillPolicy.estimatedDuplicateBytesIfFilled(
            knownAssetBytes: bytes,
            avPlayerObservedBytes: avPlayerBytes
        )
        ClipVideoTransferTelemetry.logTransferOwnership(
            clipID: clipID,
            playbackSource: "network",
            networkOwner: .deliveryService,
            assetBytes: bytes,
            avPlayerObservedBytes: avPlayerBytes,
            avPlayerRawReportedBytes: rawBytes,
            deliveryDownloadBytes: bytes,
            duplicateBytesEstimated: dup,
            persistentCacheResult: .written,
            strategy: .deliveryFullDownload,
            cacheDecisionState: decisionState
        )
    }

    private func markFillCompleteAlreadyCached(cacheKey: String, state: ClipState) {
        var state = state
        state.fillStarted = true
        state.cacheDecisionState = .completed
        clipStates[cacheKey] = state
        ClipVideoTransferTelemetry.logCacheDecision(
            clipID: state.clipID,
            stage: nil,
            watchedSeconds: state.watchedSeconds,
            watchedPercent: watchedFraction(state),
            assetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes,
            avPlayerObservedPercent: nil,
            avPlayerRawReportedBytes: state.avPlayerRawReportedBytes,
            decision: .alreadyCached,
            reason: "diskHitBeforeFill"
        )
    }

    private func logDeferredCacheFillDecision(
        state: ClipState,
        deferred: (
            decision: ClipVideoCacheFillPolicy.CacheFillDecision,
            reason: String,
            avPlayerObservedPercent: Double?,
            stage: ClipVideoCacheFillPolicy.DecisionStage?
        ),
        decisionOverride: ClipVideoTransferTelemetry.CacheFillDecisionKind? = nil
    ) {
        let decisionKind: ClipVideoTransferTelemetry.CacheFillDecisionKind
        if let decisionOverride {
            decisionKind = decisionOverride
        } else {
            switch deferred.decision {
            case .startFill:
                decisionKind = .startFill
            case .skipDuplicateRisk:
                decisionKind = .skipDuplicateRisk
            case .pending:
                decisionKind = .pending
            }
        }
        let telemetryStage = deferred.stage.map {
            ClipVideoTransferTelemetry.CacheDecisionStage(rawValue: $0.rawValue)!
        }
        ClipVideoTransferTelemetry.logCacheDecision(
            clipID: state.clipID,
            stage: telemetryStage,
            watchedSeconds: state.watchedSeconds,
            watchedPercent: watchedFraction(state),
            assetBytes: state.knownAssetBytes,
            avPlayerObservedBytes: state.avPlayerObservedBytes,
            avPlayerObservedPercent: deferred.avPlayerObservedPercent,
            avPlayerRawReportedBytes: state.avPlayerRawReportedBytes,
            decision: decisionKind,
            reason: deferred.reason
        )
    }

    private func scheduleAssetLengthProbeIfNeeded(cacheKey: String, remoteURL: URL) {
        guard var state = clipStates[cacheKey] else { return }
        guard state.knownAssetBytes == nil, !state.assetLengthProbeStarted else { return }
        state.assetLengthProbeStarted = true
        clipStates[cacheKey] = state

        let path = remoteURL.path.isEmpty ? "/storage/v1/object/" : remoteURL.path
        let host = remoteURL.host ?? "supabase"
        Task {
            let bytes = await Self.fetchAssetContentLength(
                remoteURL: remoteURL,
                path: path,
                host: host
            )
            guard let bytes, bytes > 0 else { return }
            self.applyKnownAssetBytes(cacheKey: cacheKey, bytes: bytes)
        }
    }

    private func applyKnownAssetBytes(cacheKey: String, bytes: Int64) {
        guard var state = clipStates[cacheKey] else { return }
        state.knownAssetBytes = bytes
        clipStates[cacheKey] = state
        ClipAVPlayerEgressTelemetry.noteKnownAssetBytes(clipID: state.clipID, bytes: bytes)
        #if DEBUG
        ClipColdTestTrace.noteKnownAssetBytes(clipID: state.clipID, bytes: bytes)
        #endif
        if state.fillEligible, state.isActiveConsumer {
            Task { await self.reevaluateDeferredCacheFillDecision(cacheKey: cacheKey, trigger: "assetSizeKnown") }
        }
    }

    private func waitBrieflyForAssetLengthProbe(cacheKey: String) async {
        for _ in 0 ..< 6 {
            if clipStates[cacheKey]?.knownAssetBytes != nil { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private static func fetchAssetContentLength(
        remoteURL: URL,
        path: String,
        host: String
    ) async -> Int64? {
        do {
            return try await NetworkConcurrencyCoordinator.shared.runWithSlot(
                priority: .background,
                path: path,
                host: host,
                method: .head
            ) {
                var request = URLRequest(url: remoteURL)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 12
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode)
                else { return nil as Int64? }
                if let length = http.value(forHTTPHeaderField: "Content-Length"),
                   let parsed = Int64(length.trimmingCharacters(in: .whitespaces)),
                   parsed > 0
                {
                    return parsed
                }
                return nil as Int64?
            }
        } catch {
            return nil
        }
    }
}
