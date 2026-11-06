import SwiftUI

/// In-room voice controls — same session as ``RoomLiveVoiceBar`` (no second LiveKit connection).
struct RoomLiveVoiceControlsSheet: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    header
                    RoomLiveVoiceParticipantList(coordinator: coordinator)
                    controlButtons
                    if let lastError = coordinator.lastError, !lastError.isEmpty {
                        errorBanner(lastError)
                    }
                }
                .padding(ExperienceSpacing.md)
            }
            .experienceScreenBackground()
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(coordinator.session?.roomTitle ?? "Trade Room")
                .experienceStyle(.title3, color: colors.primaryText)
                .lineLimit(2)
            HStack(spacing: ExperienceSpacing.sm) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(coordinator.voiceConnectionStatusLabel)
                    .experienceStyle(.subheadline, color: colors.secondaryText)
                Spacer(minLength: 0)
                Text("\(coordinator.participantCount) in voice")
                    .experienceStyle(.subheadline, color: colors.secondaryText)
            }
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

    private var controlButtons: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            if coordinator.session?.canPublish == true {
                ExperienceButton(
                    title: coordinator.isMicrophoneEnabled ? "Mute microphone" : "Unmute microphone",
                    kind: .secondary,
                    isEnabled: !coordinator.isLeaving
                ) {
                    Task { await coordinator.toggleMute() }
                }

                ExperienceButton(
                    title: coordinator.isHandRaised ? "Lower hand" : "Raise hand",
                    kind: .secondary,
                    isEnabled: !coordinator.isLeaving
                ) {
                    Task { await coordinator.toggleHandRaised() }
                }
            }

            ExperienceButton(
                title: "Leave Voice",
                kind: .destructive,
                isEnabled: true
            ) {
                Task {
                    await coordinator.leave()
                    dismiss()
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            Text(message)
                .experienceStyle(.caption, color: colors.error)
            if coordinator.session != nil {
                Button("Retry leave") {
                    Task { await coordinator.leave(clearError: false) }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }
}

struct RoomLiveVoiceParticipantList: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Participants")
                .experienceStyle(.caption, color: colors.tertiaryText)
            if coordinator.participants.isEmpty {
                Text("No participants yet")
                    .experienceStyle(.caption, color: colors.secondaryText)
            } else {
                ForEach(coordinator.participants) { participant in
                    HStack(spacing: ExperienceSpacing.sm) {
                        Circle()
                            .fill(participant.isSpeaking ? colors.accent : colors.fillSecondary)
                            .frame(width: 8, height: 8)
                        Text(participant.displayName + (participant.isLocal ? " (you)" : ""))
                            .experienceStyle(.body, color: colors.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if participant.isMuted {
                            Image(systemName: "mic.slash")
                                .foregroundStyle(colors.tertiaryText)
                        }
                        if participant.isHandRaised {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(colors.accent)
                        }
                    }
                }
            }
        }
    }
}
