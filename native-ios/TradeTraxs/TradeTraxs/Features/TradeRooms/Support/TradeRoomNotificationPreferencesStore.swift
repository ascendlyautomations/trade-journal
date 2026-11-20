import Foundation
import Observation

@MainActor
@Observable
final class TradeRoomNotificationPreferencesStore {
    static let shared = TradeRoomNotificationPreferencesStore()

    struct Snapshot: Equatable, Sendable {
        var roomNotificationsEnabled: Bool
        var channelPrefs: [RoomChannelID: Bool]
    }

    private var snapshots: [RoomID: Snapshot] = [:]

    private init() {}

    func snapshot(for roomID: RoomID) -> Snapshot? {
        snapshots[roomID]
    }

    func replace(
        roomID: RoomID,
        roomNotificationsEnabled: Bool,
        channelPrefs: [RoomChannelID: Bool]
    ) {
        snapshots[roomID] = Snapshot(
            roomNotificationsEnabled: roomNotificationsEnabled,
            channelPrefs: channelPrefs
        )
    }

    func setRoomNotificationsEnabled(roomID: RoomID, enabled: Bool) {
        var snap = snapshots[roomID] ?? Snapshot(roomNotificationsEnabled: true, channelPrefs: [:])
        snap.roomNotificationsEnabled = enabled
        snapshots[roomID] = snap
    }

    func setChannelPreference(roomID: RoomID, channelID: RoomChannelID, enabled: Bool) {
        var snap = snapshots[roomID] ?? Snapshot(roomNotificationsEnabled: true, channelPrefs: [:])
        snap.channelPrefs[channelID] = enabled
        snapshots[roomID] = snap
    }

    func resetForTesting() {
        snapshots = [:]
    }
}