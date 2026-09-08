import AVFoundation
import Foundation
import Observation

/// Instagram-style feed clip autoplay — one active player, visibility- or pager-driven (no polling).
@Observable
@MainActor
final class FeedVideoPlaybackCoordinator {
    private(set) var activeReelID: ReelID?
    private(set) var isClipsExperience = false
    var isMuted = true {
        didSet {
            for player in players.values {
                player.isMuted = isMuted
            }
        }
    }

    private let storage: any ObjectStorageProviding
    private var players: [ReelID: AVPlayer] = [:]
    private var loopObservers: [ReelID: NSObjectProtocol] = [:]
    private var manuallyPausedReelIDs: Set<ReelID> = []

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
        pauseAll()
    }

    func isActive(_ reelID: ReelID) -> Bool {
        activeReelID == reelID
    }

    func shouldShowPlayIndicator(for reelID: ReelID) -> Bool {
        if !isActive(reelID) {
            return true
        }
        return manuallyPausedReelIDs.contains(reelID)
    }

    func player(for reel: Reel) -> AVPlayer? {
        if let existing = players[reel.id] {
            return existing
        }
        guard let url = MediaURLResolver.url(
            for: reel.video,
            bucket: .reels,
            storage: storage
        ) else {
            return nil
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .pause
        players[reel.id] = player

        loopObservers[reel.id] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        return player
    }

    /// Called from `onScrollVisibilityChange` on each inline feed clip row.
    func setClipVisible(_ reelID: ReelID, visible: Bool) {
        guard !isClipsExperience else { return }
        if visible {
            if activeReelID != reelID {
                if let previous = activeReelID {
                    players[previous]?.pause()
                }
                activeReelID = reelID
                if !manuallyPausedReelIDs.contains(reelID) {
                    players[reelID]?.play()
                }
            }
        } else if activeReelID == reelID {
            players[reelID]?.pause()
            activeReelID = nil
            manuallyPausedReelIDs.remove(reelID)
        }
    }

    /// Full-screen Clips pager — exactly one active clip with audio.
    func setActiveClip(_ reel: Reel, neighborReels: [Reel] = []) {
        guard isClipsExperience else { return }
        for neighbor in neighborReels {
            preparePlayback(for: neighbor)
        }
        let reelID = reel.id
        for (playerID, player) in players where playerID != reelID {
            player.pause()
            manuallyPausedReelIDs.remove(playerID)
        }
        activeReelID = reelID
        _ = player(for: reel)
        if !manuallyPausedReelIDs.contains(reelID) {
            players[reelID]?.play()
        }
    }

    func preparePlayback(for reel: Reel) {
        _ = player(for: reel)
    }

    func syncPlayback(for reelID: ReelID) {
        guard activeReelID == reelID else { return }
        guard !manuallyPausedReelIDs.contains(reelID) else { return }
        players[reelID]?.play()
    }

    func togglePlayPause(for reel: Reel) {
        preparePlayback(for: reel)
        let reelID = reel.id
        guard let player = players[reelID] else { return }

        if isActive(reelID), !manuallyPausedReelIDs.contains(reelID) {
            player.pause()
            manuallyPausedReelIDs.insert(reelID)
            return
        }

        manuallyPausedReelIDs.remove(reelID)
        if let previous = activeReelID, previous != reelID {
            players[previous]?.pause()
        }
        activeReelID = reelID
        player.play()
    }

    func toggleMute() {
        isMuted.toggle()
    }

    /// Clips comments sheet — keep the active clip playing; block pager scroll separately.
    func setCommentsSheetPresented(_ presented: Bool) {
        isCommentsSheetPresented = presented
        guard isClipsExperience, presented, let activeReelID else { return }
        syncPlayback(for: activeReelID)
    }

    func pauseAll() {
        for player in players.values {
            player.pause()
        }
        activeReelID = nil
        manuallyPausedReelIDs.removeAll()
    }
}
