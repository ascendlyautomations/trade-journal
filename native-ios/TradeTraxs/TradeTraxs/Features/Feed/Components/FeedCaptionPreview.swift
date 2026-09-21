import SwiftUI

/// Standard feed caption line limits by content type.
enum FeedCaptionLineLimit {
    static let post = 4
    static let trade = 4
    static let achievement = 4
    static let clip = 2
}

extension FeedTimelineEntry {
    /// Configured caption clamp for this row, or `nil` when the entry has no caption field.
    var feedCaptionLineLimit: Int? {
        switch self {
        case .trade:
            return FeedCaptionLineLimit.trade
        case .post:
            return FeedCaptionLineLimit.post
        case .achievement:
            return FeedCaptionLineLimit.achievement
        case .clip:
            return FeedCaptionLineLimit.clip
        }
    }

    var feedCaptionText: String? {
        let raw: String?
        switch self {
        case .trade(_, let summary):
            raw = summary.publicCaption ?? summary.notePreview
        case .post(_, let post):
            raw = post.body
        case .clip(_, let reel):
            raw = reel.caption
        case .achievement(_, let achievement):
            raw = achievement.description
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Truncated feed caption with layout-accurate `See more` when text exceeds `lineLimit`.
struct FeedCaptionPreview: View {
    enum Style: Equatable {
        case feedBody
        case clipsOverlay
    }

    let text: String
    let lineLimit: Int
    var style: Style = .feedBody
    let onSeeMore: () -> Void
    var accessibilityIdentifier: String = "feed.caption"
    var seeMoreAccessibilityIdentifier: String = "feed.caption.seeMore"

    @Environment(\.themeColors) private var colors
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: seeMoreSpacing) {
            captionText
                .multilineTextAlignment(.leading)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(accessibilityIdentifier)
                .background {
                    FeedCaptionTruncationMeasurer(
                        text: text,
                        lineLimit: lineLimit,
                        style: style,
                        colors: colors
                    ) { truncated in
                        isTruncated = truncated
                    }
                }

            if isTruncated {
                Button(action: onSeeMore) {
                    seeMoreLabel
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(seeMoreAccessibilityIdentifier)
                .accessibilityLabel("See more")
                .accessibilityHint("Opens full caption")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var seeMoreSpacing: CGFloat {
        switch style {
        case .feedBody: return ExperienceSpacing.xxs
        case .clipsOverlay: return 2
        }
    }

    @ViewBuilder
    private var captionText: some View {
        switch style {
        case .feedBody:
            Text(text)
                .experienceStyle(.body, color: colors.primaryText)
        case .clipsOverlay:
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    @ViewBuilder
    private var seeMoreLabel: some View {
        switch style {
        case .feedBody:
            Text("See more")
                .font(.footnote.weight(.regular))
                .foregroundStyle(Color(uiColor: .link))
        case .clipsOverlay:
            Text("See more")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }
}

/// Compares unlimited caption height vs. line-clamped height at the same width.
private struct FeedCaptionTruncationMeasurer: View {
    let text: String
    let lineLimit: Int
    let style: FeedCaptionPreview.Style
    let colors: SemanticColorPalette
    let onTruncated: (Bool) -> Void

    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: 0)
            .background {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        measureLabel
                            .lineLimit(lineLimit)
                            .frame(width: geo.size.width, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: FeedCaptionLimitedHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            }

                        measureLabel
                            .frame(width: geo.size.width, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: FeedCaptionFullHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            }
                    }
                    .hidden()
                }
            }
            .onPreferenceChange(FeedCaptionLimitedHeightKey.self) { limitedHeight = $0 }
            .onPreferenceChange(FeedCaptionFullHeightKey.self) { fullHeight = $0 }
            .onChange(of: limitedHeight) { _, _ in reportTruncation() }
            .onChange(of: fullHeight) { _, _ in reportTruncation() }
    }

    @ViewBuilder
    private var measureLabel: some View {
        switch style {
        case .feedBody:
            Text(text)
                .experienceStyle(.body, color: .clear)
        case .clipsOverlay:
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.clear)
        }
    }

    private func reportTruncation() {
        guard limitedHeight > 0, fullHeight > 0 else { return }
        onTruncated(fullHeight > limitedHeight + 0.5)
    }
}

private struct FeedCaptionLimitedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FeedCaptionFullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
