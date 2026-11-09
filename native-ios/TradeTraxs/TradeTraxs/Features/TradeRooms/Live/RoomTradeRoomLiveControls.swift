import SwiftUI

/// Voice + livestream entry points for Trade Room conversation chrome.
struct RoomTradeRoomLiveControls: View {
    let roomID: RoomID
    let roomTitle: String
    var isStreamLive: Bool
    var isRoomOwner: Bool
    var currentUserId: String?
    var onJoinStream: () -> Void
    var onManageStream: () -> Void
    var onOpenStream: () -> Void
    var onStartStream: () -> Void
    @Bindable var liveVoiceCoordinator: RoomLiveVoiceCoordinator
    @Bindable var broadcastCoordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    private var liveDarkGreen: Color {
        colors.accent.opacity(0.95)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
                voiceSlot
                    .frame(maxWidth: .infinity)

                if showLiveSlot {
                    liveSlot
                        .frame(maxWidth: .infinity)
                } else if isRoomOwner {
                    startStreamSlot
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
    private var startStreamSlot: some View {
        Button(action: onStartStream) {
                Label("Start Stream", systemImage: "video.badge.waveform")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                            .fill(colors.accent.opacity(0.85))
                    )
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("tradeRooms.broadcast.startStream")
        .opacity(voiceRowDisabled ? 0.45 : 1)
        .allowsHitTesting(!voiceRowDisabled)
        .accessibilityHidden(voiceRowDisabled)
    }

    private var isOwnObsLiveStream: Bool {
        broadcastCoordinator.isCurrentUserObsBroadcaster(for: roomID, userId: currentUserId)
    }

    private var voiceRowDisabled: Bool {
        broadcastCoordinator.isWatchingRoom(roomID) && !isOwnObsLiveStream
    }

    private var liveRowDisabled: Bool {
        liveVoiceCoordinator.isEngagedInVoice(for: roomID)
    }

    @ViewBuilder
    private var voiceSlot: some View {
        Group {
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
        .opacity(voiceRowDisabled ? 0.45 : 1)
        .allowsHitTesting(!voiceRowDisabled)
        .accessibilityHidden(voiceRowDisabled)
    }

    @ViewBuilder
    private var liveSlot: some View {
        Group {
            if isOwnObsLiveStream {
                Button(action: onManageStream) {
                    Label(manageStreamButtonTitle, systemImage: "slider.horizontal.3")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                                .fill(liveDarkGreen)
                        )
                }
                .buttonStyle(.experiencePlain)
                .accessibilityIdentifier("tradeRooms.broadcast.manageStream")
            } else if broadcastCoordinator.isWatchingRoom(roomID) {
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
                    .foregroundStyle(colors.textPrimary)
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
                    Label(joinLiveButtonTitle, systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.onAccent)
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
        .opacity(liveRowDisabled ? 0.45 : 1)
        .allowsHitTesting(!liveRowDisabled)
        .accessibilityHidden(liveRowDisabled)
    }

    private var joinLiveButtonTitle: String {
        if let count = broadcastCoordinator.liveViewerCount(for: roomID) {
            return "Join Live (\(count))"
        }
        return "Join Live"
    }

    private var manageStreamButtonTitle: String {
        if let count = broadcastCoordinator.liveViewerCount(for: roomID) {
            return "Manage Stream (\(count))"
        }
        return "Manage Stream"
    }
}
