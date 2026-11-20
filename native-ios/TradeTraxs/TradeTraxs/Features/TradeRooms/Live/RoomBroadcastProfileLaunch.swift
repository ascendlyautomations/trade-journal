import SwiftUI

/// Avatar + display name — opens TradeTraxs profile after collapsing livestream chrome (viewer sheet / OBS manage).
struct RoomBroadcastProfileIdentityControl: View {
    let userId: String
    let displayName: String
    let username: String
    let avatarDiameter: CGFloat
  @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let profile: Profile?
    @Environment(\.themeColors) private var colors

    private var canOpenProfile: Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return ProfileIDQueryPolicy.isQueryable(ProfileID(trimmed))
    }

    var body: some View {
        Button {
            _ = coordinator.openParticipantProfile(userId: userId)
        } label: {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                avatar
                Text(displayLabel)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .disabled(!canOpenProfile)
        .accessibilityHint(canOpenProfile ? "Opens profile" : "")
    }

    private var displayLabel: String {
        if !username.isEmpty { return username }
        return displayName
    }

    @ViewBuilder
    private var avatar: some View {
        if let profile {
            ExploreProfileAvatarView(
                profile: profile,
                imagePipeline: imagePipeline,
                diameter: avatarDiameter
            )
        } else {
            ExperienceAvatar(
                initials: ProfileDisplay.initials(displayName: displayName, username: username),
                size: avatarDiameter
            )
        }
    }
}

private func roomBroadcastProfileOpenEnabled(userId: String) -> Bool {
    let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return ProfileIDQueryPolicy.isQueryable(ProfileID(trimmed))
}

struct RoomBroadcastChatProfileAvatarButton: View {
    let userId: String
    let displayName: String
    let username: String
    @Bindable var coordinator: RoomBroadcastCoordinator
    let imagePipeline: any ImagePipeline
    let profile: Profile?

    var body: some View {
        Button {
            _ = coordinator.openParticipantProfile(userId: userId)
        } label: {
            Group {
                if let profile {
                    ExploreProfileAvatarView(
                        profile: profile,
                        imagePipeline: imagePipeline,
                        diameter: 32
                    )
                } else {
                    ExperienceAvatar(
                        initials: ProfileDisplay.initials(displayName: displayName, username: username),
                        size: 32
                    )
                }
            }
        }
        .buttonStyle(.experiencePlain)
        .disabled(!roomBroadcastProfileOpenEnabled(userId: userId))
        .accessibilityLabel(displayName)
        .accessibilityHint(roomBroadcastProfileOpenEnabled(userId: userId) ? "Opens profile" : "")
    }
}

struct RoomBroadcastChatProfileNameButton: View {
    let userId: String
    let displayName: String
    let username: String
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            _ = coordinator.openParticipantProfile(userId: userId)
        } label: {
            Text(chatDisplayLabel)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
        }
        .buttonStyle(.experiencePlain)
        .disabled(!roomBroadcastProfileOpenEnabled(userId: userId))
        .accessibilityHint(roomBroadcastProfileOpenEnabled(userId: userId) ? "Opens profile" : "")
    }

    private var chatDisplayLabel: String {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUsername.isEmpty { return trimmedUsername }
        return displayName
    }
}