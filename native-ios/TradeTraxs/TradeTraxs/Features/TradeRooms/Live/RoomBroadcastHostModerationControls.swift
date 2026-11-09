import SwiftUI

/// Broadcaster stream moderation actions (invite / mute / revoke / remove).
struct RoomBroadcastHostModerationControls: View {
    let roomID: RoomID
    let targetUserId: String
    let targetDisplayName: String
    let surface: Surface
    @Bindable var coordinator: RoomBroadcastCoordinator
    let hostUserId: String?
    let hostDisplayName: String
    @Environment(\.themeColors) private var colors

    enum Surface {
        case participant
        case raisedHand
    }

    private var isBusy: Bool {
        coordinator.broadcastModerationBusyUserId == targetUserId
    }

    private var isSpeaker: Bool {
        coordinator.isBroadcastSpeaker(userId: targetUserId)
    }

    private var isPendingInvite: Bool {
        coordinator.hasPendingSpeakInvitation(userId: targetUserId)
    }

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            if surface == .raisedHand {
                inviteButton(label: isBusy ? "Inviting…" : "Invite")
            } else if !isSpeaker, !isPendingInvite {
                inviteButton(label: "Invite to speak")
            }

            Menu {
                if surface == .raisedHand {
                    Button("Dismiss hand") {
                        run(.dismissHand)
                    }
                }
                if isSpeaker {
                    Button("Force mute") { run(.muteSpeaker) }
                    Button("Revoke speaker") {
                        run(.revokeSpeaker, chat: "\(targetDisplayName) is no longer a speaker.")
                    }
                }
                Button("Disconnect from stream (can rejoin)", role: .destructive) {
                    run(.removeViewer, chat: "\(targetDisplayName) was disconnected from the stream.")
                }
                Button("Remove & block rejoin (this session)", role: .destructive) {
                    run(.removeViewer, blockRejoin: true, chat: "\(targetDisplayName) was removed from the stream.")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .disabled(isBusy)
            .accessibilityLabel("Moderation actions")
        }
    }

    private func inviteButton(label: String) -> some View {
        Button(label) {
            run(
                .inviteSpeak,
                chat: "\(targetDisplayName) got permission to speak."
            )
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .buttonStyle(.borderedProminent)
        .tint(colors.accent)
        .disabled(isBusy || isSpeaker || isPendingInvite)
    }

    private func run(
        _ action: BroadcastModerationAction,
        blockRejoin: Bool = false,
        chat: String? = nil
    ) {
        Task {
            await coordinator.executeBroadcastModeration(
                roomID: roomID,
                targetUserId: targetUserId,
                action: action,
                blockRejoin: blockRejoin,
                chatAnnouncement: chat,
                hostUserId: hostUserId,
                hostDisplayName: hostDisplayName
            )
        }
    }
}

/// Status badges for speakers, pending invites, and blocks.
struct RoomBroadcastParticipantStatusBadges: View {
    let userId: String
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 4) {
            if coordinator.isBroadcastSpeaker(userId: userId) {
                badge("Speaker", color: colors.accent)
            } else if coordinator.hasPendingSpeakInvitation(userId: userId) {
                badge("Invited", color: colors.secondaryText)
            }
            if coordinator.isUserBlockedFromBroadcastSession(userId: userId) {
                badge("Blocked", color: colors.error)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
    }
}
