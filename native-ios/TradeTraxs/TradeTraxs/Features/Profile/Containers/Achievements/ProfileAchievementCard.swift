import SwiftUI

struct ProfileAchievementCard: View {
    let achievement: Achievement
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let onOpen: () -> Void
    var isOwner: Bool = true
    var onReport: (() -> Void)? = nil
    var profilePin: ProfilePinCallbacks? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var isPinnedToProfile: Bool {
        profilePin?.isPinned(.achievement, achievement.id.rawValue) ?? false
    }

    private var target: InteractionTarget { .achievement(achievement.id) }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ProfileCompactCardMediaSection {
                    ProfileCompactMediaThumbnail(
                        reference: achievement.image,
                        purpose: .postImage,
                        imagePipeline: imagePipeline
                    )
                    .accessibilityHidden(true)
                } metadata: {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        if achievement.isFeatured {
                            ExperienceTag(title: "Featured", tone: .success)
                        }

                        Text(achievement.title)
                            .experienceStyle(.headline, color: colors.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let description = achievement.description?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !description.isEmpty {
                            Text(description)
                                .experienceStyle(.footnote, color: colors.secondaryText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }

                        HStack(spacing: ExperienceSpacing.sm) {
                            Text(kindLabel)
                                .experienceStyle(.caption, color: colors.tertiaryText)
                            if let firm = achievement.firm, !firm.isEmpty {
                                Text(firm)
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if let value = achievement.value {
                                Text(TradeDisplay.pnlText(value))
                                    .experienceStyle(
                                        .metric,
                                        color: theme.metricColor(
                                            for: NSDecimalNumber(decimal: value.amount).doubleValue
                                        )
                                    )
                            } else if let valueText = achievement.valueText, !valueText.isEmpty {
                                Text(valueText)
                                    .experienceStyle(.caption, color: colors.secondaryText)
                            }
                        }

                        Text(TradeDisplay.dateText(achievement.achievedAt))
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                .contentShape(Rectangle())
                .experienceDoubleTapLike(
                    target: target,
                    store: engagementStore,
                    onSingleTap: onOpen
                )

                EngagementBar(
                    target: target,
                    store: engagementStore,
                    vaultStore: vaultStore,
                    onCommentTap: onOpen,
                    vaultRef: ProfileCardMediaPresence.engagementVaultRef(
                        for: target,
                        profileIsOwner: isOwner
                    )
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            ContentOverflowMenu(
                isOwner: isOwner,
                onReport: onReport,
                onPin: profilePin.map { pin in
                    {
                        pin.requestPin(
                            .achievement,
                            achievement.id.rawValue,
                            ProfilePinnedPreviewBuilder.from(achievement: achievement)
                        )
                    }
                },
                onUnpin: profilePin.map { pin in
                    {
                        pin.requestPin(
                            .achievement,
                            achievement.id.rawValue,
                            ProfilePinnedPreviewBuilder.from(achievement: achievement)
                        )
                    }
                },
                isPinnedToProfile: isPinnedToProfile,
                accessibilityIdentifier: "profile.achievement.overflow.\(achievement.id.rawValue)"
            )
            .padding(ExperienceSpacing.xxs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.achievements.card.\(achievement.id.rawValue)")
    }

    private var kindLabel: String {
        switch achievement.kind {
        case .propFirmPayout: return "Prop Firm Payout"
        case .liveTradingPayout: return "Live Trading Payout"
        case .passedEvaluation: return "Passed Eval"
        case .milestone: return "Milestone"
        }
    }
}
