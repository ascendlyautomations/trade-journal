import SwiftUI

/// Theme transition motion — always gated by Reduce Motion via ExperienceMotion.
enum ThemeAnimation {
    static var standard: Animation { MotionSpring.gentle.animation }

    static func preferred(reduceMotion: Bool) -> Animation? {
        ExperienceMotion.preferred(standard, reduceMotion: reduceMotion)
    }
}
