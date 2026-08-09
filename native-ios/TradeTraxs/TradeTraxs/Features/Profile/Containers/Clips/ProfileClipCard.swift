import SwiftUI

struct ProfileClipCard: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private var target: InteractionTarget { .reel(reel.id) }

    var body: some View {
        ExperienceCard {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                        ZStack(alignment: .bottomTrailing) {
                            TradeImageView(
                                reference: reel.thumbnail,
                                imagePipeline: imagePipeline,
                                purpose: .reelThumbnail,
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
                            Text(reel.caption?.isEmpty == false ? reel.caption! : "Clip")
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
                }
                .buttonStyle(.plain)

                EngagementBar(
                    target: target,
                    store: engagementStore,
                    onCommentTap: onOpen
                )
            }
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
