import AVFoundation
import Foundation
import Observation
import UIKit

/// Instagram-style feed clip autoplay — exactly one retained ``AVPlayer`` at a time.
@Observable
@MainActor
final class FeedVideoPlaybackCoordinator {
    private enum InlineStickyPolicy {
        static let startThreshold: CGFloat = 0.60
        static let keepThreshold: CGFloat = 0.28
    }

    private enum FreezePolicy {
        static let minimumPlaybackSeconds: Double = 0.15
    }

    private struct InlineClipSessionState {
        var lastPlaybackTime: CMTime = .zero
        var frozenFrame: UIImage?
        var hasRenderedVideo = false
        var didCaptureFreeze = false
    }

    /// Time-observer token bound to the exact ``AVPlayer`` instance that registered it.
    private struct PlayerTimeObserverRegistration {
        let player: AVPlayer
        let token: Any
    }

    private(set) var activeReelID: ReelID?
    private(set) var isClipsExperience = false
    /// False when Feed tab is inactive or another screen covers Feed home (stack push).
    private(set) var isSurfaceActive = true
    /// Feed-session mute preference — shared across inline Feed clips until toggled.
    var isMuted = true {
        didSet {
            for (reelID, player) in players {
                applyAudioState(to: player, for: reelID)
            }
        }
    }

    var retainedPlayerCount: Int {
        players.count
    }

    private let storage: any ObjectStorageProviding
    private var players: [ReelID: AVPlayer] = [:]
    private var presentationInfo: [ReelID: VideoPresentationInfo] = [:]
    private var loopObservers: [ReelID: NSObjectProtocol] = [:]
    private var accessLogObservers: [ReelID: NSObjectProtocol] = [:]
    private var readinessObservers: [ReelID: NSKeyValueObservation] = [:]
    private var playerReadyReelIDs: Set<ReelID> = []
    private var seekCompleteReelIDs: Set<ReelID> = []
    /// True only while ``AVPlayerLayer`` is actively displaying a video frame for this reel.
    private var displayingVideoFrameReelIDs: Set<ReelID> = []
    private var manuallyPausedReelIDs: Set<ReelID> = []
    private var clipVisibilityFractions: [ReelID: CGFloat] = [:]
    private var reelsByID: [ReelID: Reel] = [:]
    private var inlineSessionStates: [ReelID: InlineClipSessionState] = [:]
    private var inlineSessionAccessOrder: [ReelID] = []
    private var preparationGeneration: [ReelID: UInt64] = [:]
    private var globalGeneration: UInt64 = 0
    private var freezeCaptureTasks: [ReelID: Task<Void, Never>] = [:]
    private let maxInlineFrozenFrames = 10
    private var preparedNeighborReelID: ReelID?
    private var preparedNeighborIndex: Int?
    private var playbackStartedAt: [ReelID: Date] = [:]
    private var completedViewReelIDs: Set<ReelID> = []
    private var consumptionTimeObservers: [ReelID: PlayerTimeObserverRegistration] = [:]
    /// Prevents overlapping async player builds for the same reel (e.g. onAppear + scenePhase).
    private var preparingActiveReelIDs: Set<ReelID> = []
    private let networkPosture: any ClipPlaybackNetworkPostureProviding
    private var playerStartReasons: [ReelID: String] = [:]
    private var bandwidthSnapshots: [ReelID: ClipBandwidthSnapshot] = [:]
    #if DEBUG
    private var loggedFirstFrameReelIDs: Set<ReelID> = []
    #endif

    private struct ClipBandwidthSnapshot {
        var bytesTransferred: Int64 = 0
        var rawBytesTransferred: Int64 = 0
        var playbackSeconds: Double = 0
        var mediaRequests: Int = 0
        var bufferedAheadSeconds: Double?
        var indicatedBitrate: Double?
        var observedBitrate: Double?
    }

    var objectStorage: any ObjectStorageProviding { storage }

    init(
        storage: any ObjectStorageProviding,
        networkPosture: any ClipPlaybackNetworkPostureProviding = ClipPlaybackLiveNetworkPosture()
    ) {
        self.storage = storage
        self.networkPosture = networkPosture
    }

    private func currentBufferConfiguration() -> ClipPlaybackBufferConfiguration {
        ClipPlaybackBufferConfiguration.make(for: networkPosture.currentPosture())
    }

    private(set) var isCommentsSheetPresented = false

    /// Feed tab visibility + Feed home root (not covered by stack pushes).
    func setSurfaceActive(_ active: Bool, reason: String) {
        isSurfaceActive = active
        guard !active else { return }
        #if DEBUG
        VideoPlaybackLifecycleLog.stop(
            owner: isClipsExperience ? "clips" : "feed",
            reason: reason
        )
        #endif
        releaseAllPlayers(reason: reason)
    }

    func beginClipsExperience() {
        isClipsExperience = true
        isMuted = false
        ClipVideoDeliveryTelemetry.resetViewerSession()
        #if DEBUG
        ClipPlayerIdentityTrace.resetSession()
        ClipAVPlayerEgressTelemetry.resetSession()
        #endif
    }

    func endClipsExperience() {
        isClipsExperience = false
        isMuted = true
        flushPlaybackDurationTelemetry()
        ClipVideoDeliveryTelemetry.logSessionSummary(context: "clipsExperienceEnded")
        ClipVideoTransferTelemetry.logSessionEgressSummary(context: "clipsExperienceEnded")
        #if DEBUG
        ClipAVPlayerEgressTelemetry.logExperienceSummary(context: "clipsExperienceEnded")
        #endif
        preparedNeighborReelID = nil
        preparedNeighborIndex = nil
        releaseAllPlayers(reason: "clipsExperienceEnded")
    }

    func isActive(_ reelID: ReelID) -> Bool {
        activeReelID == reelID
    }

    func shouldShowLivePlayer(for reelID: ReelID) -> Bool {
        isActive(reelID)
            && playerReadyReelIDs.contains(reelID)
            && seekCompleteReelIDs.contains(reelID)
            && players[reelID] != nil
    }

    func frozenFrame(for reelID: ReelID) -> UIImage? {
        inlineSessionStates[reelID]?.frozenFrame
    }

    func hasRenderedFrame(for reelID: ReelID) -> Bool {
        let state = inlineSessionStates[reelID]
        return state?.hasRenderedVideo == true || state?.frozenFrame != nil
    }

    /// Poster stays visible until the inline layer is actually rendering video (not merely allocated).
    func shouldHidePoster(for reelID: ReelID) -> Bool {
        if shouldShowLivePlayer(for: reelID) {
            return displayingVideoFrameReelIDs.contains(reelID)
        }
        return frozenFrame(for: reelID) != nil
    }

    func noteVideoReadyForDisplay(_ reelID: ReelID) {
        displayingVideoFrameReelIDs.insert(reelID)
        markRenderedVideo(reelID)
    }

    func noteVideoDisplayLost(_ reelID: ReelID) {
        displayingVideoFrameReelIDs.remove(reelID)
    }

