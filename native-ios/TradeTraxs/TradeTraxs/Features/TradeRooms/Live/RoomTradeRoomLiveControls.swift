import SwiftUI

/// Voice + livestream entry points for Trade Room conversation chrome.
struct RoomTradeRoomLiveControls: View {
    let roomID: RoomID
    let roomTitle: String
    var isStreamLive: Bool
    var onJoinStream: () -> Void
    var onOpenStream: () -> Void
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                RoomLiveVoiceJoinButton(
                    roomID: roomID,
                    roomTitle: roomTitle,
                    coordinator: liveVoiceCoordinator
                )

                if broadcastCoordinator.isWatchingRoom(roomID) {
                    Button(action: onOpenStream) {
                        HStack(spacing: 6) {
                            Text("LIVE")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(Color.red.opacity(0.92)))
                            Text("Watching")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(colors.accent)
                        }
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(colors.accent.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityIdentifier("tradeRooms.broadcast.watching")
                }

                Spacer(minLength: 0)
            }

            #if DEBUG
            if let statusError = broadcastCoordinator.statusPollError,
               broadcastCoordinator.statusPollRoomID == roomID
            {
                Text("Stream status: \(statusError)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(colors.error)
                    .lineLimit(2)
            }
            #endif

            if isStreamLive, !broadcastCoordinator.isWatchingRoom(roomID) {
                Button(action: onJoinStream) {
                    Label("Join Stream", systemImage: "play.rectangle.fill")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryBackground)
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Capsule(style: .continuous).fill(Color.red.opacity(0.9)))
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("tradeRooms.broadcast.joinStream")
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xxs)
    }
}
