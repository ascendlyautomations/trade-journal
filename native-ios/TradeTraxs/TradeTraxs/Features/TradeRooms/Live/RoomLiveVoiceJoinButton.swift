import SwiftUI

struct RoomLiveVoiceJoinButton: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var coordinator: RoomLiveVoiceCoordinator

    @Environment(\.themeColors) private var colors
    @State private var showsVoiceControls = false

    var body: some View {
        if coordinator.isEngagedInVoice(for: roomID) {
            Button {
                showsVoiceControls = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: "waveform")
                        .foregroundStyle(colors.accent)
                    Text(inRoomStatusTitle)
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
            .accessibilityIdentifier("tradeRooms.liveVoice.inVoice")
            .sheet(isPresented: $showsVoiceControls) {
                RoomLiveVoiceControlsSheet(coordinator: coordinator)
            }
        } else {
            Button {
                Task {
                    await coordinator.join(roomID: roomID, roomTitle: roomTitle)
                }
            } label: {
                Label(joinButtonTitle, systemImage: "headphones")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryBackground)
                    .padding(.horizontal, ExperienceSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(colors.accent))
            }
            .buttonStyle(.experiencePlain)
            .disabled(coordinator.isJoining)
            .accessibilityIdentifier("tradeRooms.liveVoice.join")
        }
    }

    private var joinButtonTitle: String {
        if coordinator.isJoining, coordinator.session?.roomID != roomID {
            return "Joining…"
        }
        return coordinator.isJoining ? "Joining…" : "Join Voice"
    }

    private var inRoomStatusTitle: String {
        switch coordinator.voiceConnectionStatusLabel {
        case "Reconnecting…":
            return "Reconnecting…"
        case "Connecting…":
            return "Connecting…"
        case "Leaving…":
            return "Leaving…"
        default:
            return "In Voice"
        }
    }

    private var statusIndicatorColor: Color {
        switch coordinator.voiceConnectionStatusLabel {
        case "Connected":
            return colors.accent
        case "Connecting…", "Reconnecting…":
            return .orange
        default:
            return colors.accent.opacity(0.7)
        }
    }
}