    func shouldShowPlayIndicator(for reelID: ReelID) -> Bool {
        if !isActive(reelID) {
            return true
        }
        return manuallyPausedReelIDs.contains(reelID)
    }

    func player(for reelID: ReelID) -> AVPlayer? {
        guard isActive(reelID) else { return nil }
        return players[reelID]
    }

    func presentation(for reelID: ReelID) -> VideoPresentationInfo? {
        presentationInfo[reelID]
    }

    func updateInlineClipVisibility(reel: Reel, fraction: CGFloat) {
        guard isSurfaceActive else { return }
        guard !isClipsExperience else { return }
        let reelID = reel.id
        reelsByID[reelID] = reel
        let clamped = min(1, max(0, fraction))
        let previous = clipVisibilityFractions[reelID] ?? -1
        clipVisibilityFractions[reelID] = clamped

        guard abs(previous - clamped) >= 0.03
            || crossesStickyThreshold(previous: previous, next: clamped)
            || resolveStickyOwner() != activeReelID
        else {
            return
        }

        applyStickyOwnershipIfNeeded()
    }

    func setClipVisible(_ reel: Reel, visible: Bool) {
        updateInlineClipVisibility(reel: reel, fraction: visible ? 1 : 0)
    }

    func setActiveClip(_ reel: Reel, atIndex index: Int? = nil) {
        guard isSurfaceActive else { return }
        guard isClipsExperience else { return }
        let reelID = reel.id
        reelsByID[reelID] = reel

        #if DEBUG
        ClipsPagerPlaybackProbe.pageBecameActive(clipID: reelID.rawValue, index: index)
        #endif

        let previous = activeReelID
        activeReelID = reelID

        let promotingPrefetch = preparedNeighborReelID == reelID
        if promotingPrefetch {
            preparedNeighborReelID = nil
            preparedNeighborIndex = nil
            notePrefetchViewed(for: reel)
            if let player = players[reelID], let item = player.currentItem {
                ClipPlayerIdentityTrace.log(
                    clipID: reelID.rawValue,
                    event: .promotePrefetchToActive,
                    player: player,
                    item: item,
                    role: "active",
                    reason: "clipsPageActive"
                )
                #if DEBUG
                ClipAVPlayerEgressTelemetry.logPrefetchEgress(clipID: reelID.rawValue, becameActive: true)
                #endif
            }
        }

        if let previous, previous != reelID {
            hardReleasePlayer(for: previous, reason: "clipsPagerSwitch")
        }

        if !currentBufferConfiguration().allowsNeighborPrefetch,
           let neighbor = preparedNeighborReelID,
           neighbor != reelID
        {
            hardReleasePlayer(for: neighbor, reason: "prefetchSuppressedConstrainedNetwork")
        }

        enforceClipsPlayerBudget(keeping: reelID)
        prepareAndPlay(reel, isCurrentPage: true, reason: "clipsPageActive")
        logPlayerState()
    }

