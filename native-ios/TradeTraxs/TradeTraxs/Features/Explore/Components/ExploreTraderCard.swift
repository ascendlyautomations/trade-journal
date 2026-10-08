import SwiftUI
import UIKit

/// Compact suggested-trader card for the horizontal discovery rail — fixed geometry for every slot.
struct ExploreTraderCard: View {
    /// Height reserved for the horizontal Explore rail (must match ``cardHeight``).
    static let railHeight: CGFloat = 176

    let trader: ExploreTraderSuggestion
    let profile: Profile
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var usesCompactLayout: Bool {
        dynamicTypeSize < .accessibility1
    }

    private let cardWidth: CGFloat = 148
    private let cardHeight: CGFloat = Self.railHeight
    private let avatarDiameter: CGFloat = 52
    private let nameRowHeight: CGFloat = 18
    private let usernameRowHeight: CGFloat = 15
    private let detailRowHeight: CGFloat = 14
    private let followButtonHeight: CGFloat = 30
    private let textRowSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ExploreProfileAvatarView(
                        profile: profile,
                        imagePipeline: imagePipeline,
                        diameter: avatarDiameter
                    )

                    VStack(alignment: .leading, spacing: textRowSpacing) {
                        HStack(spacing: 4) {
                            Text(profile.displayName)
                                .font(ExperienceTypography.subheadline.weight(.semibold))
                                .foregroundStyle(colors.primaryText)
                                .lineLimit(1)
                            ProfileTradeTraxsIdentityBadge(profile: profile, size: .inline)
                        }
                        .frame(height: usesCompactLayout ? nameRowHeight : nil, alignment: .center)

                        fixedTextRow(
                            text: "@\(profile.username)",
                            role: .caption,
                            color: colors.secondaryText,
                            height: usesCompactLayout ? usernameRowHeight : nil
                        )

                        fixedOptionalRow(
                            text: ProfileDisplay.suggestedTraderExperienceLine(for: profile),
                            role: .caption2,
                            color: colors.tertiaryText,
                            height: usesCompactLayout ? detailRowHeight : nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            followButton
        }
        .padding(ExperienceSpacing.sm)
        .frame(width: cardWidth, height: usesCompactLayout ? cardHeight : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.surfacePrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .contextMenu {
            Button(action: onOpen) {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            Button {
                UIPasteboard.general.string = "@\(trader.profile.username)"
                ExperienceHaptics.play(.success)
            } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
            Button(action: onToggleFollow) {
                Label(
                    isFollowing ? "Unfollow" : "Follow",
                    systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus"
                )
            }
        } preview: {
            ExploreTraderCard(
                trader: trader,
                profile: profile,
                imagePipeline: imagePipeline,
                isFollowing: isFollowing,
                onOpen: {},
                onToggleFollow: {}
            )
        }
        .accessibilityIdentifier("explore.trader.\(trader.id.rawValue)")
    }

    private var followButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: followButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                        .fill(isFollowing ? colors.fillSecondary : colors.accent)
                )
                .overlay {
                    if isFollowing {
                        RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                            .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                    }
                }
                .contentShape(Rectangle())
                .frame(minHeight: ExperienceAccessibility.minTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            isFollowing
                ? "explore.trader.following.\(trader.id.rawValue)"
                : "explore.trader.follow.\(trader.id.rawValue)"
        )
    }

    private func fixedTextRow(
        text: String,
        font: Font? = nil,
        role: TypographyRole? = nil,
        color: Color,
        height: CGFloat?
    ) -> some View {
        Group {
            if let font {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
            } else if let role {
                Text(text)
                    .experienceStyle(role, color: color)
            }
        }
        .lineLimit(usesCompactLayout ? 1 : 2)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: !usesCompactLayout)
        .frame(height: height, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fixedOptionalRow(
        text: String?,
        role: TypographyRole,
        color: Color,
        height: CGFloat?
    ) -> some View {
        Text(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text! : " ")
            .experienceStyle(role, color: color)
            .lineLimit(usesCompactLayout ? 1 : 2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: !usesCompactLayout)
            .opacity(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 1 : 0)
            .frame(height: height, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
