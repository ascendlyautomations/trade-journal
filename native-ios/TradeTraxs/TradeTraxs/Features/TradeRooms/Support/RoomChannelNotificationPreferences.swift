import Foundation

/// Web `lib/roomChannelNotificationPreferences.ts` parity.
enum RoomChannelNotificationPreferences {
    static func channelNotificationsEnabled(
        prefsBySectionID: [RoomChannelID: Bool],
        channelID: RoomChannelID
    ) -> Bool {
        prefsBySectionID[channelID] != false
    }

    static func anyRoomChannelNotificationsEnabled(
        roomLevelEnabled: Bool,
        channels: [RoomChannel],
        prefsBySectionID: [RoomChannelID: Bool]
    ) -> Bool {
        guard roomLevelEnabled else { return false }
        guard !channels.isEmpty else { return true }
        return channels.contains { channelNotificationsEnabled(prefsBySectionID: prefsBySectionID, channelID: $0.id) }
    }

    static func defaultedChannelPrefs(
        channels: [RoomChannel],
        serverPrefs: [RoomChannelID: Bool]
    ) -> [RoomChannelID: Bool] {
        var result: [RoomChannelID: Bool] = [:]
        for channel in channels {
            result[channel.id] = serverPrefs[channel.id] != false
        }
        return result
    }
}