    /// Lightweight neighbor preparation — one paused player ahead/behind the active clip.
    func prepareNeighborClip(_ reel: Reel, atIndex index: Int) {
        guard isSurfaceActive else { return }
        guard isClipsExperience else { return }
        let reelID = reel.id
        guard reelID != activeReelID else { return }
        let bufferConfiguration = currentBufferConfiguration()
        guard bufferConfiguration.allowsNeighborPrefetch else {
            if let neighbor = preparedNeighborReelID {
                hardReleasePlayer(for: neighbor, reason: "prefetchSuppressedConstrainedNetwork")
            }
            logTransferSnapshot(
                reelID: reelID,
                event: "prefetchSkipped",
                role: "prefetch",
                lifecycle: "offscreen",
                startReason: "prefetchSuppressedConstrainedNetwork",
                stopReason: "constrainedNetwork",
                item: nil,
                player: nil
            )
            return
        }
        guard players[reelID] == nil || preparedNeighborReelID == reelID else {
            if players[reelID] != nil {
                preparedNeighborReelID = reelID
                preparedNeighborIndex = index
            }
            return
        }

        if let old = preparedNeighborReelID, old != reelID {
            #if DEBUG
            ClipsPagerPrefetchProbe.cancelled(
                clipID: old.rawValue,
                index: preparedNeighborIndex
            )
            #endif
            notePrefetchDiscarded(forReelID: old)
            hardReleasePlayer(for: old, reason: "prefetchReplace")
        }

        preparedNeighborReelID = reelID
        preparedNeighborIndex = index
        reelsByID[reelID] = reel

        if players[reelID] != nil {
            return
        }

        #if DEBUG
        ClipsPagerPrefetchProbe.prepareStarted(clipID: reelID.rawValue, index: index)
        #endif
        Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            MainThreadWorkProbe.measure("feed.player.prepare", surface: "feed") {
                self.preparePlayerOnly(reel: reel, atIndex: index)
            }
            self.enforceClipsPlayerBudget(keeping: self.activeReelID)
        }
    }

    func syncPlayback(for reelID: ReelID) {
        guard activeReelID == reelID else { return }
        guard let player = players[reelID] else { return }
        playPlayer(
            player,
            reelID: reelID,
            reason: "syncPlayback",
            reel: reelsByID[reelID],
            isCurrentPage: isClipsExperience ? true : nil
        )
    }

    func togglePlayPause(for reel: Reel) {
        let reelID = reel.id
        if isActive(reelID), let player = players[reelID], !manuallyPausedReelIDs.contains(reelID) {
            pausePlayer(player, reelID: reelID, reason: "userToggle", userInitiated: true)
            savePlaybackTime(reelID, player.currentItem?.currentTime() ?? .zero)
            manuallyPausedReelIDs.insert(reelID)
            logPlayerState()
            return
        }

        reelsByID[reelID] = reel
        manuallyPausedReelIDs.remove(reelID)
        if activeReelID != reelID {
            transferOwnership(to: reelID, reason: "manualPlaySwitch")
        } else if let player = players[reelID] {
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .resume,
                player: player,
                item: player.currentItem,
                role: "active",
                reason: "userResume"
            )
            playPlayer(player, reelID: reelID, reason: "userResume", reel: reel, userInitiated: true)
        }
        logPlayerState()
    }

    func toggleMute() {
        let before = isMuted
        isMuted.toggle()
        let activeID = activeReelID?.rawValue ?? "nil"
        let isPlaying = activeReelID.flatMap { players[$0]?.rate ?? 0 > 0.01 } ?? false
        InlineClipAudioDiagnostics.log(
            clipID: activeID,
            action: isMuted ? "mute" : "unmute",
            before: before,
            after: isMuted,
            isPlaying: isPlaying
        )
    }

    func setCommentsSheetPresented(_ presented: Bool) {
        isCommentsSheetPresented = presented
        guard isClipsExperience, presented, let activeReelID else { return }
        syncPlayback(for: activeReelID)
    }

    func pauseAll(reason: String = "pauseAll") {
        for (reelID, player) in players {
            pausePlayer(player, reelID: reelID, reason: reason)
        }
        activeReelID = nil
        manuallyPausedReelIDs.removeAll()
        logPlayerState()
    }

    func releaseAllPlayers(reason: String = "releaseAll") {
        MainThreadWorkProbe.measure("feed.releaseAllPlayers", surface: "feed") {
            globalGeneration &+= 1
            cancelAllFreezeCaptures()
            for reelID in Array(players.keys) {
                hardReleasePlayer(for: reelID, reason: reason)
            }
        }
        activeReelID = nil
        manuallyPausedReelIDs.removeAll()
        clipVisibilityFractions.removeAll()
        reelsByID.removeAll()
        preparedNeighborReelID = nil
        preparedNeighborIndex = nil
        logPlayerState()
    }

    // MARK: - Sticky inline ownership

    private func applyStickyOwnershipIfNeeded() {
        let target = resolveStickyOwner()
        guard target != activeReelID else {
            resumeActivePlaybackIfNeeded()
            return
        }
        transferOwnership(to: target, reason: ownershipReason(for: target))
    }

    private func crossesStickyThreshold(previous: CGFloat, next: CGFloat) -> Bool {
        func crossed(_ threshold: CGFloat) -> Bool {
            (previous < threshold && next >= threshold) || (previous >= threshold && next < threshold)
        }
        return crossed(InlineStickyPolicy.startThreshold) || crossed(InlineStickyPolicy.keepThreshold)
    }

    private func resolveStickyOwner() -> ReelID? {
        if let current = activeReelID {
            let currentFraction = clipVisibilityFractions[current] ?? 0
            if currentFraction >= InlineStickyPolicy.keepThreshold {
                return current
            }
        }

        let starters = clipVisibilityFractions.filter {
            $0.value >= InlineStickyPolicy.startThreshold
        }
        return starters.max(by: { $0.value < $1.value })?.key
    }

    private func ownershipReason(for target: ReelID?) -> String {
        guard let target else {
            return activeReelID == nil ? "unchanged" : "belowKeepNoStarter"
        }
        if activeReelID == nil { return "initialStart" }
        if activeReelID == target { return "unchanged" }
        return "previousBelowKeep"
    }

    private func transferOwnership(to target: ReelID?, reason: String) {
        let from = activeReelID
        guard from != target else { return }

        if let from {
            deactivateInlineClip(from, reason: reason)
        }

        activeReelID = target

        if let target, let reel = reelsByID[target], !manuallyPausedReelIDs.contains(target) {
            Task { @MainActor [weak self] in
                guard self?.activeReelID == target else { return }
                self?.prepareAndPlay(reel, reason: reason)
            }
        }

        InlineClipOwnershipDiagnostics.log(
            from: from?.rawValue,
            to: target?.rawValue,
            reason: reason,
            currentVisibility: from.flatMap { clipVisibilityFractions[$0] } ?? 0,
            candidateVisibility: target.flatMap { clipVisibilityFractions[$0] } ?? 0
        )
        logPlayerState()
    }

    private func resumeActivePlaybackIfNeeded() {
        guard let activeReelID,
              !manuallyPausedReelIDs.contains(activeReelID),
              let player = players[activeReelID],
              player.rate < 0.01
        else { return }
        playPlayer(
            player,
            reelID: activeReelID,
            reason: "resumeAfterVisibilityHold",
            reel: reelsByID[activeReelID]
        )
    }

    private func deactivateInlineClip(_ reelID: ReelID, reason: String) {
        guard let player = players.removeValue(forKey: reelID) else { return }

        tearDownPlayerObservers(for: reelID)

        let time = player.currentItem?.currentTime() ?? .zero
        let asset = player.currentItem?.asset

        pausePlayer(player, reelID: reelID, reason: "ownershipLost:\(reason)")
        savePlaybackTime(reelID, time)
        manuallyPausedReelIDs.remove(reelID)

        if shouldScheduleFreezeCapture(reelID: reelID, time: time), let asset {
            scheduleSingleFreezeCapture(for: reelID, asset: asset, time: time, reason: reason)
        } else {
            InlineClipFreezeDiagnostics.log(
                clipID: reelID.rawValue,
                action: "skip",
                playbackTime: time.seconds,
                frameAvailable: inlineSessionStates[reelID]?.frozenFrame != nil,
                reason: inlineSessionStates[reelID]?.hasRenderedVideo == true
                    ? "playbackTimeTooEarly"
                    : "neverRendered"
            )
        }

        #if DEBUG
        if let item = player.currentItem {
            VideoAccessLogAccounting.unregisterItem(item)
        }
        #endif
        logPlayerRelease(reelID: reelID, reason: "ownershipLost:\(reason)", role: "active", player: player)
        if freezeCaptureTasks[reelID] != nil {
            // The freeze capture still needs this asset for one frame. Drop the player item
            // without cancelLoading so that single read can finish.
            player.replaceCurrentItem(with: nil)
        } else {
            ClipShortFormPlayerFactory.stopNetworkLoading(player)
        }
    }

    private func shouldScheduleFreezeCapture(reelID: ReelID, time: CMTime) -> Bool {
        guard inlineSessionStates[reelID]?.hasRenderedVideo == true else { return false }
        guard inlineSessionStates[reelID]?.didCaptureFreeze != true else { return false }
        guard time.isNumeric, time.seconds > FreezePolicy.minimumPlaybackSeconds else { return false }
        return true
    }

    private func scheduleSingleFreezeCapture(
        for reelID: ReelID,
        asset: AVAsset,
        time: CMTime,
        reason: String
    ) {
        freezeCaptureTasks[reelID]?.cancel()
        var state = inlineSessionStates[reelID, default: InlineClipSessionState()]
        state.didCaptureFreeze = true
        inlineSessionStates[reelID] = state

        freezeCaptureTasks[reelID] = Task.detached(priority: .utility) { [weak self] in
            let image = await InlineClipFrameCapture.captureFrame(asset: asset, time: time)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.freezeCaptureTasks[reelID] = nil
                guard let image else { return }
                var updated = self.inlineSessionStates[reelID, default: InlineClipSessionState()]
                updated.frozenFrame = image
                updated.hasRenderedVideo = true
                self.inlineSessionStates[reelID] = updated
                self.touchInlineSessionAccess(reelID)
                self.pruneInlineFrozenFramesIfNeeded()
                InlineClipFreezeDiagnostics.log(
                    clipID: reelID.rawValue,
                    action: "capture",
                    playbackTime: time.seconds,
                    frameAvailable: true,
                    reason: reason
                )
            }
        }
    }

    private func cancelAllFreezeCaptures() {
        for task in freezeCaptureTasks.values {
            task.cancel()
        }
        freezeCaptureTasks.removeAll()
    }

