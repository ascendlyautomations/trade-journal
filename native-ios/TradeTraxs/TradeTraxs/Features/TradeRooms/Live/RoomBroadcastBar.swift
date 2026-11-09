import SwiftUI

/// Persistent livestream chrome above the tab bar — same session as ``RoomBroadcastWatchView``.
struct RoomBroadcastBar: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if coordinator.isObsHostBroadcastBarActive {
                obsHostBarContent
            } else {
                viewerBarContent
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.navigationBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.red.opacity(0.45))
                .frame(height: 1)
        }
        .accessibilityIdentifier("tradeRooms.broadcast.bar")
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(Color.red.opacity(0.92)))
    }

    private var obsHostBarContent: some View {
        Button {
            coordinator.presentObsManageStreamFromBar()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                liveBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.obsHostBarSession?.roomTitle ?? "Live stream")
                        .experienceStyle(.caption, color: colors.primaryText)
                        .lineLimit(1)
                    Text("You're streaming")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("tradeRooms.broadcast.hostBar")
    }

    private var viewerBarContent: some View {
        Group {
            Button {
                coordinator.presentViewer()
            } label: {
                HStack(spacing: ExperienceSpacing.sm) {
                    liveBadge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.watchSession?.roomTitle ?? "Live stream")
                            .experienceStyle(.caption, color: colors.primaryText)
                            .lineLimit(1)
                        Text(coordinator.broadcastStatusLabel)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.experiencePlain)

            Button {
                Task { await coordinator.toggleBroadcastHand() }
            } label: {
                Image(systemName: coordinator.isBroadcastHandRaised ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        coordinator.isBroadcastHandRaised ? colors.accent : colors.secondaryText
                    )
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel(coordinator.isBroadcastHandRaised ? "Lower hand" : "Raise hand")

            Button {
                Task { await coordinator.toggleStreamPlaybackMute() }
            } label: {
                Image(systemName: coordinator.isStreamPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel(coordinator.isStreamPlaybackMuted ? "Unmute stream" : "Mute stream")

            Button {
                Task { await coordinator.leaveWatch() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.error)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.experiencePlain)
            .accessibilityLabel("Leave stream")
        }
    }
}
