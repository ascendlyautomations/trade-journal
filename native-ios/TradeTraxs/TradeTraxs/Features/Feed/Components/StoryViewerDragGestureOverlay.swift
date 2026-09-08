import SwiftUI

enum StoryViewerDragGestureSupport {
    static let minimumDistance: CGFloat = 24
    static let directionThreshold: CGFloat = 48

    static func dragGesture(
        isReplyFocused: Bool,
        canOpenReplyComposer: Bool,
        onSwipeDown: @escaping () -> Void,
        onSwipeUp: @escaping () -> Void,
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

                if absX > absY {
                    guard !isReplyFocused else { return }
                    if x < 0 {
                        onSwipeLeft()
                    } else {
                        onSwipeRight()
                    }
                } else if y > 0 {
                    onSwipeDown()
                } else if !isReplyFocused, canOpenReplyComposer {
                    onSwipeUp()
                }
            }
    }
}

/// Transparent layer for media-area drag when not using a parent simultaneous gesture.
struct StoryViewerDragGestureOverlay: View {
    var isEnabled: Bool
    var canOpenReplyComposer: Bool
    var onSwipeDown: () -> Void
    var onSwipeUp: () -> Void
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                StoryViewerDragGestureSupport.dragGesture(
                    isReplyFocused: !isEnabled,
                    canOpenReplyComposer: canOpenReplyComposer,
                    onSwipeDown: onSwipeDown,
                    onSwipeUp: onSwipeUp,
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight
                )
            )
            .accessibilityHidden(true)
    }
}
