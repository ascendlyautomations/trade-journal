import SwiftUI

struct FollowListRowView: View {
    let profile: Profile
    let viewerProfileID: ProfileID?
    let imagePipeline: any ImagePipeline
    var followButtonRevision: Int = 0
    let isFollowing: Bool
    var showsFollowControl: Bool = true
    let showsRemove: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void
    let onRemove: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        let _ = followButtonRevision
        HStack(spacing: ExperienceSpacing.md) {
            Button(action: onOpen) {
                HStack(spacing: ExperienceSpacing.md) {
                    FollowListAvatarView(profile: profile, imagePipeline: imagePipeline)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: ExperienceSpacing.xxs) {
                            Text(profile.displayName)
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundStyle(colors.primaryText)
                                .lineLimit(1)
                        }
                        Text("@\(profile.username)")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.experiencePlain)
            .accessibilityIdentifier("followList.row.\(profile.id.rawValue)")

            ExperienceProfileListFollowTrailing(
                profileID: profile.id,
                viewerProfileID: viewerProfileID,
                isFollowing: isFollowing,
                showsFollowControl: showsFollowControl,
                style: .followList,
                accessibilityPrefix: "followList",
                onToggleFollow: onToggleFollow
            )

            if showsRemove {
                Menu {
                    Button("Remove", role: .destructive, action: onRemove)
                } label: {
                    ExperienceIcon(icon: .more, size: .sm, color: colors.secondaryText)
                        .frame(
                            width: ExperienceAccessibility.minTouchTarget,
                            height: ExperienceAccessibility.minTouchTarget
                        )
                        .contentShape(Rectangle())
                    .experienceControlHitTarget()
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("followList.removeMenu.\(profile.id.rawValue)")
            }
        }
        .padding(.horizontal, ExperienceSpacing.lg)
        .padding(.vertical, ExperienceSpacing.sm)
        .contentShape(Rectangle())
    }

}
