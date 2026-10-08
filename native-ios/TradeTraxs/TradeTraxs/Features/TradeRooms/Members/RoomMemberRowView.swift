import SwiftUI

struct RoomMemberRowView: View {
    let item: RoomMemberItem
    let imagePipeline: any ImagePipeline
    var showsTrailingChevron: Bool = true
    var showsManageButton: Bool = false
    var onManage: (() -> Void)? = nil
    var onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Button(action: onOpen) {
                HStack(spacing: ExperienceSpacing.md) {
                    avatarBlock
                    memberTextBlock
                    Spacer(minLength: 0)
                    if showsTrailingChevron, !showsManageButton {
                        ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsManageButton, let onManage {
                Button("Manage") {
                    ExperienceHaptics.play(.selection)
                    onManage()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(colors.accent)
                .accessibilityIdentifier("tradeRooms.member.manage.\(item.id.rawValue)")
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityIdentifier("tradeRooms.member.\(item.id.rawValue)")
    }

    private var avatarBlock: some View {
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
    }

    private var memberTextBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: ExperienceSpacing.xxs) {
                Text(item.profile.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .lineLimit(1)
                ProfileTradeTraxsIdentityBadge(profile: item.profile, size: .inline)
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
    }
}
