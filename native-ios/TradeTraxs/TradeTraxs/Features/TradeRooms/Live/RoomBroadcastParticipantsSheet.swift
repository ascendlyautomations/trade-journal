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
                            HStack(spacing: ExperienceSpacing.sm) {
                                rosterAvatar(for: participant)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(participant.displayName)
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text(participant.roleLabel + (participant.isLocal ? " · you" : ""))
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                                Spacer(minLength: 0)
                                if participant.isHandRaised {
                                    Image(systemName: "hand.raised.fill")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                            .experienceDashboardListRow()
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

    @ViewBuilder
    private func rosterAvatar(for participant: BroadcastRosterParticipant) -> some View {
        if let profile = coordinator.chatProfileCache.profile(forUserId: participant.identity) {
            ExploreProfileAvatarView(
                profile: profile,
                imagePipeline: imagePipeline,
                diameter: 36
            )
        } else {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: participant.displayName,
                    username: participant.identity
                ),
                size: 36
            )
        }
    }
}
