import SwiftUI

/// Standard feed caption line limits by content type.
enum FeedCaptionLineLimit {
    static let post = 2
    static let trade = 2
    static let achievement = 2
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
            raw = ReelCaptionDisplay.bodyText(for: reel)
        case .achievement(_, let achievement):
            raw = achievement.description
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Feed caption with inline `...more` / ` less` when text exceeds `lineLimit`.
struct FeedCaptionPreview: View {
    enum Style: Equatable {
        case feedBody
        case clipsOverlay
    }

    let text: String
    let lineLimit: Int
    var style: Style = .feedBody
    var accessibilityIdentifier: String = "feed.caption"
    var seeMoreAccessibilityIdentifier: String = "feed.caption.seeMore"

    @Environment(\.themeColors) private var colors

    var body: some View {
        ExperienceExpandableText(
            text: text,
            typography: resolvedTypography,
            textColor: resolvedTextColor,
            moreColor: resolvedMoreColor,
            collapsedLineLimit: lineLimit,
            visualStyle: resolvedVisualStyle,
            accessibilityIdentifier: seeMoreAccessibilityIdentifier
        )
    }

    private var resolvedTypography: TypographyRole {
        switch style {
        case .feedBody: return .body
        case .clipsOverlay: return .subheadline
        }
    }

    private var resolvedTextColor: Color? {
        switch style {
        case .feedBody: return colors.primaryText
        case .clipsOverlay: return nil
        }
    }

    private var resolvedMoreColor: Color? {
        switch style {
        case .feedBody: return Color(uiColor: .link)
        case .clipsOverlay: return nil
        }
    }

    private var resolvedVisualStyle: ExperienceExpandableText.VisualStyle {
        switch style {
        case .feedBody: return .standard
        case .clipsOverlay: return .clipsOverlay
        }
    }
}