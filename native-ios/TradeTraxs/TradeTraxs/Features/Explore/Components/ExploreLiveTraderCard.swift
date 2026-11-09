import SwiftUI

struct ExploreLiveTraderCard: View {
    static let railHeight: CGFloat = 188
    private static let cardWidth: CGFloat = 168

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
                        if let count = item.viewerCount, count > 0 {
                            Text("\(count) watching")
                                .font(ExperienceTypography.caption2)
                                .foregroundStyle(colors.tertiaryText)
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

            Button(action: onWatch) {
                Text("Watch")
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                            .fill(colors.accent.opacity(0.35))
                    )
            }
            .buttonStyle(.experiencePlain)
        }
        .padding(ExperienceSpacing.sm)
        .frame(width: Self.cardWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(colors.surfacePrimary)
        )
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
