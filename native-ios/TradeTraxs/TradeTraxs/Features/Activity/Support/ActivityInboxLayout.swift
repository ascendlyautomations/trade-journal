import SwiftUI

/// Plain `List` spacing for Activity, date section headers and filter chrome.
enum ActivityInboxLayout {
    /// Default plain-list inter-section gap (~`ExperienceSpacing.md`) tightened by half.
    static let sectionSpacing = ExperienceSpacing.xs

    /// Scroll content inset above the first section (halves default top breathing room).
    static let listTopContentMargin = ExperienceSpacing.xxs

    /// Filter bar inset below controls before the list (halves prior `ExperienceSpacing.xs` bottom).
    static let filterBarBottomPadding = ExperienceSpacing.xxs
}