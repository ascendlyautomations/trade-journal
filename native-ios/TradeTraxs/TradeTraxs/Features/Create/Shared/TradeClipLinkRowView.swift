import SwiftUI

/// Shared clip row for Link Clip picker and Add/Edit Trade linked-clip summary.
struct TradeClipLinkRowView: View {
    enum Presentation {
        case picker
        case linkedSelection
    }

    let reel: Reel
    let imagePipeline: (any ImagePipeline)?
    let objectStorage: any ObjectStorageProviding
    var presentation: Presentation = .picker

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            TradeClipLinkThumbnail(
                reel: reel,
                imagePipeline: imagePipeline,
                objectStorage: objectStorage
            )

            VStack(alignment: .leading, spacing: presentation == .picker ? 4 : 2) {
                Text(displayTitle)
                    .experienceStyle(presentation == .picker ? .headline : .body, color: colors.primaryText)
                    .lineLimit(2)

                HStack(spacing: ExperienceSpacing.sm) {
                    if let seconds = reel.durationSeconds {
                        Text(Self.formatDuration(seconds))
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                    if presentation == .picker {
                        Text(reel.createdAt, style: .date)
                            .experienceStyle(.caption, color: colors.tertiaryText)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, presentation == .picker ? 2 : 0)
    }

    private var displayTitle: String {
        reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? (presentation == .linkedSelection ? "Existing clip" : "Untitled clip")
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Portrait clip poster — matches other TradeTraxs media picker rows (~56×72).
struct TradeClipLinkThumbnail: View {
    static let width: CGFloat = 56
    static let height: CGFloat = 72

    let reel: Reel
    let imagePipeline: (any ImagePipeline)?
    let objectStorage: any ObjectStorageProviding

    @Environment(\.themeColors) private var colors

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .fill(colors.fillPrimary)

            if let imagePipeline {
                FeedClipPosterImage(
                    thumbnail: reel.thumbnail,
                    video: reel.video,
                    imagePipeline: imagePipeline,
                    objectStorage: objectStorage,
                    contentMode: .fill,
                    allowsVideoFrameExtraction: false
                )
            } else {
                ExperienceIcon(icon: .playRectangle, size: .lg, color: colors.accent)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
