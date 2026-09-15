import UIKit

/// Process-wide navigation bar back control — chevron only, no previous-page title.
enum ExperienceNavigationBarAppearance {
    static func configureArrowOnlyBackButtons() {
        // Hides the previous screen title beside the system back chevron on pushed pages.
        let hiddenTitleOffset = UIOffset(horizontal: -1000, vertical: 0)
        UIBarButtonItem.appearance().setBackButtonTitlePositionAdjustment(
            hiddenTitleOffset,
            for: .default
        )
    }
}
