import AVFoundation
import Foundation

#if DEBUG
/// Phase 12D — AVPlayer / AVPlayerItem lifecycle identity (one player+item per retained clip).
nonisolated enum ClipPlayerIdentityTrace {
    enum Event: String, Sendable {
        case createPlayer
        case createItem
        case reusePlayer
        case promotePrefetchToActive
        case demoteActiveToPrefetch
        case discard
        case loopSeek
        case resume
    }

    private struct ClipCounts {
        var playerCreates: Int = 0
        var itemCreates: Int = 0
        var loopSeeks: Int = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var countsByClipID: [String: ClipCounts] = [:]

    nonisolated static func resetSession() {
        lock.lock()
        countsByClipID.removeAll()
        lock.unlock()
    }

    nonisolated static func log(
        clipID: String,
        event: Event,
        player: AVPlayer?,
        item: AVPlayerItem?,
        role: String,
        reason: String
    ) {
        let playerID = player.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let itemID = item.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        print(
            """
            [ClipPlayerIdentity] clipID=\(clipID) event=\(event.rawValue) \
            playerInstanceID=\(playerID) itemInstanceID=\(itemID) role=\(role) reason=\(reason)
            """
        )
        lock.lock()
        var counts = countsByClipID[clipID, default: ClipCounts()]
        switch event {
        case .createPlayer:
            counts.playerCreates += 1
        case .createItem:
            counts.itemCreates += 1
        case .loopSeek:
            counts.loopSeeks += 1
        case .reusePlayer, .promotePrefetchToActive, .demoteActiveToPrefetch, .discard, .resume:
            break
        }
        countsByClipID[clipID] = counts
        lock.unlock()
        ClipAVPlayerEgressTelemetry.noteIdentityEvent(clipID: clipID, event: event)
    }

    nonisolated static func counts(for clipID: String) -> (players: Int, items: Int, loops: Int) {
        lock.lock()
        defer { lock.unlock() }
        let c = countsByClipID[clipID] ?? ClipCounts()
        return (c.playerCreates, c.itemCreates, c.loopSeeks)
    }
}
#else
nonisolated enum ClipPlayerIdentityTrace {
    enum Event: String, Sendable {
        case createPlayer, createItem, reusePlayer, promotePrefetchToActive
        case demoteActiveToPrefetch, discard, loopSeek, resume
    }

    nonisolated static func resetSession() {}
    nonisolated static func log(
        clipID: String,
        event: Event,
        player: AVPlayer?,
        item: AVPlayerItem?,
        role: String,
        reason: String
    ) {}
}
#endif
