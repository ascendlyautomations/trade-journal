import XCTest
@testable import TradeTraxs

final class ClipVideoDeliveryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVideoCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        ClipVideoDeliveryTelemetry.resetViewerSession()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testCacheKeyIsDeterministicForSameURL() {
        let url = URL(string: "https://proj.supabase.co/storage/v1/object/public/reels/u1/videos/1-clip.mp4")!
        let a = ClipVideoCacheIdentity.cacheKey(for: url)
        let b = ClipVideoCacheIdentity.cacheKey(for: url)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testCacheKeyIgnoresQueryFragment() {
        let base = URL(string: "https://proj.supabase.co/storage/v1/object/public/reels/u1/videos/1-clip.mp4")!
        let withQuery = URL(string: "https://proj.supabase.co/storage/v1/object/public/reels/u1/videos/1-clip.mp4?token=abc")!
        XCTAssertEqual(
            ClipVideoCacheIdentity.canonicalIdentity(for: base),
            ClipVideoCacheIdentity.canonicalIdentity(for: withQuery)
        )
    }

    func testPersistentCacheHitAfterCompleteDownload() async throws {
        let store = try ClipPersistentVideoCacheStore(
            maxDiskBytes: 50 * 1_024 * 1_024,
            rootDirectory: tempRoot
        )
        let key = "abc123"
        let staged = tempRoot.appendingPathComponent("staged.mp4")
        try writeMinimalMP4(at: staged)

        let bytes = try await store.completeDownload(
            cacheKey: key,
            urlIdentity: "example.com/reels/x",
            stagedFileURL: staged
        )
        XCTAssertGreaterThan(bytes, 0)

        let ready = await store.readyFileURL(for: key)
        XCTAssertNotNil(ready)
        let readyAgain = await store.readyFileURL(for: key)
        XCTAssertEqual(readyAgain?.path, ready?.path)
    }

