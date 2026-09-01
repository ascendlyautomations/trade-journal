import SwiftUI

struct RoomActivePresenceMember: Identifiable, Equatable {
    var id: ProfileID { profileID }
    var profileID: ProfileID
    var profile: Profile
}

/// Web Community header — stacked avatars + active trader count.
struct RoomActivePresenceBar: View {
    let members: [RoomActivePresenceMember]
    let imagePipeline: any ImagePipeline
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ExperienceSpacing.sm) {
                HStack(spacing: -8) {
                    ForEach(members.prefix(3)) { member in
                        FollowListAvatarView(
                            profile: member.profile,
                            imagePipeline: imagePipeline,
                            size: 28
                        )
                        .overlay {
                            Circle()
                                .strokeBorder(colors.primaryBackground, lineWidth: 2)
                        }
                    }
                    if members.count > 3 {
                        Text("+\(members.count - 3)")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .padding(.leading, 4)
                    }
                }
                Text("\(members.count) active traders")
                    .experienceStyle(.caption, color: colors.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tradeRooms.conversation.activePresence")
        .accessibilityLabel("\(members.count) active traders")
    }
}

struct RoomActivePresenceSheet: View {
    let members: [RoomActivePresenceMember]
    let imagePipeline: any ImagePipeline
    let onSelectProfile: (ProfileID) -> Void
    let onClose: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if members.isEmpty {
                    ExperienceEmptyState(
                        icon: .rooms,
                        title: "No active traders",
                        message: "Traders appear here while viewing this room."
                    )
                } else {
                    List(members) { member in
                        Button {
                            onSelectProfile(member.profileID)
                        } label: {
                            HStack(spacing: ExperienceSpacing.sm) {
                                FollowListAvatarView(
                                    profile: member.profile,
                                    imagePipeline: imagePipeline,
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(member.profile.username)")
                                        .experienceStyle(.subheadline, color: colors.primaryText)
                                        .lineLimit(1)
                                    if !member.profile.displayName.isEmpty,
                                       member.profile.displayName != member.profile.username
                                    {
                                        Text(member.profile.displayName)
                                            .experienceStyle(.caption, color: colors.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .experienceScreenBackground()
            .navigationTitle("Active now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onClose()
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("tradeRooms.conversation.activePresence.sheet")
    }
}
