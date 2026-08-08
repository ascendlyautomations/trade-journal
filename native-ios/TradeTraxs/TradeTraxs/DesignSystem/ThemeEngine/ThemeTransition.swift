import SwiftUI

/// Applies a smooth theme change without rebuilding navigation stacks.
enum ThemeTransition {
    static func perform(
        reduceMotion: Bool,
        animates: Bool,
        _ updates: () -> Void
    ) {
        guard animates else {
            updates()
            return
        }
        ExperienceMotion.withAnimation(
            ThemeAnimation.standard,
            reduceMotion: reduceMotion,
            updates
        )
    }
}
