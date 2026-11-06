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

    private var voiceLightGreen: Color {
        colors.accent.opacity(0.72)
    }

    private var liveDarkGreen: Color {
        colors.accent.opacity(0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                voiceSlot
                    .frame(maxWidth: .infinity)

                if showLiveSlot {
                    liveSlot
                        .frame(maxWidth: .infinity)
                }
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
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.xxs)
    }

    private var showLiveSlot: Bool {
        isStreamLive || broadcastCoordinator.isWatchingRoom(roomID)
    }

    @ViewBuilder
    private var voiceSlot: some View {
        if liveVoiceCoordinator.isEngagedInVoice(for: roomID) {
            RoomLiveVoiceJoinButton(
                roomID: roomID,
                roomTitle: roomTitle,
                coordinator: liveVoiceCoordinator,
                presentation: .tradeRoomRowEngaged
            )
        } else {
            RoomLiveVoiceJoinButton(
                roomID: roomID,
                roomTitle: roomTitle,
                coordinator: liveVoiceCoordinator,
                presentation: .tradeRoomRowLight
            )
        }
    }

    @ViewBuilder
    private var liveSlot: some View {
        if broadcastCoordinator.isWatchingRoom(roomID) {
            Button(action: onOpenStream) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 8, height: 8)
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Watching")
                        .fontWeight(.semibold)
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .strokeBorder(colors.accent.opacity(0.55), lineWidth: 1.5)
                )
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("tradeRooms.broadcast.watching")
        } else if isStreamLive {
            Button(action: onJoinStream) {
                Label("Join Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                            .fill(liveDarkGreen)
                    )
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("tradeRooms.broadcast.joinStream")
        }
    }
}
