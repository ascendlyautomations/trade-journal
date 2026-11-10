import SwiftUI

struct ExploreLiveTraderCard: View {
    /// Outer card height used by the Explore horizontal rail (includes padding).
    static let railHeight: CGFloat = 212
    private static let cardWidth: CGFloat = 168
    private static let watchButtonVerticalPadding: CGFloat = 6
    private static let watchButtonBlockHeight: CGFloat = 34

    let item: ExploreLiveTraderNow
    let imagePipeline: any ImagePipeline
    let onOpenProfile: () -> Void
    let onWatch: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var profile: Profile {
        let username = item.broadcasterUsername?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "trader"
        let displayName = item.broadcasterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? username
        let avatar = item.broadcasterAvatarURL.flatMap { raw -> MediaReference? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return MediaReference(id: trimmed, kind: .image, altText: nil)
        }
        return Profile(
            id: item.broadcasterProfileID,
            userID: UserID(item.broadcasterProfileID.rawValue),
            username: username,
            displayName: displayName,
            bio: nil,
            avatar: avatar,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: .now
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            profileHeaderBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(0)

            watchButton
                .layoutPriority(2)
        }
        .padding(ExperienceSpacing.sm)
        .frame(width: Self.cardWidth, height: Self.railHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.surfacePrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }

    private var profileHeaderBlock: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpenProfile) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    ExploreProfileAvatarView(
                        profile: profile,
                        imagePipeline: imagePipeline,
                        diameter: 52
                    )
                    Text(profile.displayName)
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    if let username = item.broadcasterUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !username.isEmpty
                    {
                        Text("@\(username)")
                            .font(ExperienceTypography.caption)
                            .foregroundStyle(colors.secondaryText)
                            .lineLimit(1)
                    }
                    Text(item.roomName)
                        .font(ExperienceTypography.caption2)
                        .foregroundStyle(colors.tertiaryText)
                        .lineLimit(2)
                        .layoutPriority(0)
                    if let count = item.viewerCount, count > 0 {
                        Text("\(count) watching")
                            .font(ExperienceTypography.caption2)
                            .foregroundStyle(colors.tertiaryText)
                            .lineLimit(1)
                            .layoutPriority(0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.experiencePlain)
            .padding(.trailing, 28)

            Text("LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.9)))
        }
    }

    private var watchButton: some View {
        Button(action: onWatch) {
            Text("Watch")
                .font(ExperienceTypography.subheadline.weight(.semibold))
                .foregroundStyle(colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.watchButtonVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        .fill(colors.accent.opacity(0.35))
                )
        }
        .buttonStyle(.experiencePlain)
        .frame(height: Self.watchButtonBlockHeight)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
