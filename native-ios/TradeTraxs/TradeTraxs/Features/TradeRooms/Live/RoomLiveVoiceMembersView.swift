import SwiftUI

/// Full-screen General Voice roster; dismiss only (does not disconnect LiveKit).
struct RoomLiveVoiceMembersView: View {
    @Bindable var coordinator: RoomLiveVoiceCoordinator
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    private var sortedParticipants: [LiveVoiceParticipantItem] {
        coordinator.participants.sorted { lhs, rhs in
            if lhs.isLocal != rhs.isLocal { return lhs.isLocal }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if coordinator.participants.isEmpty {
                    Text("No members in voice yet")
                        .experienceStyle(.body, color: colors.secondaryText)
                        .experienceDashboardListRow()
                } else {
                    Section {
                        ForEach(sortedParticipants) { participant in
                            RoomLiveVoiceMemberRow(
                                participant: participant,
                                profile: coordinator.chatProfileCache.profile(forUserId: participant.identity),
                                imagePipeline: imagePipeline
                            )
                            .experienceDashboardListRow()
                        }
                    } header: {
                        Text("\(coordinator.participantCount) in voice")
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .experienceScreenBackground()
            .experienceNavigationTitle("Members")
            .experienceArrowBackToolbarButton {
                coordinator.showsMembersScreen = false
            }
        }
        .task(id: participantIdentityKey) {
            await hydrateProfiles()
        }
    }

    private var participantIdentityKey: String {
        sortedParticipants.map(\.identity).joined(separator: "|")
    }

    private func hydrateProfiles() async {
        let ids = coordinator.participants.map(\.identity)
        await coordinator.chatProfileCache.hydrate(userIds: ids)
    }
}

struct RoomLiveVoiceMemberRow: View {
    let participant: LiveVoiceParticipantItem
    let profile: Profile?
    let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(1)
                if let secondary = secondaryLabel {
                    Text(secondary)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ExperienceSpacing.xs) {
                if participant.isSpeaking {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.accent)
                        .accessibilityLabel("Speaking")
                }
                if participant.isMuted {
                    Image(systemName: "mic.slash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                        .accessibilityLabel("Muted")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryLabel: String {
        let name = profile?.displayName ?? participant.displayName
        if participant.isLocal {
            return "\(name) (you)"
        }
        return name
    }

    private var secondaryLabel: String? {
        if let username = profile?.username, !username.isEmpty {
            return "@\(username)"
        }
        return nil
    }

    @ViewBuilder
    private var avatar: some View {
        let diameter: CGFloat = 40
        if let profile {
            FollowListAvatarView(
                profile: profile,
                imagePipeline: imagePipeline,
                size: diameter,
                debugSurface: "liveVoiceMembers"
            )
            .overlay {
                if participant.isSpeaking {
                    Circle()
                        .strokeBorder(colors.accent, lineWidth: 2)
                }
            }
        } else {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(
                    displayName: participant.displayName,
                    username: participant.identity
                ),
                size: diameter
            )
            .overlay {
                if participant.isSpeaking {
                    Circle()
                        .strokeBorder(colors.accent, lineWidth: 2)
                }
            }
        }
    }
}