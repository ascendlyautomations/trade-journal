import SwiftUI

enum FeedContentFilterSwipeSupport {
    static let minimumDistance: CGFloat = 28
    static let directionThreshold: CGFloat = 56
    static let horizontalDominanceRatio: CGFloat = 1.35

    /// Swipe left advances the strip (All → Trades → …); swipe right goes back.
    static func dragGesture(
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .local)
            .onEnded { value in
                let x = value.translation.width
                let y = value.translation.height
                let absX = abs(x)
                let absY = abs(y)

                guard max(absX, absY) >= directionThreshold else { return }
                guard absX > absY * horizontalDominanceRatio else { return }

                if x < 0 {
                    onSwipeLeft()
                } else {
                    onSwipeRight()
                }
            }
    }
}

struct FeedContentFilterSwipeModifier: ViewModifier {
    let filter: FeedContentFilter
    var isEnabled: Bool = true
    let onSelect: (FeedContentFilter) -> Void

    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                content.simultaneousGesture(
                    FeedContentFilterSwipeSupport.dragGesture(
                        onSwipeLeft: {
                            guard let next = filter.adjacentFilter(offset: 1) else { return }
                            ExperienceHaptics.play(.selection)
                            onSelect(next)
                        },
                        onSwipeRight: {
                            guard let previous = filter.adjacentFilter(offset: -1) else { return }
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
    func feedContentFilterSwipe(
        filter: FeedContentFilter,
        isEnabled: Bool = true,
        onSelect: @escaping (FeedContentFilter) -> Void
    ) -> some View {
        modifier(
            FeedContentFilterSwipeModifier(
                filter: filter,
                isEnabled: isEnabled,
                onSelect: onSelect
            )
        )
    }
}
