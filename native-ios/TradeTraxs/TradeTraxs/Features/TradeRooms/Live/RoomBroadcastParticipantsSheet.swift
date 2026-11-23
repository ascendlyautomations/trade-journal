import SwiftUI

struct RoomBroadcastParticipantsSheet: View {
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Watching") {
                        Text("\(coordinator.localViewerCount)")
                    }
                }
                Section("In stream") {
                    if coordinator.rosterParticipants.isEmpty {
                        Text("No participants yet")
                            .foregroundStyle(colors.secondaryText)
                    } else {
                        ForEach(coordinator.rosterParticipants) { participant in
                            participantRow(participant)
                        }
                    }
                }
                if coordinator.isOpenVoiceStream, !coordinator.isInConversation {
                    Section {
                        ExperienceButton(title: "Join conversation", kind: .primary) {
                            Task { await coordinator.joinConversation() }
                        }
                    } footer: {
                        Text("Microphone access requires explicit join and server authorization.")
                    }
                }
                if coordinator.isInConversation {
                    Section {
                        ExperienceButton(title: "Leave conversation", kind: .secondary) {
                            Task { await coordinator.leaveConversation() }
                        }
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .experienceScreenBackground()
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func participantRow(_ participant: BroadcastRosterParticipant) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            RoomBroadcastProfileIdentityControl(
                userId: participant.identity,
                displayName: participant.displayName,
                username: coordinator.chatProfileCache.profile(forUserId: participant.identity)?.username
                    ?? participant.identity,
                avatarDiameter: 36,
                coordinator: coordinator,
                imagePipeline: imagePipeline,
                profile: coordinator.chatProfileCache.profile(forUserId: participant.identity)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if participant.isHandRaised {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(colors.accent)
            }

            if let role = participant.rosterRoleDisplay {
                Text(role)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
        }
        .experienceDashboardListRow()
    }
}
