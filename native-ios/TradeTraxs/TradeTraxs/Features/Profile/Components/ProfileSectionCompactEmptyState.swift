import SwiftUI

typealias ProfileSectionEmptyState = ExperienceCompactEmptyState

extension ExperienceCompactEmptyState {
    /// Profile section tabs (Posts, Clips, Trades, Stats, Achievements).
    static func profileSection(
        icon: AppIcon,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> ExperienceCompactEmptyState {
        ExperienceCompactEmptyState(
            icon: icon,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action,
            accessibilityIdentifier: "profile.section.emptyState"
        )
    }
}

typealias ProfileSectionCompactEmptyState = ExperienceCompactEmptyState
