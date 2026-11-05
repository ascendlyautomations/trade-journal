import SwiftUI

/// Persistent compact voice chrome — room label, mute, leave.
struct RoomLiveVoiceBar: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    @State private var showsParticipants = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live voice")
                        .experienceStyle(.caption2, color: colors.accent)
                    Text(coordinator.session?.roomTitle ?? "")
                        .experienceStyle(.caption, color: colors.primaryText)
                        .lineLimit(1)
                    Text(coordinator.session?.channelTitle ?? "")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if coordinator.session?.canPublish == true {
                    Button {
                        Task { await coordinator.toggleMute() }
                    } label: {
                        Image(systemName: coordinator.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(
                                coordinator.isMicrophoneEnabled ? colors.primaryText : colors.error
                            )
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.experiencePlain)
                    .accessibilityLabel(coordinator.isMicrophoneEnabled ? "Mute" : "Unmute")
                }

                Button {
                    showsParticipants.toggle()
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Participants")

                Button {
                    Task { await coordinator.leave() }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.error)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.experiencePlain)
                .accessibilityLabel("Leave live voice")
            }

            if showsParticipants {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(coordinator.participants) { participant in
                        HStack(spacing: ExperienceSpacing.xs) {
                            Circle()
                                .fill(participant.isSpeaking ? colors.accent : colors.fillSecondary)
                                .frame(width: 8, height: 8)
                            Text(participant.displayName + (participant.isLocal ? " (you)" : ""))
                                .experienceStyle(.caption2, color: colors.secondaryText)
                                .lineLimit(1)
                            if participant.isMuted {
                                Image(systemName: "mic.slash")
                                    .font(.system(size: 10))
                                    .foregroundStyle(colors.tertiaryText)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let lastError = coordinator.lastError, !lastError.isEmpty {
                Text(lastError)
                    .experienceStyle(.caption2, color: colors.error)
                    .lineLimit(2)
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
    }
}
