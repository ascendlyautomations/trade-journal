import SwiftUI

/// Inset-grouped list metrics for Messages home.
enum MessagesInboxLayout {
    /// Tighter gaps between inset sections (Direct Messages ↔ Trade Rooms, etc.).
    static let sectionSpacing = ExperienceSpacing.xxs

    static let headerToFirstRowCompression = ExperienceSpacing.xxs
    /// Extra pull when Direct Messages follows the personal trade room (no header).
    static let directMessagesHeaderTopCompression = ExperienceSpacing.xxs

    /// ~75% less space above the first list content (personal trade room).
    static let listTopContentMargin = ExperienceSpacing.xxs

    static let avatarSide: CGFloat = 52
    static let rowHorizontalSpacing = ExperienceSpacing.sm
    /// ~37.5% less vertical padding per row than the prior `ExperienceSpacing.xs`.
    static let rowVerticalPadding: CGFloat = 5

    static let sectionToggleVerticalPadding: CGFloat = 2

    /// Horizontal inset for row separators (matches list content margins).
    static let rowSeparatorHorizontalInset = ExperienceSpacing.md

    /// Barely visible inbox row dividers (~0.5pt hairline at 8–12% opacity).
    static let rowSeparatorLineOpacity: CGFloat = 0.10
}