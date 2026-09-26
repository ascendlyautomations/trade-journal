import AVFoundation
import Foundation

#if DEBUG
/// Correct AVPlayerItem access-log byte accounting — events are per-request, not one session counter.
enum VideoAccessLogAccounting {
    struct DeltaResult: Sendable {
        var newBytes: Int64
        var eventIndex: Int
        var eventBytes: Int64
        var previousEventBytes: Int64
        var sessionItemBytes: Int64
        /// Sum of per-event `numberOfBytesTransferred` (can over-count overlapping requests).
        var rawReportedSessionItemBytes: Int64
        var sessionVideoBytes: Int64
        var accessLogEventCount: Int
        var playerInstanceID: String?
        var itemInstanceID: ObjectIdentifier
    }

    private struct ItemState {
        var eventCount: Int = 0
        var bytesByEventIndex: [Int: Int64] = [:]
        var sessionItemBytes: Int64 = 0
        var playerInstanceID: ObjectIdentifier?
        let itemInstanceID: ObjectIdentifier
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var items: [ObjectIdentifier: ItemState] = [:]
    nonisolated(unsafe) private static var sessionVideoBytes: Int64 = 0

    nonisolated static func registerItem(player: AVPlayer?, item: AVPlayerItem) {
        let key = ObjectIdentifier(item)
        lock.lock()
        defer { lock.unlock() }
        items[key] = ItemState(
            playerInstanceID: player.map(ObjectIdentifier.init),
            itemInstanceID: key
        )
    }

    nonisolated static func unregisterItem(_ item: AVPlayerItem) {
        lock.lock()
        defer { lock.unlock() }
        items.removeValue(forKey: ObjectIdentifier(item))
    }

    nonisolated static func processNewAccessLogEntry(
        item: AVPlayerItem,
        player: AVPlayer?
    ) -> DeltaResult? {
        guard let log = item.accessLog() else { return nil }
        let events = log.events
        guard !events.isEmpty else { return nil }

        let eventIndex = events.count - 1
        let lastEvent = events[eventIndex]
        let eventBytes = max(0, lastEvent.numberOfBytesTransferred)
        let key = ObjectIdentifier(item)

        lock.lock()
        defer { lock.unlock() }

        var state = items[key] ?? ItemState(itemInstanceID: key)
        if let player {
            state.playerInstanceID = ObjectIdentifier(player)
        }

        let previousEventBytes = state.bytesByEventIndex[eventIndex] ?? 0
        let newBytes: Int64
        if eventIndex >= state.eventCount {
            newBytes = eventBytes
            state.eventCount = events.count
        } else {
            newBytes = max(0, eventBytes - previousEventBytes)
        }

        state.bytesByEventIndex[eventIndex] = eventBytes
        let rawSum = state.bytesByEventIndex.values.reduce(0, +)
        state.sessionItemBytes = state.bytesByEventIndex.values.max() ?? 0
        sessionVideoBytes += newBytes
        items[key] = state

        return DeltaResult(
            newBytes: newBytes,
            eventIndex: eventIndex,
            eventBytes: eventBytes,
            previousEventBytes: previousEventBytes,
            sessionItemBytes: state.sessionItemBytes,
            rawReportedSessionItemBytes: rawSum,
            sessionVideoBytes: sessionVideoBytes,
            accessLogEventCount: events.count,
            playerInstanceID: state.playerInstanceID.map { String(describing: $0) },
            itemInstanceID: key
        )
    }
}
#else
enum VideoAccessLogAccounting {
    struct DeltaResult: Sendable {
        var newBytes: Int64 = 0
        var eventIndex: Int = 0
        var eventBytes: Int64 = 0
        var previousEventBytes: Int64 = 0
        var sessionItemBytes: Int64 = 0
        var rawReportedSessionItemBytes: Int64 = 0
        var sessionVideoBytes: Int64 = 0
        var accessLogEventCount: Int = 0
        var playerInstanceID: String?
        var itemInstanceID: ObjectIdentifier = ObjectIdentifier(NSObject())
    }

    nonisolated static func registerItem(player: AVPlayer?, item: AVPlayerItem) {}
    nonisolated static func unregisterItem(_ item: AVPlayerItem) {}
    nonisolated static func processNewAccessLogEntry(item: AVPlayerItem, player: AVPlayer?) -> DeltaResult? { nil }
}
#endif
