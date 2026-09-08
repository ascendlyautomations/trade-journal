import SwiftUI

struct RoomMemberRowView: View {
    let item: RoomMemberItem
    let imagePipeline: any ImagePipeline
    var onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: ExperienceSpacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    FollowListAvatarView(profile: item.profile, imagePipeline: imagePipeline)
                    if item.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(colors.backgroundPrimary, lineWidth: 1.5)
                            }
                            .offset(x: 1, y: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: ExperienceSpacing.xxs) {
                        Text(item.profile.displayName)
                            .experienceStyle(.subheadline, color: colors.primaryText)
                            .lineLimit(1)
                        if item.profile.isCreator {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(colors.accent)
                        }
                    }
                    Text("@\(item.profile.username)")
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: ExperienceSpacing.xs) {
                        RoomMemberTagChipsView(
                            tags: item.tags,
                            showsOwnerBadge: item.role == .owner,
                            limit: 3
                        )
                        if item.role == .member && item.tags.isEmpty {
                            Text("Member")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(colors.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colors.fillSecondary, in: Capsule())
                        }
                        if let joinedAt = item.joinedAt {
                            Text("Joined \(MessagesInboxSupport.relativeTimestamp(joinedAt))")
                                .experienceStyle(.caption2, color: colors.tertiaryText)
                        }
                    }
                }
                Spacer(minLength: 0)
                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
            .padding(.vertical, ExperienceSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tradeRooms.member.\(item.id.rawValue)")
    }
}
