import SwiftUI

/// Plain-list spacing for Messages home (continuous inbox, not inset-grouped cards).
enum MessagesInboxLayout {
    static let sectionSpacing = ExperienceSpacing.xxs
    static let listTopContentMargin = ExperienceSpacing.xxs
    static let headerToFirstRowCompression = ExperienceSpacing.xxs

    static let avatarSide: CGFloat = 48
    static let rowHorizontalSpacing = ExperienceSpacing.xs
    static let rowVerticalPadding = ExperienceSpacing.xxs

    static let rowInsets = EdgeInsets(
        top: rowVerticalPadding,
        leading: ExperienceSpacing.md,
        bottom: rowVerticalPadding,
        trailing: ExperienceSpacing.md
    )

    static let sectionToggleVerticalPadding = ExperienceSpacing.xxs
}