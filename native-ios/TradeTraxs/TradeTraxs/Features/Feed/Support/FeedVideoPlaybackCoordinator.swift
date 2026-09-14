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

    private enum PrefetchBufferPolicy {
        /// Neighbor clip — warm start without downloading the full object.
        static let forwardBufferSeconds: TimeInterval = 2
    }

    private enum ActiveBufferPolicy {
        /// Active Feed/Clips playback — preferred forward buffer target (not a hard byte cap).
        static let forwardBufferSeconds: TimeInterval = 4
    }

    private struct InlineClipSessionState {
        var lastPlaybackTime: CMTime = .zero
        var frozenFrame: UIImage?
        var hasRenderedVideo = false
        var didCaptureFreeze = false
    }

    private(set) var activeReelID: ReelID?
    private(set) var isClipsExperience = false
    /// Feed-session mute preference — shared across inline Feed clips until toggled.
    var isMuted = true {
        didSet {
            for player in players.values {
                applyAudioState(to: player)
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
    #if DEBUG
    private var loggedFirstFrameReelIDs: Set<ReelID> = []
    #endif

    init(storage: any ObjectStorageProviding) {
        self.storage = storage
    }

    private(set) var isCommentsSheetPresented = false

    func beginClipsExperience() {
        isClipsExperience = true
        isMuted = false
    }

    func endClipsExperience() {
        isClipsExperience = false
        isMuted = true
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
        guard isClipsExperience else { return }
        let reelID = reel.id
        reelsByID[reelID] = reel

        #if DEBUG
        ClipsPagerPlaybackProbe.pageBecameActive(clipID: reelID.rawValue, index: index)
        #endif

        let previous = activeReelID
        activeReelID = reelID

        if preparedNeighborReelID == reelID {
            preparedNeighborReelID = nil
            preparedNeighborIndex = nil
        }

        if let previous, previous != reelID {
            hardReleasePlayer(for: previous, reason: "clipsPagerSwitch")
        }

        enforceClipsPlayerBudget(keeping: reelID)
        prepareAndPlay(reel, isCurrentPage: true, reason: "clipsPageActive")
        logPlayerState()
    }

    /// Lightweight neighbor preparation — one paused player ahead/behind the active clip.
    func prepareNeighborClip(_ reel: Reel, atIndex index: Int) {
        guard isClipsExperience else { return }
        let reelID = reel.id
        guard reelID != activeReelID else { return }
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
        player.replaceCurrentItem(with: nil)
        logPlayerRelease(reelID: reelID, reason: "ownershipLost:\(reason)")
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

        let item = AVPlayerItem(url: url)
        configurePrefetchItem(item)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        applyAudioState(to: player)
        player.actionAtItemEnd = .pause
        player.pause()

        guard preparedNeighborReelID == reelID, preparationGeneration[reelID] == prepToken else {
            player.replaceCurrentItem(with: nil)
            return
        }

        players[reelID] = player
        installLoopObserver(for: reel, item: item, player: player)
        #if DEBUG
        VideoHTTPAudit.probe(
            url: url,
            clipID: reelID.rawValue,
            surface: "clips",
            role: "prefetch"
        )
        #endif
        installAccessLogObserver(for: reelID, item: item, player: player)
        installReadinessObserver(
            for: reelID,
            item: item,
            prepToken: prepToken,
            prefetchIndex: index
        )
        warmPresentation(for: reel, prepToken: prepToken, asset: item.asset)

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
            playerCreated: true,
            playerReused: false
        )
        #endif
    }

    private func prepareAndPlay(_ reel: Reel, isCurrentPage: Bool? = nil, reason: String = "becameActive") {
        let reelID = reel.id
        guard activeReelID == reelID else { return }

        if var session = inlineSessionStates[reelID] {
            session.didCaptureFreeze = false
            inlineSessionStates[reelID] = session
        }

        preparationGeneration[reelID, default: 0] &+= 1
        let prepToken = preparationGeneration[reelID]!

        if let existing = players[reelID] {
            if let item = existing.currentItem {
                configureActiveItem(item)
            }
            #if DEBUG
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
            warmPresentation(for: reel, prepToken: prepToken)
            return
        }

        guard let url = MediaURLResolver.url(
            for: reel.video,
            bucket: .reels,
            storage: storage
        ) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.activeReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                return
            }

            let built = await Task.detached(priority: .userInitiated) {
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                return (item, player)
            }.value

            guard self.activeReelID == reelID, self.preparationGeneration[reelID] == prepToken else {
                built.1.replaceCurrentItem(with: nil)
                return
            }

            let item = built.0
            let player = built.1
            player.automaticallyWaitsToMinimizeStalling = true
            self.configureActiveItem(item)
            self.applyAudioState(to: player)
            player.actionAtItemEnd = .pause

            self.players[reelID] = player
            self.seekCompleteReelIDs.remove(reelID)
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
            reason: "accessLogNewEntry"
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
        if accounting.newBytes > 0 {
            MediaEgressTracker.recordNetworkTransfer(
                type: .video,
                surface: isClipsExperience ? "clips" : "feed",
                mediaID: reelID.rawValue,
                bytes: Int(accounting.newBytes)
            )
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

    private func configurePrefetchItem(_ item: AVPlayerItem) {
        item.preferredForwardBufferDuration = PrefetchBufferPolicy.forwardBufferSeconds
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    private func configureActiveItem(_ item: AVPlayerItem) {
        item.preferredForwardBufferDuration = ActiveBufferPolicy.forwardBufferSeconds
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    private func hardReleasePlayer(for reelID: ReelID, reason: String) {
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
            #if DEBUG
            if let item = player.currentItem {
                VideoAccessLogAccounting.unregisterItem(item)
            }
            #endif
            player.replaceCurrentItem(with: nil)
            logPlayerRelease(reelID: reelID, reason: reason)
        }
    }

    private func tearDownPlayerObservers(for reelID: ReelID) {
        if let observer = loopObservers.removeValue(forKey: reelID) {
            NotificationCenter.default.removeObserver(observer)
        }
        readinessObservers.removeValue(forKey: reelID)?.invalidate()
        playerReadyReelIDs.remove(reelID)
        seekCompleteReelIDs.remove(reelID)
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
        guard activeReelID == reelID else { return }
        guard !manuallyPausedReelIDs.contains(reelID) else { return }

        applyAudioState(to: player)
        player.play()
        markRenderedVideo(reelID)

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

    private func logPlayerRelease(reelID: ReelID, reason: String) {
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

    private func logPlayerState() {
        ClipPlaybackLogger.log(
            activeClip: activeReelID?.rawValue,
            retainedPlayers: retainedPlayerCount,
            visibleClips: clipVisibilityFractions.filter { $0.value > 0 }.count
        )
    }

    private func applyAudioState(to player: AVPlayer) {
        FeedVideoAudioSession.applyMute(isMuted, to: player)
    }
}
