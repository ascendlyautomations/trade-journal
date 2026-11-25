import SwiftUI

/// In-room voice controls, same session as ``RoomLiveVoiceBar`` (no second LiveKit connection).
struct RoomLiveVoiceControlsSheet: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    header
                    membersEntry
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
        .experienceSheetChrome()
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

    private var membersEntry: some View {
        ExperienceButton(
            title: "Members",
            kind: .secondary,
            isEnabled: !coordinator.isLeaving
        ) {
            dismiss()
            coordinator.showsMembersScreen = true
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
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

