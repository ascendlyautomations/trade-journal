import SwiftUI

struct ProfileSectionSwipeModifier: ViewModifier {
    let section: ProfileSection
    var isEnabled: Bool = true
    let onSelect: (ProfileSection) -> Void

    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                content
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                    FeedContentFilterSwipeSupport.dragGesture(
                        onSwipeLeft: {
                            guard let next = section.adjacentSection(offset: 1) else { return }
                            ExperienceHaptics.play(.selection)
                            onSelect(next)
                        },
                        onSwipeRight: {
                            guard let previous = section.adjacentSection(offset: -1) else { return }
                            ExperienceHaptics.play(.selection)
                            onSelect(previous)
                        }
                    )
                )
            } else {
                content
            }
        }
    }
}

extension View {
    /// Horizontal swipe between profile tabs — same thresholds as Feed filter swipe.
    func profileSectionSwipe(
        section: ProfileSection,
        isEnabled: Bool = true,
        onSelect: @escaping (ProfileSection) -> Void
    ) -> some View {
        modifier(
            ProfileSectionSwipeModifier(
                section: section,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
        )
    }
}
