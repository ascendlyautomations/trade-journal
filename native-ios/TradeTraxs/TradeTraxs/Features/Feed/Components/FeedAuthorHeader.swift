import SwiftUI

/// Compact Instagram-style author row — avatar from cache / fixtures only (no per-row fetch).
struct FeedAuthorHeader: View {
    let profile: Profile?
    let fallbackID: ProfileID
    let timestamp: Date
    let imagePipeline: any ImagePipeline
    let onOpenAuthor: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpenAuthor) {
            HStack(spacing: ExperienceSpacing.sm) {
                FollowListAvatarView(
                    profile: resolvedProfile,
                    imagePipeline: imagePipeline,
                    size: 36
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if !username.isEmpty {
                            Text("@\(username)")
                                .experienceStyle(.caption, color: colors.secondaryText)
                                .lineLimit(1)
                            Text("·")
                                .experienceStyle(.caption, color: colors.tertiaryText)
                        }
                        Text(MessagesInboxSupport.relativeTimestamp(timestamp))
                            .experienceStyle(.caption, color: colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("feed.author.\(fallbackID.rawValue)")
    }

    private var resolvedProfile: Profile {
        if let profile { return profile }
        // Web feed cards fall back to "User" — never render a raw UUID.
        return Profile(
            id: fallbackID,
            userID: UserID(fallbackID.rawValue),
            username: "",
            displayName: "User",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private var displayName: String {
        let name = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty, name != fallbackID.rawValue { return name }
        let user = username
        return user.isEmpty ? "User" : user
    }

    private var username: String {
        profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
