import SwiftUI

enum RoomLiveVoiceJoinPresentation {
    case legacy
    case tradeRoomRowLight
    case tradeRoomRowEngaged
}

struct RoomLiveVoiceJoinButton: View {
    let roomID: RoomID
    let roomTitle: String
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    var presentation: RoomLiveVoiceJoinPresentation = .legacy

    @Environment(\.themeColors) private var colors
    @State private var showsVoiceControls = false

    var body: some View {
        if coordinator.isEngagedInVoice(for: roomID) {
            engagedButton
        } else {
            joinButton
        }
    }

    @ViewBuilder
    private var joinButton: some View {
        Button {
            Task {
                await coordinator.join(roomID: roomID, roomTitle: roomTitle)
            }
        } label: {
            joinLabel
        }
        .buttonStyle(.experiencePlain)
        .disabled(coordinator.isJoining)
        .accessibilityIdentifier("tradeRooms.liveVoice.join")
    }

    @ViewBuilder
    private var engagedButton: some View {
        Button {
            showsVoiceControls = true
        } label: {
            engagedLabel
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier("tradeRooms.liveVoice.inVoice")
        .sheet(isPresented: $showsVoiceControls) {
            RoomLiveVoiceControlsSheet(coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var joinLabel: some View {
        switch presentation {
        case .legacy:
            Label(joinButtonTitle, systemImage: "headphones")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.primaryBackground)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(colors.accent))
        case .tradeRoomRowLight, .tradeRoomRowEngaged:
            Label(tradeRoomJoinVoiceTitle, systemImage: "headphones")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .fill(colors.accent.opacity(0.95))
                )
        }
    }

    @ViewBuilder
    private var engagedLabel: some View {
        let content = HStack(spacing: 6) {
            Circle()
                .fill(statusIndicatorColor)
                .frame(width: 8, height: 8)
            Image(systemName: "headphones")
            Text(inRoomStatusTitle)
                .fontWeight(.semibold)
        }
        .font(.system(.caption, design: .rounded))

        switch presentation {
        case .legacy:
            content
                .foregroundStyle(colors.accent)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(colors.accent.opacity(0.45), lineWidth: 1)
                )
        case .tradeRoomRowLight, .tradeRoomRowEngaged:
            content
                .foregroundStyle(colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .strokeBorder(colors.accent.opacity(0.55), lineWidth: 1.5)
                )
        }
    }

    private var joinButtonTitle: String {
        if coordinator.isJoining, coordinator.session?.roomID != roomID {
            return "Joining…"
        }
        return coordinator.isJoining ? "Joining…" : tradeRoomJoinVoiceTitle
    }

    private var tradeRoomJoinVoiceTitle: String {
        if coordinator.isJoining { return "Joining…" }
        if let count = coordinator.generalVoiceConnectedCount(for: roomID) {
            return "Join Voice (\(count))"
        }
        return "Join Voice"
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
