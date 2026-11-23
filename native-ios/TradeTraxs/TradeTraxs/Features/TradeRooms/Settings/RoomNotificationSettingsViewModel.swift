import Foundation
import Observation

@MainActor
@Observable
final class RoomNotificationSettingsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    let roomID: RoomID
    let roomName: String
    private(set) var channels: [RoomChannel]
    private let viewerID: ProfileID
    private let rooms: any RoomRepository
    private let inboxStore: MessagesInboxStore
    private let skipServerWrites: Bool

    private(set) var phase: Phase = .idle
    private(set) var roomNotificationsEnabled = true
    private(set) var channelPrefs: [RoomChannelID: Bool] = [:]
    private(set) var saveError: String?

    private var savingRoomLevel = false
    private var savingChannelIDs: Set<RoomChannelID> = []

    init(
        roomID: RoomID,
        roomName: String,
        channels: [RoomChannel],
        viewerID: ProfileID,
        rooms: any RoomRepository,
        inboxStore: MessagesInboxStore,
        membership: RoomMembership?
    ) {
        self.roomID = roomID
        self.roomName = roomName
        self.channels = channels.sorted { $0.position < $1.position }
        self.viewerID = viewerID
        self.rooms = rooms
        self.inboxStore = inboxStore
        self.skipServerWrites = MessagesInboxSupport.isLocalDevelopmentProfile(viewerID)
            || roomID.rawValue.hasPrefix("dev-")

        if let cached = TradeRoomNotificationPreferencesStore.shared.snapshot(for: roomID) {
            roomNotificationsEnabled = cached.roomNotificationsEnabled
            channelPrefs = RoomChannelNotificationPreferences.defaultedChannelPrefs(
                channels: self.channels,
                serverPrefs: cached.channelPrefs
            )
        } else if let membership {
            roomNotificationsEnabled = membership.notificationsEnabled
            channelPrefs = RoomChannelNotificationPreferences.defaultedChannelPrefs(
                channels: self.channels,
                serverPrefs: [:]
            )
        }
    }

    func loadIfNeeded() {
        guard phase == .idle else { return }
        Task { await refresh() }
    }

    func refresh() async {
        phase = .loading
        saveError = nil
        if skipServerWrites {
            channelPrefs = RoomChannelNotificationPreferences.defaultedChannelPrefs(
                channels: channels,
                serverPrefs: channelPrefs
            )
            commitSnapshot()
            phase = .ready
            return
        }

        do {
            if let membership = try await rooms.membership(roomID: roomID, profileID: viewerID) {
                roomNotificationsEnabled = membership.notificationsEnabled
            }
            let serverPrefs = try await rooms.channelNotificationPreferences(
                roomID: roomID,
                profileID: viewerID,
                channelIDs: channels.map(\.id)
            )
            channelPrefs = RoomChannelNotificationPreferences.defaultedChannelPrefs(
                channels: channels,
                serverPrefs: serverPrefs
            )
            commitSnapshot()
            phase = .ready
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }

    func setRoomNotificationsEnabled(_ enabled: Bool) {
        guard !savingRoomLevel, roomNotificationsEnabled != enabled else { return }
        let previous = roomNotificationsEnabled
        roomNotificationsEnabled = enabled
        saveError = nil
        commitSnapshot()
        guard !skipServerWrites else { return }
        savingRoomLevel = true
        Task {
            defer { savingRoomLevel = false }
            do {
                try await rooms.updateMembershipNotificationEnabled(
                    roomID: roomID,
                    profileID: viewerID,
                    enabled: enabled
                )
                ExperienceHaptics.play(.success)
            } catch {
                roomNotificationsEnabled = previous
                saveError = ProfileSectionSupport.message(for: error)
                commitSnapshot()
                ExperienceHaptics.play(.error)
            }
        }
    }

    func setChannelNotificationsEnabled(_ channelID: RoomChannelID, enabled: Bool) {
        guard roomNotificationsEnabled, !savingChannelIDs.contains(channelID) else { return }
        let previous = channelPrefs[channelID] ?? true
        guard previous != enabled else { return }
        channelPrefs[channelID] = enabled
        saveError = nil
        commitSnapshot()
        guard !skipServerWrites else { return }
        savingChannelIDs.insert(channelID)
        Task {
            defer { savingChannelIDs.remove(channelID) }
            do {
                try await rooms.setChannelNotificationEnabled(
                    roomID: roomID,
                    profileID: viewerID,
                    channelID: channelID,
                    enabled: enabled
                )
                ExperienceHaptics.play(.success)
            } catch {
                channelPrefs[channelID] = previous
                saveError = ProfileSectionSupport.message(for: error)
                commitSnapshot()
                ExperienceHaptics.play(.error)
            }
        }
    }

    func effectiveChannelNotificationsEnabled(_ channelID: RoomChannelID) -> Bool {
        roomNotificationsEnabled && (channelPrefs[channelID] ?? true)
    }

    func isSavingChannel(_ channelID: RoomChannelID) -> Bool {
        savingChannelIDs.contains(channelID)
    }

    private func commitSnapshot() {
        TradeRoomNotificationPreferencesStore.shared.replace(
            roomID: roomID,
            roomNotificationsEnabled: roomNotificationsEnabled,
            channelPrefs: channelPrefs
        )
        let delivers = RoomChannelNotificationPreferences.anyRoomChannelNotificationsEnabled(
            roomLevelEnabled: roomNotificationsEnabled,
            channels: channels,
            prefsBySectionID: channelPrefs
        )
        inboxStore.setRoomMuted(roomID: roomID, muted: !delivers)
    }
}