#if DEBUG
    func testing_drainInlineOwnership() async {
        for task in freezeCaptureTasks.values {
            await task.value
        }
    }

    /// Waits for async clip player / prefetch preparation (Phase 12A delivery resolution).
    func testing_playerInstanceID(for reelID: ReelID) -> ObjectIdentifier? {
        players[reelID].map(ObjectIdentifier.init)
    }

    func testing_drainClipVideoPreparation(
        expectedPlayers: Int? = nil,
        timeoutSeconds: Double = 3
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let prepDone = preparingActiveReelIDs.isEmpty
            let countOK = expectedPlayers.map { retainedPlayerCount >= $0 } ?? true
            if prepDone, countOK {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 25_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
#endif

    // MARK: - Session state

    private func savePlaybackTime(_ reelID: ReelID, _ time: CMTime) {
        var state = inlineSessionStates[reelID, default: InlineClipSessionState()]
        state.lastPlaybackTime = time
        inlineSessionStates[reelID] = state
        touchInlineSessionAccess(reelID)
    }

    private func markRenderedVideo(_ reelID: ReelID) {
        var state = inlineSessionStates[reelID, default: InlineClipSessionState()]
        state.hasRenderedVideo = true
        inlineSessionStates[reelID] = state
    }

    private func touchInlineSessionAccess(_ reelID: ReelID) {
        inlineSessionAccessOrder.removeAll { $0 == reelID }
        inlineSessionAccessOrder.append(reelID)
    }

    private func pruneInlineFrozenFramesIfNeeded() {
        while inlineSessionAccessOrder.count > maxInlineFrozenFrames {
            let evicted = inlineSessionAccessOrder.removeFirst()
            guard evicted != activeReelID else { continue }
            if var state = inlineSessionStates[evicted] {
                state.frozenFrame = nil
                inlineSessionStates[evicted] = state
            }
        }
    }

    private func savedPlaybackTime(for reelID: ReelID) -> CMTime? {
        guard let time = inlineSessionStates[reelID]?.lastPlaybackTime, time.isNumeric else { return nil }
        guard time.seconds > FreezePolicy.minimumPlaybackSeconds else { return nil }
        return time
    }

    // MARK: - Player lifecycle

    private func enforceClipsPlayerBudget(keeping activeID: ReelID?) {
        guard isClipsExperience else { return }
        var allowed = Set<ReelID>()
        if let activeID {
            allowed.insert(activeID)
        }
        if let preparedNeighborReelID {
            allowed.insert(preparedNeighborReelID)
        }
        for reelID in players.keys where !allowed.contains(reelID) {
            hardReleasePlayer(for: reelID, reason: "clipsPlayerBudget")
        }
    }

    private func preparePlayerOnly(reel: Reel, atIndex index: Int) {
        let reelID = reel.id
        guard isSurfaceActive else { return }
        guard isClipsExperience else { return }
        guard players[reelID] == nil else { return }
        guard let url = MediaURLResolver.url(
            for: reel.video,
            bucket: .reels,
            storage: storage
        ) else {
            return
        }

        preparationGeneration[reelID, default: 0] &+= 1
        let prepToken = preparationGeneration[reelID]!

        let prefetchBufferSeconds = currentBufferConfiguration().prefetchForwardBufferSeconds
        Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await ClipVideoDeliveryService.shared.playbackURL(
                remoteURL: url,
                clipID: reelID.rawValue,
                role: .prefetch
            )
            guard self.isSurfaceActive else { return }
            guard self.preparedNeighborReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                return
            }
            guard self.players[reelID] == nil else { return }
            guard self.currentBufferConfiguration().allowsNeighborPrefetch else {
                return
            }

            let built = ClipShortFormPlayerFactory.makePlayer(
                url: resolved.url,
                forwardBufferSeconds: prefetchBufferSeconds
            )
            let item = built.item
            let player = built.player
            self.applyAudioState(to: player, for: reelID)
            player.actionAtItemEnd = .pause
            player.pause()

            guard self.isSurfaceActive else {
                ClipShortFormPlayerFactory.stopNetworkLoading(player)
                return
            }
            guard self.preparedNeighborReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                ClipShortFormPlayerFactory.stopNetworkLoading(player)
                return
            }

            self.players[reelID] = player
            self.playerStartReasons[reelID] = "preparePlayerOnly"
            self.logTransferSnapshot(
                reelID: reelID,
                event: "playerCreated",
                role: "prefetch",
                lifecycle: "warm",
                startReason: "preparePlayerOnly",
                stopReason: nil,
                item: item,
                player: player
            )
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .createPlayer,
                player: player,
                item: item,
                role: "prefetch",
                reason: "preparePlayerOnly"
            )
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .createItem,
                player: player,
                item: item,
                role: "prefetch",
                reason: "preparePlayerOnly"
            )
            self.installLoopObserver(for: reel, item: item, player: player)
            #if DEBUG
            VideoHTTPAudit.probe(
                url: url,
                clipID: reelID.rawValue,
                surface: "clips",
                role: "prefetch"
            )
            #endif
            self.installAccessLogObserver(for: reelID, item: item, player: player)
            self.installReadinessObserver(
                for: reelID,
                item: item,
                prepToken: prepToken,
                prefetchIndex: index
            )
            self.warmPresentation(for: reel, prepToken: prepToken, asset: item.asset)

            #if DEBUG
            VideoTransferAudit.logPlayerCreated(
                clipID: reelID.rawValue,
                surface: "clips",
                role: "prefetch",
                player: player,
                item: item,
                preferredForwardBufferDuration: item.preferredForwardBufferDuration,
                canUseNetworkWhilePaused: item.canUseNetworkResourcesForLiveStreamingWhilePaused
            )
            #endif

            ClipBandwidthLogger.log(
                clipID: reelID.rawValue,
                event: .playerCreated,
                urlIdentity: reel.playbackURLIdentity,
                isVisible: false,
                isCurrentPage: false
            )
            #if DEBUG
            MediaLoadDiagnostics.log(
                contentType: "video/mp4",
                mediaID: reelID.rawValue,
                source: .clipsPrefetch,
                role: .prefetch,
                urlIdentity: reel.playbackURLIdentity,
                cacheHit: resolved.source == .persistentDisk,
                playerCreated: true,
                playerReused: false
            )
            #endif
        }
    }

    private func prepareAndPlay(_ reel: Reel, isCurrentPage: Bool? = nil, reason: String = "becameActive") {
        let reelID = reel.id
        guard isSurfaceActive else { return }
        guard activeReelID == reelID else { return }

        if var session = inlineSessionStates[reelID] {
            session.didCaptureFreeze = false
            inlineSessionStates[reelID] = session
        }

        if let existing = players[reelID] {
            existing.automaticallyWaitsToMinimizeStalling = false
            if let item = existing.currentItem {
                ClipShortFormPlayerFactory.applyBufferHint(
                    to: item,
                    forwardBufferSeconds: currentBufferConfiguration().activeForwardBufferSeconds
                )
            }
            if playerStartReasons[reelID] == nil {
                playerStartReasons[reelID] = reason
            }
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .reusePlayer,
                player: existing,
                item: existing.currentItem,
                role: "active",
                reason: reason
            )
            #if DEBUG
            ClipPlayerLifecycle.log(
                clipID: reelID.rawValue,
                player: existing,
                item: existing.currentItem,
                event: "reuse",
                reason: reason
            )
            MediaLoadDiagnostics.log(
                contentType: "video/mp4",
                mediaID: reelID.rawValue,
                source: isClipsExperience ? .clipsPager : .feedInline,
                role: .active,
                urlIdentity: reel.playbackURLIdentity,
                playerCreated: false,
                playerReused: true
            )
            #endif
            playPlayer(
                existing,
                reelID: reelID,
                reason: reason,
                reel: reel,
                isCurrentPage: isCurrentPage
            )
            warmPresentation(for: reel, prepToken: preparationGeneration[reelID] ?? 0)
            return
        }

        guard preparingActiveReelIDs.insert(reelID).inserted else {
            #if DEBUG
            ClipPlayerLifecycle.log(
                clipID: reelID.rawValue,
                player: nil,
                item: nil,
                event: "reuse",
                reason: "prepareAlreadyInFlight"
            )
            #endif
            return
        }

        preparationGeneration[reelID, default: 0] &+= 1
        let prepToken = preparationGeneration[reelID]!

        guard let url = MediaURLResolver.url(
            for: reel.video,
            bucket: .reels,
            storage: storage
        ) else {
            preparingActiveReelIDs.remove(reelID)
            return
        }

        Task { @MainActor [weak self] in
            defer { self?.preparingActiveReelIDs.remove(reelID) }
            guard let self else { return }
            guard self.isSurfaceActive else { return }
            guard self.activeReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                return
            }

            let deliveryRole: ClipVideoDeliveryRole = self.isClipsExperience ? .active : .active
            let resolved = await ClipVideoDeliveryService.shared.playbackURL(
                remoteURL: url,
                clipID: reelID.rawValue,
                role: deliveryRole
            )
            ClipVideoDeliveryTelemetry.record(.clipStart)

            let activeBufferSeconds = self.currentBufferConfiguration().activeForwardBufferSeconds
            let built = await Task.detached(priority: .userInitiated) {
                ClipShortFormPlayerFactory.makePlayer(
                    url: resolved.url,
                    forwardBufferSeconds: activeBufferSeconds
                )
            }.value

            guard self.isSurfaceActive else {
                ClipShortFormPlayerFactory.stopNetworkLoading(built.player)
                return
            }
            guard self.activeReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                ClipShortFormPlayerFactory.stopNetworkLoading(built.player)
                return
            }

            let item = built.item
            let player = built.player
            player.automaticallyWaitsToMinimizeStalling = false
            self.applyAudioState(to: player, for: reelID)
            player.actionAtItemEnd = .pause

            self.players[reelID] = player
            self.playerStartReasons[reelID] = reason
            self.seekCompleteReelIDs.remove(reelID)
            self.logTransferSnapshot(
                reelID: reelID,
                event: "playerCreated",
                role: "active",
                lifecycle: "active",
                startReason: reason,
                stopReason: nil,
                item: item,
                player: player
            )
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .createPlayer,
                player: player,
                item: item,
                role: "active",
                reason: reason
            )
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .createItem,
                player: player,
                item: item,
                role: "active",
                reason: reason
            )
            self.installLoopObserver(for: reel, item: item, player: player)
            #if DEBUG
            VideoHTTPAudit.probe(
                url: url,
                clipID: reelID.rawValue,
                surface: self.isClipsExperience ? "clips" : "feed",
                role: "active"
            )
            #endif
            self.installAccessLogObserver(for: reelID, item: item, player: player)
            self.installReadinessObserver(for: reelID, item: item, prepToken: prepToken, prefetchIndex: nil)

            #if DEBUG
            ClipPlayerLifecycle.log(
                clipID: reelID.rawValue,
                player: player,
                item: item,
                event: "create",
                reason: reason
            )
            VideoTransferAudit.logPlayerCreated(
                clipID: reelID.rawValue,
                surface: self.isClipsExperience ? "clips" : "feed",
                role: "active",
                player: player,
                item: item,
                preferredForwardBufferDuration: item.preferredForwardBufferDuration,
                canUseNetworkWhilePaused: item.canUseNetworkResourcesForLiveStreamingWhilePaused
            )
            #endif

            ClipBandwidthLogger.log(
                clipID: reelID.rawValue,
                event: .playerCreated,
                urlIdentity: reel.playbackURLIdentity,
                isVisible: self.isClipsExperience
                    ? (self.activeReelID == reelID)
                    : ((self.clipVisibilityFractions[reelID] ?? 0) > 0),
                isCurrentPage: isCurrentPage
            )
            #if DEBUG
            MediaLoadDiagnostics.log(
                contentType: "video/mp4",
                mediaID: reelID.rawValue,
                source: self.isClipsExperience ? .clipsPager : .feedInline,
                role: .active,
                urlIdentity: reel.playbackURLIdentity,
                cacheHit: resolved.source == .persistentDisk,
                playerCreated: true,
                playerReused: false
            )
            #endif

            self.warmPresentation(for: reel, prepToken: prepToken, asset: item.asset)
            self.startPlayback(
                player: player,
                reel: reel,
                reelID: reelID,
                isCurrentPage: isCurrentPage,
                reason: reason
            )
        }
    }

    private func startPlayback(
        player: AVPlayer,
        reel: Reel,
        reelID: ReelID,
        isCurrentPage: Bool?,
        reason: String
    ) {
        if let resumeTime = savedPlaybackTime(for: reelID) {
            InlineClipFreezeDiagnostics.log(
                clipID: reelID.rawValue,
                action: "resume",
                playbackTime: resumeTime.seconds,
                frameAvailable: inlineSessionStates[reelID]?.frozenFrame != nil,
                reason: "seekScheduled"
            )
            player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self, self.players[reelID] === player else { return }
                    if finished {
                        self.seekCompleteReelIDs.insert(reelID)
                    }
                    self.playPlayer(
                        player,
                        reelID: reelID,
                        reason: "resumeAfterSeek",
                        reel: reel,
                        isCurrentPage: isCurrentPage
                    )
                }
            }
        } else {
            seekCompleteReelIDs.insert(reelID)
            playPlayer(
                player,
                reelID: reelID,
                reason: reason,
                reel: reel,
                isCurrentPage: isCurrentPage
            )
        }
    }

    private func installReadinessObserver(
        for reelID: ReelID,
        item: AVPlayerItem,
        prepToken: UInt64,
        prefetchIndex: Int?
    ) {
        readinessObservers[reelID]?.invalidate()
        playerReadyReelIDs.remove(reelID)

        readinessObservers[reelID] = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.players[reelID] != nil else { return }
                guard self.preparationGeneration[reelID] == prepToken else { return }
                switch item.status {
                case .readyToPlay:
                    self.playerReadyReelIDs.insert(reelID)
                    if self.isClipsExperience {
                        if self.activeReelID == reelID {
                            FeedMediaReadyProbe.log(
                                itemID: reelID.rawValue,
                                kind: "clip-video",
                                source: "network"
                            )
                            if self.savedPlaybackTime(for: reelID) == nil {
                                self.seekCompleteReelIDs.insert(reelID)
                            }
                            if !self.manuallyPausedReelIDs.contains(reelID),
                               let player = self.players[reelID],
                               player.rate < 0.01
                            {
                                self.playPlayer(
                                    player,
                                    reelID: reelID,
                                    reason: "readyToPlay",
                                    reel: self.reelsByID[reelID],
                                    isCurrentPage: true
                                )
                            }
                        } else if self.preparedNeighborReelID == reelID, let prefetchIndex {
                            #if DEBUG
                            ClipsPagerPrefetchProbe.prepareReady(
                                clipID: reelID.rawValue,
                                index: prefetchIndex
                            )
                            #endif
                        }
                    } else {
                        FeedMediaReadyProbe.log(
                            itemID: reelID.rawValue,
                            kind: "clip-video",
                            source: "network"
                        )
                        if self.savedPlaybackTime(for: reelID) == nil {
                            self.seekCompleteReelIDs.insert(reelID)
                        }
                    }
                case .failed:
                    self.playerReadyReelIDs.remove(reelID)
                    self.seekCompleteReelIDs.remove(reelID)
                default:
                    break
                }
            }
        }
    }

    private func warmPresentation(
        for reel: Reel,
        prepToken: UInt64,
        asset: AVAsset? = nil
    ) {
        guard presentationInfo[reel.id] == nil else { return }
        let reelID = reel.id
        Task {
            let info: VideoPresentationInfo?
            if let asset {
                info = await VideoPresentationInfo.load(asset: asset)
            } else if let url = MediaURLResolver.url(
                for: reel.video,
                bucket: .reels,
                storage: storage
            ) {
                info = await VideoPresentationInfo.load(url: url)
            } else {
                info = nil
            }
            guard let info else { return }
            await MainActor.run {
                guard preparationGeneration[reelID] == prepToken else { return }
                presentationInfo[reelID] = info
                let surface: VideoPresentationSurface = isClipsExperience ? .clipsPager : .feedInline
                VideoPresentationProbe.log(
                    surface: surface,
                    info: info,
                    containerAspect: surface == .feedInline
                        ? info.containerAspectRatio(for: .feedInline)
                        : nil
                )
            }
        }
    }

    private func installLoopObserver(for reel: Reel, item: AVPlayerItem, player: AVPlayer) {
        let reelID = reel.id
        if let existing = loopObservers.removeValue(forKey: reelID) {
            NotificationCenter.default.removeObserver(existing)
        }
        loopObservers[reelID] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeReelID == reelID,
                      let activePlayer = self.players[reelID]
                else { return }
                if self.completedViewReelIDs.insert(reelID).inserted {
                    ClipVideoDeliveryTelemetry.record(.clipCompletedView)
                }
                ClipPlayerIdentityTrace.log(
                    clipID: reelID.rawValue,
                    event: .loopSeek,
                    player: activePlayer,
                    item: item,
                    role: "active",
                    reason: "loopRestart"
                )
                activePlayer.seek(to: .zero)
                self.savePlaybackTime(reelID, .zero)
                self.playPlayer(
                    activePlayer,
                    reelID: reelID,
                    reason: "loopRestart",
                    reel: reel
                )
            }
        }
    }

    private func installAccessLogObserver(for reelID: ReelID, item: AVPlayerItem, player: AVPlayer) {
        #if DEBUG
        if let existing = accessLogObservers.removeValue(forKey: reelID) {
            NotificationCenter.default.removeObserver(existing)
        }
        VideoAccessLogAccounting.registerItem(player: player, item: item)
        accessLogObservers[reelID] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAccessLog(for: reelID, item: item)
            }
        }
        #else
        _ = reelID
        _ = item
        _ = player
        #endif
    }

    #if DEBUG
    private func handleAccessLog(for reelID: ReelID, item: AVPlayerItem) {
        guard players[reelID] != nil else { return }
        guard let event = item.accessLog()?.events.last else { return }
        guard let accounting = VideoAccessLogAccounting.processNewAccessLogEntry(
            item: item,
            player: players[reelID]
        ) else { return }

        let surface = isClipsExperience ? "clips" : "feed"
        let role = activeReelID == reelID ? "active" : "prefetch"
        VideoTransferAudit.logAccessLogEvent(
            clipID: reelID.rawValue,
            surface: surface,
            role: role,
            item: item,
            accounting: accounting,
            reason: "accessLogNewEntry",
            waitsToMinimizeStalling: players[reelID]?.automaticallyWaitsToMinimizeStalling ?? false
        )
        if isClipsExperience,
           activeReelID == reelID,
           accounting.sessionItemBytes > 0,
           loggedFirstFrameReelIDs.insert(reelID).inserted
        {
            ClipsPagerPlaybackProbe.firstFrame(clipID: reelID.rawValue)
        }
        ClipBandwidthLogger.logAccessLog(
            clipID: reelID.rawValue,
            cumulativeBytes: accounting.sessionItemBytes,
            deltaBytes: accounting.newBytes,
            mediaRequests: event.numberOfMediaRequests,
            transferDuration: event.transferDuration,
            observedBitrate: event.observedBitrate
        )
        let playbackSeconds = ClipPlaybackBufferInspection.playbackSeconds(item: item)
        let snapshot = ClipBandwidthSnapshot(
            bytesTransferred: accounting.sessionItemBytes,
            rawBytesTransferred: accounting.rawReportedSessionItemBytes,
            playbackSeconds: playbackSeconds,
            mediaRequests: event.numberOfMediaRequests,
            bufferedAheadSeconds: ClipPlaybackBufferInspection.bufferedAheadSeconds(item: item),
            indicatedBitrate: event.indicatedBitrate.isFinite ? event.indicatedBitrate : nil,
            observedBitrate: event.observedBitrate.isFinite ? event.observedBitrate : nil
        )
        bandwidthSnapshots[reelID] = snapshot
        let labels = playbackLabels(for: reelID)
        logTransferSnapshot(
            reelID: reelID,
            event: "accessLog",
            role: labels.role,
            lifecycle: labels.lifecycle,
            startReason: playerStartReasons[reelID],
            stopReason: nil,
            item: item,
            player: players[reelID]
        )
        if accounting.newBytes > 0 {
            MediaEgressTracker.recordNetworkTransfer(
                type: .video,
                surface: isClipsExperience ? "clips" : "feed",
                mediaID: reelID.rawValue,
                bytes: Int(accounting.newBytes)
            )
            let roleLabel = activeReelID == reelID ? "active" : "prefetch"
            if isClipsExperience, let reel = reelsByID[reelID],
               let mediaURL = MediaURLResolver.url(for: reel.video, bucket: .reels, storage: storage)
            {
                Task {
                    await ClipVideoDeliveryService.shared.recordAVPlayerNetworkBytes(
                        clipID: reelID.rawValue,
                        remoteURL: mediaURL,
                        deltaBytes: accounting.newBytes,
                        sessionItemBytes: accounting.sessionItemBytes
                    )
                }
            } else {
                ClipVideoByteAccounting.recordAVPlayerDelta(
                    clipID: reelID.rawValue,
                    bytes: accounting.newBytes,
                    role: roleLabel
                )
            }
            if isClipsExperience {
                let reel = reelsByID[reelID]
                let resolvedMediaURL = reel.flatMap {
                    MediaURLResolver.url(for: $0.video, bucket: .reels, storage: storage)
                }
                let canonicalKey = resolvedMediaURL.map { ClipVideoCacheIdentity.cacheKey(for: $0) }
                    ?? reel?.playbackURLIdentity
                    ?? reelID.rawValue
                let playbackURL = event.uri.flatMap { URL(string: $0) } ?? resolvedMediaURL
                ClipColdTestTrace.recordPlaybackTransfer(
                    clipID: reelID.rawValue,
                    canonicalKey: canonicalKey,
                    role: roleLabel,
                    url: playbackURL,
                    deltaBytes: accounting.newBytes,
                    sessionItemBytes: accounting.sessionItemBytes,
                    accessLogEventIndex: accounting.eventIndex
                )
                ClipAVPlayerEgressTelemetry.recordPlaybackDelta(
                    clipID: reelID.rawValue,
                    role: roleLabel,
                    deltaBytes: accounting.newBytes,
                    sessionItemBytes: accounting.sessionItemBytes
                )
            }
        }
        MediaLoadDiagnostics.log(
            contentType: "video/mp4",
            mediaID: reelID.rawValue,
            source: isClipsExperience ? .clipsPager : .feedInline,
            role: activeReelID == reelID ? .active : .prefetch,
            byteCount: Int(accounting.sessionItemBytes),
            cacheHit: accounting.newBytes == 0 && accounting.sessionItemBytes > 0
        )
    }
    #endif

    private func hardReleasePlayer(for reelID: ReelID, reason: String) {
        let labels = playbackLabels(for: reelID)
        accumulatePlaybackDuration(for: reelID)
        if preparedNeighborReelID == reelID {
            notePrefetchDiscarded(forReelID: reelID)
        } else if activeReelID != reelID {
            noteClipAbandoned(forReelID: reelID)
        }
        preparationGeneration[reelID, default: 0] &+= 1
        tearDownPlayerObservers(for: reelID)
        freezeCaptureTasks[reelID]?.cancel()
        freezeCaptureTasks[reelID] = nil

        if preparedNeighborReelID == reelID {
            preparedNeighborReelID = nil
            preparedNeighborIndex = nil
        }
        #if DEBUG
        loggedFirstFrameReelIDs.remove(reelID)
        #endif

        if let player = players.removeValue(forKey: reelID) {
            pausePlayer(player, reelID: reelID, reason: "hardRelease:\(reason)")
            ClipPlayerIdentityTrace.log(
                clipID: reelID.rawValue,
                event: .discard,
                player: player,
                item: player.currentItem,
                role: activeReelID == reelID ? "active" : "prefetch",
                reason: reason
            )
            #if DEBUG
            if activeReelID != reelID {
                ClipAVPlayerEgressTelemetry.logPrefetchEgress(
                    clipID: reelID.rawValue,
                    becameActive: false
                )
            }
            ClipPlayerLifecycle.log(
                clipID: reelID.rawValue,
                player: player,
                item: player.currentItem,
                event: "destroy",
                reason: reason
            )
            if let item = player.currentItem {
                VideoAccessLogAccounting.unregisterItem(item)
            }
            #endif
            logPlayerRelease(
                reelID: reelID,
                reason: reason,
                role: labels.role,
                lifecycle: labels.lifecycle,
                player: player
            )
            ClipShortFormPlayerFactory.stopNetworkLoading(player)
        }
    }

    private func tearDownPlayerObservers(for reelID: ReelID) {
        removeConsumptionObserver(for: reelID)
        if let observer = loopObservers.removeValue(forKey: reelID) {
            NotificationCenter.default.removeObserver(observer)
        }
        readinessObservers.removeValue(forKey: reelID)?.invalidate()
        playerReadyReelIDs.remove(reelID)
        seekCompleteReelIDs.remove(reelID)
        displayingVideoFrameReelIDs.remove(reelID)
        #if DEBUG
        if let observer = accessLogObservers.removeValue(forKey: reelID) {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    // MARK: - Playback logging

    private func playPlayer(
        _ player: AVPlayer,
        reelID: ReelID,
        reason: String,
        reel: Reel? = nil,
        isCurrentPage: Bool? = nil,
        userInitiated: Bool = false
    ) {
        guard isSurfaceActive else { return }
        guard activeReelID == reelID else { return }
        guard !manuallyPausedReelIDs.contains(reelID) else { return }

        applyAudioState(to: player, for: reelID)
        #if DEBUG
        VideoPlaybackLifecycleLog.play(owner: isClipsExperience ? "clips" : "feed")
        #endif
        playbackStartedAt[reelID] = Date()
        let consumptionReel = reel ?? reelsByID[reelID]
        if let consumptionReel {
            installConsumptionObserver(for: reelID, player: player, reel: consumptionReel)
        }
        player.playImmediately(atRate: 1)

        if isClipsExperience, activeReelID == reelID {
            ClipsPagerPlaybackProbe.playRequested(clipID: reelID.rawValue)
        }

        InlineClipPlaybackDiagnostics.log(
            clipID: reelID.rawValue,
            action: "play",
            reason: reason,
            activeClipID: activeReelID?.rawValue,
            visibility: clipVisibilityFractions[reelID],
            userInitiated: userInitiated
        )
        ClipBandwidthLogger.log(
            clipID: reelID.rawValue,
            event: .play,
            urlIdentity: reel?.playbackURLIdentity,
            isCurrentPage: isCurrentPage
        )
    }

    private func pausePlayer(
        _ player: AVPlayer,
        reelID: ReelID,
        reason: String,
        userInitiated: Bool = false
    ) {
        player.pause()
        InlineClipPlaybackDiagnostics.log(
            clipID: reelID.rawValue,
            action: "pause",
            reason: reason,
            activeClipID: activeReelID?.rawValue,
            visibility: clipVisibilityFractions[reelID],
            userInitiated: userInitiated
        )
        ClipBandwidthLogger.log(clipID: reelID.rawValue, event: .pause)
    }

    private static func resolutionText(_ size: CGSize) -> String {
        if size.width <= 0 || size.height <= 0 { return "unrestricted" }
        return "\(Int(size.width))x\(Int(size.height))"
    }

    private func playbackLabels(for reelID: ReelID) -> (role: String, lifecycle: String) {
        if activeReelID == reelID { return ("active", "active") }
        if preparedNeighborReelID == reelID { return ("prefetch", "warm") }
        return ("offscreen", "offscreen")
    }

    private func logPlayerRelease(
        reelID: ReelID,
        reason: String,
        role: String,
        lifecycle: String? = nil,
        player: AVPlayer
    ) {
        let resolvedLifecycle = lifecycle ?? (role == "prefetch" ? "warm" : role)
        logTransferSnapshot(
            reelID: reelID,
            event: "playerReleased",
            role: role,
            lifecycle: resolvedLifecycle,
            startReason: playerStartReasons[reelID],
            stopReason: reason,
            item: player.currentItem,
            player: player
        )
        playerStartReasons[reelID] = nil
        bandwidthSnapshots[reelID] = nil
        InlineClipPlaybackDiagnostics.log(
            clipID: reelID.rawValue,
            action: "release",
            reason: reason,
            activeClipID: activeReelID?.rawValue,
            visibility: clipVisibilityFractions[reelID],
            userInitiated: false
        )
        ClipBandwidthLogger.log(clipID: reelID.rawValue, event: .playerReleased)
    }

    private func logTransferSnapshot(
        reelID: ReelID,
        event: String,
        role: String,
        lifecycle: String,
        startReason: String?,
        stopReason: String?,
        item: AVPlayerItem?,
        player: AVPlayer?
    ) {
        let configuration = currentBufferConfiguration()
        let snapshot = bandwidthSnapshots[reelID]
        let playbackSeconds = item.map(ClipPlaybackBufferInspection.playbackSeconds)
            ?? snapshot?.playbackSeconds
            ?? 0
        let playWallSeconds = playbackStartedAt[reelID].map { Date().timeIntervalSince($0) }
        #if DEBUG
        let assetBytes = ClipAVPlayerEgressTelemetry.knownAssetBytes(for: reelID.rawValue)
        #else
        let assetBytes: Int64? = nil
        #endif
        ClipBandwidthLogger.logTransferSnapshot(
            clipID: reelID.rawValue,
            event: event,
            role: role,
            lifecycle: lifecycle,
            assetBytes: assetBytes,
            bytesTransferred: snapshot?.bytesTransferred ?? 0,
            rawBytesTransferred: snapshot?.rawBytesTransferred ?? 0,
            playbackSeconds: playbackSeconds,
            networkClass: configuration.networkClass,
            startReason: startReason,
            stopReason: stopReason,
            forwardBufferSeconds: item?.preferredForwardBufferDuration
                ?? (role == "prefetch"
                    ? configuration.prefetchForwardBufferSeconds
                    : configuration.activeForwardBufferSeconds),
            waitsToMinimizeStalling: player?.automaticallyWaitsToMinimizeStalling
                ?? configuration.waitsToMinimizeStalling,
            bufferedAheadSeconds: item.flatMap(ClipPlaybackBufferInspection.bufferedAheadSeconds)
                ?? snapshot?.bufferedAheadSeconds,
            mediaRequests: snapshot?.mediaRequests,
            indicatedBitrate: snapshot?.indicatedBitrate ?? item?.accessLog()?.events.last?.indicatedBitrate,
            observedBitrate: snapshot?.observedBitrate ?? item?.accessLog()?.events.last?.observedBitrate,
            preferredPeakBitRate: item?.preferredPeakBitRate,
            preferredMaximumResolution: Self.resolutionText(item?.preferredMaximumResolution ?? .zero),
            playWallSeconds: playWallSeconds
        )
    }

    private func logPlayerState() {
        ClipPlaybackLogger.log(
            activeClip: activeReelID?.rawValue,
            retainedPlayers: retainedPlayerCount,
            visibleClips: clipVisibilityFractions.filter { $0.value > 0 }.count
        )
    }

    private func applyAudioState(to player: AVPlayer, for reelID: ReelID) {
        let shouldMute = reelID != activeReelID || isMuted
        FeedVideoAudioSession.applyMute(shouldMute, to: player)
    }

    // MARK: - DEBUG playback lifecycle

#if DEBUG
    private enum VideoPlaybackLifecycleLog {
        static func play(owner: String) {
            print("[VIDEO_PLAYBACK] owner=\(owner) action=play")
        }

        static func stop(owner: String, reason: String) {
            print("[VIDEO_PLAYBACK] owner=\(owner) action=stop reason=\(reason)")
        }

        static func stop(reason: String) {
            print("[VIDEO_PLAYBACK] action=stop reason=\(reason)")
        }
    }
#else
    private enum VideoPlaybackLifecycleLog {
        static func play(owner: String) {}
        static func stop(owner: String, reason: String) {}
        static func stop(reason: String) {}
    }
#endif

    // MARK: - Clip video delivery (Phase 12A)

    private func notePrefetchViewed(for reel: Reel) {
        guard let url = MediaURLResolver.url(for: reel.video, bucket: .reels, storage: storage) else { return }
        let key = ClipVideoCacheIdentity.cacheKey(for: url)
        Task {
            await ClipVideoDeliveryService.shared.notePrefetchViewed(cacheKey: key)
        }
    }

    private func notePrefetchDiscarded(for reel: Reel) {
        guard let url = MediaURLResolver.url(for: reel.video, bucket: .reels, storage: storage) else { return }
        let key = ClipVideoCacheIdentity.cacheKey(for: url)
        Task {
            await ClipVideoDeliveryService.shared.notePrefetchDiscarded(cacheKey: key)
        }
    }

    private func noteClipAbandoned(forReelID reelID: ReelID) {
        guard let reel = reelsByID[reelID],
              let url = MediaURLResolver.url(for: reel.video, bucket: .reels, storage: storage)
        else { return }
        let key = ClipVideoCacheIdentity.cacheKey(for: url)
        Task {
            await ClipVideoDeliveryService.shared.activeClipReleased(cacheKey: key)
        }
    }

    private func installConsumptionObserver(for reelID: ReelID, player: AVPlayer, reel: Reel) {
        removeConsumptionObserver(for: reelID)
        guard let url = MediaURLResolver.url(for: reel.video, bucket: .reels, storage: storage) else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard self != nil else { return }
            let watched = max(0, time.seconds)
            let duration = reel.durationSeconds.map(Double.init)
            Task {
                await ClipVideoDeliveryService.shared.updateConsumption(
                    clipID: reelID.rawValue,
                    remoteURL: url,
                    watchedSeconds: watched,
                    durationSeconds: duration
                )
            }
        }
        consumptionTimeObservers[reelID] = PlayerTimeObserverRegistration(player: player, token: token)
    }

    private func removeConsumptionObserver(for reelID: ReelID) {
        guard let registration = consumptionTimeObservers.removeValue(forKey: reelID) else { return }
        registration.player.removeTimeObserver(registration.token)
    }

    private func notePrefetchDiscarded(forReelID reelID: ReelID) {
        guard let reel = reelsByID[reelID] else { return }
        notePrefetchDiscarded(for: reel)
    }

    private func accumulatePlaybackDuration(for reelID: ReelID) {
        guard let started = playbackStartedAt.removeValue(forKey: reelID) else { return }
        let seconds = Date().timeIntervalSince(started)
        ClipVideoDeliveryTelemetry.record(.playbackSeconds(seconds))
    }

    private func flushPlaybackDurationTelemetry() {
        for reelID in Array(playbackStartedAt.keys) {
            accumulatePlaybackDuration(for: reelID)
        }
    }
}