    func testPartialPartFileIsNotReadableAsReady() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let key = "partial-key"
        let part = await store.partFileURL(for: key)
        try Data(repeating: 0xAB, count: 32).write(to: part)
        let partialReady = await store.readyFileURL(for: key)
        XCTAssertNil(partialReady)
    }

    func testCorruptFileInvalidatesEntry() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let key = "corrupt"
        let staged = tempRoot.appendingPathComponent("good.mp4")
        try writeMinimalMP4(at: staged)
        _ = try await store.completeDownload(
            cacheKey: key,
            urlIdentity: "id",
            stagedFileURL: staged
        )
        let fileURL = await store.fileURL(for: key)
        try Data("not-mp4".utf8).write(to: fileURL)
        let afterCorrupt = await store.readyFileURL(for: key)
        XCTAssertNil(afterCorrupt)
        let count = await store.entryCount()
        XCTAssertEqual(count, 0)
    }

    func testLRUEnforcesBudget() async throws {
        let budget: Int64 = 300
        let store = try ClipPersistentVideoCacheStore(maxDiskBytes: budget, rootDirectory: tempRoot)

        for index in 0 ..< 3 {
            let key = "key-\(index)"
            let staged = tempRoot.appendingPathComponent("f-\(index).mp4")
            try writeMinimalMP4(at: staged, padding: 120)
            _ = try await store.completeDownload(
                cacheKey: key,
                urlIdentity: "id-\(index)",
                stagedFileURL: staged
            )
            if index < 2 {
                _ = await store.readyFileURL(for: key)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        await store.evictIfNeeded()
        let total = await store.totalBytesOnDisk()
        XCTAssertLessThanOrEqual(total, budget)
        let evicted = await store.readyFileURL(for: "key-0")
        XCTAssertNil(evicted)
        let retained = await store.readyFileURL(for: "key-2")
        XCTAssertNotNil(retained)
    }

    func testDeliveryServiceReturnsDiskURLOnHit() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/9-clip.mp4")!
        let key = ClipVideoCacheIdentity.cacheKey(for: remote)
        let staged = tempRoot.appendingPathComponent("hit.mp4")
        try writeMinimalMP4(at: staged)
        _ = try await store.completeDownload(cacheKey: key, urlIdentity: "x", stagedFileURL: staged)

        let service = ClipVideoDeliveryService(testStore: store)
        let first = await service.playbackURL(remoteURL: remote, clipID: "clip-1", role: .active)
        assertPlaybackSource(first.source, expected: .persistentDisk)
        XCTAssertTrue(first.url.isFileURL)

        ClipVideoDeliveryTelemetry.resetViewerSession()
        let second = await service.playbackURL(remoteURL: remote, clipID: "clip-1", role: .active)
        assertPlaybackSource(second.source, expected: .persistentDisk)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertGreaterThanOrEqual(snap.persistentCacheHits, 1)
        XCTAssertGreaterThanOrEqual(snap.cacheReuses, 1)
    }

    func testDeliveryServiceNetworkFallbackWhenCacheUnavailable() async {
        let service = ClipVideoDeliveryService(store: nil)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/1-clip.mp4")!
        let result = await service.playbackURL(remoteURL: remote, clipID: "x", role: .active)
        assertPlaybackSource(result.source, expected: .network)
        XCTAssertEqual(result.url, remote)
    }

    func testPrefetchViewedTelemetry() async {
        ClipVideoDeliveryTelemetry.resetViewerSession()
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/2-clip.mp4")!
        let service = ClipVideoDeliveryService(store: nil)
        _ = await service.playbackURL(remoteURL: remote, clipID: "a", role: .prefetch)
        let key = await service.cacheKey(for: remote)
        await service.notePrefetchViewed(cacheKey: key)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertEqual(snap.prefetchStarted, 1)
        XCTAssertEqual(snap.prefetchViewed, 1)
    }

    func testCacheFillPolicyThresholds() {
        XCTAssertFalse(ClipVideoCacheFillPolicy.isEligible(watchedSeconds: 0.5, durationSeconds: 60))
        XCTAssertTrue(ClipVideoCacheFillPolicy.isEligible(watchedSeconds: 2, durationSeconds: 60))
        XCTAssertTrue(ClipVideoCacheFillPolicy.isEligible(watchedSeconds: 1, durationSeconds: 5))
        XCTAssertFalse(ClipVideoCacheFillPolicy.isEligible(watchedSeconds: 1, durationSeconds: 60))
    }

    func testDuplicateRiskPolicyPreservedAfter12D() {
        let decision = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: 35_576_577,
            avPlayerObservedBytes: 32_871_964
        )
        XCTAssertEqual(decision.decision, .skipDuplicateRisk)
    }

    func testDuplicateRiskPolicySkipsHighAvPlayerFraction() {
        let decision = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: 35_576_577,
            avPlayerObservedBytes: 32_770_150
        )
        XCTAssertEqual(decision.decision, .skipDuplicateRisk)
    }

    func testDuplicateRiskPolicyAllowsFillWhenAvPlayerLow() {
        let decision = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: 35_576_577,
            avPlayerObservedBytes: 4_000_000
        )
        XCTAssertEqual(decision.decision, .startFill)
    }

    func testDuplicateRiskPolicyAllowsFillWhenAssetSizeUnknown() {
        let decision = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: nil,
            avPlayerObservedBytes: 32_000_000
        )
        XCTAssertEqual(decision.decision, .startFill)
        XCTAssertEqual(decision.reason, "assetSizeUnknown_allowFill")
    }

    func testDuplicateRiskPolicyAllowsFillWhenAvPlayerUnobserved() {
        let decision = ClipVideoCacheFillPolicy.cacheFillDecision(
            knownAssetBytes: 10_000_000,
            avPlayerObservedBytes: 0
        )
        XCTAssertEqual(decision.decision, .startFill)
        XCTAssertEqual(decision.reason, "avPlayerBytesNotYetObserved")
    }

    func testConservativeCacheFillPolicyBoundaries() {
        let asset: Int64 = 21_250_625
        let bytes39 = Int64((Double(asset) * 0.39).rounded(.down))
        let bytes40 = Int64((Double(asset) * ClipVideoCacheFillPolicy.maximumAVPlayerFractionForFullCacheFill).rounded(.up))
        let bytes533 = Int64(11_316_831)
        let bytes64 = Int64(Double(asset) * 0.64)
        let bytes65 = Int64((Double(asset) * 0.65).rounded(.up))

        XCTAssertEqual(
            ClipVideoCacheFillPolicy.cacheFillDecision(knownAssetBytes: asset, avPlayerObservedBytes: bytes39).decision,
            .startFill
        )
        let at40 = ClipVideoCacheFillPolicy.cacheFillDecision(knownAssetBytes: asset, avPlayerObservedBytes: bytes40)
        XCTAssertEqual(at40.decision, .skipDuplicateRisk)
        XCTAssertEqual(at40.reason, "avPlayerAlreadyConsumedMaterialFraction")

        let at533 = ClipVideoCacheFillPolicy.cacheFillDecision(knownAssetBytes: asset, avPlayerObservedBytes: bytes533)
        XCTAssertEqual(at533.decision, .skipDuplicateRisk)
        XCTAssertEqual(at533.reason, "avPlayerAlreadyConsumedMaterialFraction")

        let at64 = ClipVideoCacheFillPolicy.cacheFillDecision(knownAssetBytes: asset, avPlayerObservedBytes: bytes64)
        XCTAssertEqual(at64.decision, .skipDuplicateRisk)
        XCTAssertEqual(at64.reason, "avPlayerAlreadyConsumedMaterialFraction")

        let at65 = ClipVideoCacheFillPolicy.cacheFillDecision(knownAssetBytes: asset, avPlayerObservedBytes: bytes65)
        XCTAssertEqual(at65.decision, .skipDuplicateRisk)
        XCTAssertEqual(at65.reason, "avPlayerConsumedHighFractionOfAsset")

        let final533 = ClipVideoCacheFillPolicy.deferredCacheFillDecision(
            watchedSeconds: 6,
            knownAssetBytes: asset,
            avPlayerObservedBytes: bytes533,
            avPlayerObservedBytesWhenPendingBegan: bytes533,
            pendingBeganAtWatchedSeconds: 2,
            durationSeconds: 30
        )
        XCTAssertEqual(final533.decision, .skipDuplicateRisk)
        XCTAssertEqual(final533.reason, "avPlayerAlreadyConsumedMaterialFraction")
    }

    func testServiceSkipsFillWhenDuplicateRiskDetected() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/dup-risk.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "dup-risk", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "dup-risk",
            knownAssetBytes: 10_000,
            avPlayerObservedBytes: 9_000
        )
        await service.updateConsumption(clipID: "dup-risk", remoteURL: remote, watchedSeconds: 2.5, durationSeconds: 30)
        let skipped = await service.testing_fillSkippedDuplicateRisk(for: remote)
        let inFlight = await service.testing_isFillInFlight(for: remote)
        XCTAssertTrue(skipped)
        XCTAssertFalse(inFlight)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
    }

    func testBelowThresholdAtTwoSecondsEntersPendingNotFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/defer-pending.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "defer-pending", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "defer-pending",
            knownAssetBytes: 21_250_625,
            avPlayerObservedBytes: 3_000_000
        )
        await service.updateConsumption(clipID: "defer-pending", remoteURL: remote, watchedSeconds: 2.0, durationSeconds: 30)
        let decision = await service.testing_cacheDecisionState(for: remote)
        let fillStarted = await service.testing_fillStarted(for: remote)
        let inFlight = await service.testing_isFillInFlight(for: remote)
        XCTAssertEqual(decision, .pending)
        XCTAssertFalse(fillStarted)
        XCTAssertFalse(inFlight)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
    }

    func testServiceStartsFillWhenAvPlayerBytesLowAfterDeferWindow() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/low-bytes.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "low-bytes", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "low-bytes",
            knownAssetBytes: 10_000_000,
            avPlayerObservedBytes: 500_000
        )
        await service.updateConsumption(clipID: "low-bytes", remoteURL: remote, watchedSeconds: 2.5, durationSeconds: 30)
        let pendingDecision = await service.testing_cacheDecisionState(for: remote)
        let fillStartedEarly = await service.testing_fillStarted(for: remote)
        XCTAssertEqual(pendingDecision, .pending)
        XCTAssertFalse(fillStartedEarly)

        await service.updateConsumption(clipID: "low-bytes", remoteURL: remote, watchedSeconds: 6.5, durationSeconds: 30)
        let skipped = await service.testing_fillSkippedDuplicateRisk(for: remote)
        let fillStarted = await service.testing_fillStarted(for: remote)
        XCTAssertFalse(skipped)
        XCTAssertTrue(fillStarted)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 1)
    }

    func testMaterialFractionAtFinalDecisionSkipsFullCacheFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/5650-case.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "5650-case", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "5650-case",
            knownAssetBytes: 21_250_625,
            avPlayerObservedBytes: 11_316_831
        )
        await service.updateConsumption(clipID: "5650-case", remoteURL: remote, watchedSeconds: 6.5, durationSeconds: 30)
        let skipped = await service.testing_fillSkippedDuplicateRisk(for: remote)
        let fillStarted = await service.testing_fillStarted(for: remote)
        let inFlight = await service.testing_isFillInFlight(for: remote)
        XCTAssertTrue(skipped)
        XCTAssertTrue(fillStarted)
        XCTAssertFalse(inFlight)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
    }

    func testPendingThenAvPlayerCrossesThresholdSkipsFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/pending-skip.mp4")!
        _ = await service.playbackURL(remoteURL: remote, clipID: "pending-skip", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "pending-skip",
            knownAssetBytes: 21_250_625,
            avPlayerObservedBytes: 3_000_000
        )
        await service.updateConsumption(clipID: "pending-skip", remoteURL: remote, watchedSeconds: 2.0, durationSeconds: 30)
        let pendingState = await service.testing_cacheDecisionState(for: remote)
        XCTAssertEqual(pendingState, .pending)

        await service.testing_recordAvPlayerSessionBytes(
            remoteURL: remote,
            clipID: "pending-skip",
            sessionItemBytes: 14_500_000,
            deltaBytes: 4_000_000
        )
        await service.updateConsumption(clipID: "pending-skip", remoteURL: remote, watchedSeconds: 4.0, durationSeconds: 30)
        let skippedFill = await service.testing_fillSkippedDuplicateRisk(for: remote)
        let inFlightAfterSkip = await service.testing_isFillInFlight(for: remote)
        XCTAssertTrue(skippedFill)
        XCTAssertFalse(inFlightAfterSkip)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
    }

    func testPendingCancelledWhenActiveClipReleased() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/swipe-away.mp4")!
        _ = await service.playbackURL(remoteURL: remote, clipID: "swipe-away", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "swipe-away",
            knownAssetBytes: 10_000_000,
            avPlayerObservedBytes: 1_000_000
        )
        await service.updateConsumption(clipID: "swipe-away", remoteURL: remote, watchedSeconds: 2.5, durationSeconds: 30)
        let key = await service.cacheKey(for: remote)
        await service.activeClipReleased(cacheKey: key)
        await service.updateConsumption(clipID: "swipe-away", remoteURL: remote, watchedSeconds: 8, durationSeconds: 30)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
    }

    func testFillCancelledWhenDuplicateRiskEmergesDuringDownload() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/cancel-fill.mp4")!
        _ = await service.playbackURL(remoteURL: remote, clipID: "cancel-fill", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "cancel-fill",
            knownAssetBytes: 10_000_000,
            avPlayerObservedBytes: 500_000
        )
        await service.testing_simulateFillInFlight(remoteURL: remote, clipID: "cancel-fill")
        await service.testing_recordAvPlayerSessionBytes(
            remoteURL: remote,
            clipID: "cancel-fill",
            sessionItemBytes: 7_000_000,
            deltaBytes: 6_500_000
        )
        await service.testing_cancelInFlightFillIfDuplicateRisk(for: remote)
        let cancelledState = await service.testing_cacheDecisionState(for: remote)
        let inFlightAfterCancel = await service.testing_isFillInFlight(for: remote)
        XCTAssertEqual(cancelledState, .cancelledDuplicateRisk)
        XCTAssertFalse(inFlightAfterCancel)
    }

    func testPrefetchDoesNotStartFullCacheFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/prefetch-only.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "prefetch-1", role: .prefetch)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertEqual(snap.cacheFillStarted, 0)
        let prefetchFillStarted = await service.testing_fillStarted(for: remote)
        let prefetchInFlight = await service.testing_isFillInFlight(for: remote)
        XCTAssertFalse(prefetchFillStarted)
        XCTAssertFalse(prefetchInFlight)
    }

    func testActiveImmediateAbandonDoesNotStartFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/quick-swipe.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "active-1", role: .active)
        await service.updateConsumption(clipID: "active-1", remoteURL: remote, watchedSeconds: 0.4, durationSeconds: 30)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertEqual(snap.cacheFillStarted, 0)
        let eligible = await service.testing_fillEligible(for: remote)
        XCTAssertFalse(eligible)
    }

    func testConsumptionThresholdStartsFillOnce() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/watch-me.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "active-2", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "active-2",
            knownAssetBytes: 8_000_000,
            avPlayerObservedBytes: 200_000
        )
        await service.updateConsumption(clipID: "active-2", remoteURL: remote, watchedSeconds: 2.5, durationSeconds: 30)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
        await service.updateConsumption(clipID: "active-2", remoteURL: remote, watchedSeconds: 6.5, durationSeconds: 30)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertEqual(snap.cacheFillStarted, 1)
        let fillStarted = await service.testing_fillStarted(for: remote)
        XCTAssertTrue(fillStarted)
        await service.updateConsumption(clipID: "active-2", remoteURL: remote, watchedSeconds: 10, durationSeconds: 30)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 1)
    }

    func testConservingNetworkDefersFullFileFill() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(
            testStore: store,
            allowsPersistentFullFileFill: { false }
        )
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/cellular-watch.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "cellular-1", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "cellular-1",
            knownAssetBytes: 53_000_000,
            avPlayerObservedBytes: 1_500_000
        )
        await service.updateConsumption(
            clipID: "cellular-1",
            remoteURL: remote,
            watchedSeconds: 6.5,
            durationSeconds: 30
        )
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().cacheFillStarted, 0)
        let fillStarted = await service.testing_fillStarted(for: remote)
        let inFlight = await service.testing_isFillInFlight(for: remote)
        XCTAssertFalse(fillStarted)
        XCTAssertFalse(inFlight)
    }

    func testDeferredCacheFillPolicyStages() {
        let asset: Int64 = 21_250_625
        let lowBytes: Int64 = 3_000_000
        let atTwo = ClipVideoCacheFillPolicy.deferredCacheFillDecision(
            watchedSeconds: 2,
            knownAssetBytes: asset,
            avPlayerObservedBytes: lowBytes,
            avPlayerObservedBytesWhenPendingBegan: lowBytes,
            pendingBeganAtWatchedSeconds: 2,
            durationSeconds: 30
        )
        XCTAssertEqual(atTwo.decision, .pending)
        XCTAssertEqual(atTwo.stage, .initial)

        let atSix = ClipVideoCacheFillPolicy.deferredCacheFillDecision(
            watchedSeconds: 6,
            knownAssetBytes: asset,
            avPlayerObservedBytes: lowBytes,
            avPlayerObservedBytesWhenPendingBegan: lowBytes,
            pendingBeganAtWatchedSeconds: 2,
            durationSeconds: 30
        )
        XCTAssertEqual(atSix.decision, .startFill)
        XCTAssertEqual(atSix.stage, .final)
    }

    func testFillCancelledWhenMaterialFractionEmergesDuringDownload() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/cancel-material.mp4")!
        _ = await service.playbackURL(remoteURL: remote, clipID: "cancel-material", role: .active)
        await service.testing_seedNetworkMetrics(
            remoteURL: remote,
            clipID: "cancel-material",
            knownAssetBytes: 10_000_000,
            avPlayerObservedBytes: 300_000
        )
        await service.testing_simulateFillInFlight(remoteURL: remote, clipID: "cancel-material")
        await service.testing_recordAvPlayerSessionBytes(
            remoteURL: remote,
            clipID: "cancel-material",
            sessionItemBytes: 4_200_000,
            deltaBytes: 3_900_000
        )
        await service.testing_cancelInFlightFillIfDuplicateRisk(for: remote)
        let cancelledState = await service.testing_cacheDecisionState(for: remote)
        let inFlightAfterCancel = await service.testing_isFillInFlight(for: remote)
        XCTAssertEqual(cancelledState, .cancelledDuplicateRisk)
        XCTAssertFalse(inFlightAfterCancel)
    }

    func testPrefetchFullDownloadsTelemetryInvariant() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let service = ClipVideoDeliveryService(testStore: store)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/invariant.mp4")!
        ClipVideoDeliveryTelemetry.resetViewerSession()
        _ = await service.playbackURL(remoteURL: remote, clipID: "pf", role: .prefetch)
        await service.notePrefetchDiscarded(cacheKey: ClipVideoCacheIdentity.cacheKey(for: remote))
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().prefetchFullDownloads, 0)
    }

    func testClearAllContentsRemovesCachedFilesAndIndex() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let key = "clear-me"
        let staged = tempRoot.appendingPathComponent("clear.mp4")
        try writeMinimalMP4(at: staged, padding: 64)
        _ = try await store.completeDownload(cacheKey: key, urlIdentity: "id", stagedFileURL: staged)
        let countBeforeClear = await store.entryCount()
        XCTAssertEqual(countBeforeClear, 1)

        await store.clearAllContents()

        let countAfterClear = await store.entryCount()
        XCTAssertEqual(countAfterClear, 0)
        let readyAfterClear = await store.readyFileURL(for: key)
        XCTAssertNil(readyAfterClear)
        let indexURL = tempRoot.appendingPathComponent("index.json")
        let indexData = try Data(contentsOf: indexURL)
        let decoded = try JSONDecoder().decode(ClipPersistentVideoCacheStore.Index.self, from: indexData)
        XCTAssertTrue(decoded.entries.isEmpty)
        let remaining = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.lastPathComponent, "index.json")
    }

    func testDeliveryServiceClearPersistentCacheForColdTest() async throws {
        let store = try ClipPersistentVideoCacheStore(rootDirectory: tempRoot)
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/cold.mp4")!
        let key = ClipVideoCacheIdentity.cacheKey(for: remote)
        let staged = tempRoot.appendingPathComponent("cold.mp4")
        try writeMinimalMP4(at: staged)
        _ = try await store.completeDownload(cacheKey: key, urlIdentity: "x", stagedFileURL: staged)

        let service = ClipVideoDeliveryService(testStore: store)
        _ = await service.playbackURL(remoteURL: remote, clipID: "cold-1", role: .active)
        await service.updateConsumption(clipID: "cold-1", remoteURL: remote, watchedSeconds: 3, durationSeconds: 30)

        await service.clearPersistentCacheForColdTest()

        let entryCountAfterClear = await store.entryCount()
        XCTAssertEqual(entryCountAfterClear, 0)
        let afterClear = await service.playbackURL(remoteURL: remote, clipID: "cold-1", role: .active)
        assertPlaybackSource(afterClear.source, expected: .network)
        let fillStarted = await service.testing_fillStarted(for: remote)
        XCTAssertFalse(fillStarted)
    }

    func testPrefetchDiscardedTelemetry() async {
        ClipVideoDeliveryTelemetry.resetViewerSession()
        let remote = URL(string: "https://example.supabase.co/storage/v1/object/public/reels/u/videos/3-clip.mp4")!
        let service = ClipVideoDeliveryService(store: nil)
        _ = await service.playbackURL(remoteURL: remote, clipID: "b", role: .prefetch)
        let key = await service.cacheKey(for: remote)
        await service.notePrefetchDiscarded(cacheKey: key)
        XCTAssertEqual(ClipVideoDeliveryTelemetry.snapshot().prefetchFullDownloads, 0)
        let snap = ClipVideoDeliveryTelemetry.snapshot()
        XCTAssertEqual(snap.prefetchStarted, 1)
        XCTAssertEqual(snap.prefetchDiscarded, 1)
    }

    // MARK: - Helpers

    private func assertPlaybackSource(_ source: ClipVideoPlaybackSource, expected: ClipVideoPlaybackSource) {
        switch (source, expected) {
        case (.persistentDisk, .persistentDisk), (.network, .network):
            return
        default:
            XCTFail("Expected \(expected), got \(source)")
        }
    }

    private func writeMinimalMP4(at url: URL, padding: Int = 0) throws {
        var data = Data(count: 8)
        data[4 ..< 8] = Data("ftyp".utf8)
        if padding > 0 {
            data.append(Data(repeating: 0x00, count: padding))
        }
        try data.write(to: url)
    }
}
