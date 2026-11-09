import SwiftUI

struct RoomBroadcastChatRow: View {
    let message: BroadcastChatMessageItem
    let imagePipeline: any ImagePipeline
    @Bindable var coordinator: RoomBroadcastCoordinator
    @Environment(\.themeColors) private var colors

    var body: some View {
        let profile = coordinator.chatProfileCache.profile(forUserId: message.userId)
        let name = profile?.displayName ?? message.displayName
        let username = profile?.username ?? message.displayName
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            if let profile {
                ExploreProfileAvatarView(
                    profile: profile,
                    imagePipeline: imagePipeline,
                    diameter: 32
                )
            } else {
                ExperienceAvatar(
                    initials: ProfileDisplay.initials(displayName: name, username: username),
                    size: 32
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(username.isEmpty ? name : username)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                    Text(BroadcastChatRelativeTime.string(for: message.sentAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(colors.tertiaryText)
                }
                Text(message.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum BroadcastChatRelativeTime {
    static func string(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
