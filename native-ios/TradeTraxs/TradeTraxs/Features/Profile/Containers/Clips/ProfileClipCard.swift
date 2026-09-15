import SwiftUI

struct ProfileClipCard: View {
    let reel: Reel
    let detailCache: DetailPresentationCache
    let imagePipeline: any ImagePipeline
    let objectStorage: any ObjectStorageProviding
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let onOpen: () -> Void
    var isOwner: Bool = true
    var onReport: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    private var target: InteractionTarget { .reel(reel.id) }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                    ZStack(alignment: .bottomTrailing) {
                        FeedClipPosterImage(
                            thumbnail: reel.thumbnail,
                            video: reel.video,
                            imagePipeline: imagePipeline,
                            objectStorage: objectStorage,
                            contentMode: .fill
                        )
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(colors.primaryText)
                            .padding(6)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text(ClipDisplayTitle.text(for: reel, cache: detailCache))
                            .experienceStyle(.headline, color: colors.primaryText)
                            .lineLimit(3)

                        HStack(spacing: ExperienceSpacing.xs) {
                            Text(TradeDisplay.dateText(reel.createdAt))
                                .experienceStyle(.caption, color: colors.secondaryText)
                            if let seconds = reel.durationSeconds, seconds > 0 {
                                Text(Self.formatDuration(seconds))
                                    .experienceStyle(.caption, color: colors.tertiaryText)
                            }
                            if reel.linkedTradeID != nil {
                                ExperienceTag(title: "Trade", tone: .info)
                            }
                            Spacer(minLength: 0)
                        }
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
                accessibilityIdentifier: "profile.clip.overflow.\(reel.id.rawValue)"
            )
            .padding(ExperienceSpacing.xxs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.clips.card.\(reel.id.rawValue)")
    }

    private static func formatDuration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let mins = seconds / 60
        let secs = seconds % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
