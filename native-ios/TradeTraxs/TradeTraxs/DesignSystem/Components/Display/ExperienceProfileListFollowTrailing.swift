import SwiftUI

/// Trailing affordance on profile list rows, ``Follow`` / ``Following`` or static ``You`` for the signed-in user.
enum ExperienceProfileListFollowStyle {
    case exploreList
    case followList
    case exploreCard
    case leaderboard
}

struct ExperienceProfileListSelfLabel: View {
    let style: ExperienceProfileListFollowStyle

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text("You")
            .font(labelFont)
            .foregroundStyle(colors.secondaryText)
            .frame(
                minWidth: minimumWidth,
                maxWidth: style == .exploreCard ? .infinity : nil,
                minHeight: minimumHeight,
                alignment: style == .exploreCard ? .center : .trailing
            )
            .frame(height: fixedHeight)
            .accessibilityLabel("You")
            .accessibilityIdentifier("profileList.selfYou")
    }

    private var labelFont: Font {
        switch style {
        case .exploreList, .leaderboard:
            return .caption.weight(.semibold)
        case .followList:
            return .system(.footnote, design: .default).weight(.semibold)
        case .exploreCard:
            return .system(.caption, design: .rounded).weight(.semibold)
        }
    }

    private var fixedHeight: CGFloat? {
        switch style {
        case .exploreList, .leaderboard: return 30
        case .followList: return 32
        case .exploreCard: return 30
        }
    }

    private var minimumHeight: CGFloat? {
        switch style {
        case .followList: return ExperienceAccessibility.minTouchTarget
        default: return nil
        }
    }

    private var minimumWidth: CGFloat? {
        switch style {
        case .followList: return ExperienceAccessibility.minTouchTarget
        case .exploreList, .leaderboard: return 72
        case .exploreCard: return nil
        }
    }
}

struct ExperienceProfileListFollowTrailing: View {
    let profileID: ProfileID
    let viewerProfileID: ProfileID?
    let isFollowing: Bool
    let showsFollowControl: Bool
    let style: ExperienceProfileListFollowStyle
    let accessibilityPrefix: String
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        if isAuthenticatedViewer {
            ExperienceProfileListSelfLabel(style: style)
        } else if showsFollowControl {
            followButton
        }
    }

    private var isAuthenticatedViewer: Bool {
        guard let viewerProfileID else { return false }
        return profileID == viewerProfileID
    }

    @ViewBuilder
    private var followButton: some View {
        switch style {
        case .exploreList:
            exploreListButton
        case .followList:
            followListButton
        case .exploreCard:
            exploreCardButton
        case .leaderboard:
            leaderboardButton
        }
    }

    private var exploreListButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isFollowing ? colors.fillSecondary : colors.accent))
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier(
            isFollowing
                ? "\(accessibilityPrefix).following.\(profileID.rawValue)"
                : "\(accessibilityPrefix).follow.\(profileID.rawValue)"
        )
    }

    private var followListButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(.footnote, design: .default).weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .padding(.horizontal, 14)
                .frame(height: 32)
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
                .frame(
                    minWidth: ExperienceAccessibility.minTouchTarget,
                    minHeight: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier(
            isFollowing
                ? "\(accessibilityPrefix).following.\(profileID.rawValue)"
                : "\(accessibilityPrefix).follow.\(profileID.rawValue)"
        )
    }

    private var exploreCardButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
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
        .buttonStyle(.experiencePlain)
        .accessibilityIdentifier(
            isFollowing
                ? "\(accessibilityPrefix).following.\(profileID.rawValue)"
                : "\(accessibilityPrefix).follow.\(profileID.rawValue)"
        )
    }

    private var leaderboardButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, isFollowing ? 8 : 10)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(isFollowing ? colors.fillSecondary : colors.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel(isFollowing ? "Following" : "Follow")
    }
}