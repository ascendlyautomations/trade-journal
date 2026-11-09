import SwiftUI

/// Persistent compact voice chrome — room label, mute, leave.
struct RoomLiveVoiceBar: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    @State private var showsParticipants = false
    @State private var showsVoiceControls = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.sm) {
                Button {
                    showsVoiceControls = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.session?.roomTitle ?? "Trade Room")
                            .experienceStyle(.caption, color: colors.primaryText)
                            .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(coordinator.voiceConnectionStatusLabel)
                            .experienceStyle(.caption2, color: colors.secondaryText)
                    }
                    }
                }
                .buttonStyle(.experiencePlain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if coordinator.session?.canPublish == true {
                    voiceIconButton(
                        systemName: coordinator.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                        foreground: coordinator.isMicrophoneEnabled ? colors.primaryText : colors.error,
                        label: coordinator.isMicrophoneEnabled ? "Mute" : "Unmute"
                    ) {
                        Task { await coordinator.toggleMute() }
                    }

                    voiceIconButton(
                        systemName: coordinator.isHandRaised ? "hand.raised.fill" : "hand.raised",
                        foreground: coordinator.isHandRaised ? colors.accent : colors.secondaryText,
                        label: coordinator.isHandRaised ? "Lower hand" : "Raise hand"
                    ) {
                        Task { await coordinator.toggleHandRaised() }
                    }
                }

                voiceIconButton(
                    systemName: "person.2.fill",
                    foreground: colors.secondaryText,
                    label: "Participants"
                ) {
                    showsParticipants.toggle()
                }

                voiceIconButton(
                    systemName: "phone.down.fill",
                    foreground: colors.error,
                    label: "Leave Voice"
                ) {
                    Task { await coordinator.leave() }
                }
            }

            if showsParticipants {
                RoomLiveVoiceParticipantList(coordinator: coordinator)
            }

            if let lastError = coordinator.lastError, !lastError.isEmpty {
                HStack(spacing: ExperienceSpacing.sm) {
                    Text(lastError)
                        .experienceStyle(.caption2, color: colors.error)
                        .lineLimit(2)
                    if coordinator.session != nil {
                        Button("Retry leave") {
                            Task { await coordinator.leave(clearError: false) }
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(colors.error)
                    }
                }
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.vertical, ExperienceSpacing.sm)
        .background(colors.navigationBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.accent.opacity(0.35))
                .frame(height: 1)
        }
        .accessibilityIdentifier("tradeRooms.liveVoice.bar")
        .sheet(isPresented: $showsVoiceControls) {
            RoomLiveVoiceControlsSheet(coordinator: coordinator)
        }
    }

    private var statusColor: Color {
        switch coordinator.voiceConnectionStatusLabel {
        case "Connected":
            return colors.accent
        case "Connecting…", "Reconnecting…":
            return .orange
        default:
            return colors.tertiaryText
        }
    }

    private func voiceIconButton(
        systemName: String,
        foreground: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.experiencePlain)
        .disabled(coordinator.isLeaving)
        .accessibilityLabel(label)
    }
}
