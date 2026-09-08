import SwiftUI

/// Press-and-hold pause on the Story media area — cancels if the finger moves enough to swipe.
struct StoryHoldToPauseGesture: ViewModifier {
    var isEnabled: Bool
    var onHoldChanged: (Bool) -> Void

    @State private var isHolding = false

    private static let cancelMovement: CGFloat = 14

    func body(content: Content) -> some View {
        content.simultaneousGesture(holdGesture)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled else {
                    endHoldIfNeeded()
                    return
                }
                let moved = hypot(value.translation.width, value.translation.height)
                if moved > Self.cancelMovement {
                    endHoldIfNeeded()
                    return
                }
                if !isHolding {
                    isHolding = true
                    onHoldChanged(true)
                }
            }
            .onEnded { _ in
                endHoldIfNeeded()
            }
    }

    private func endHoldIfNeeded() {
        guard isHolding else { return }
        isHolding = false
        onHoldChanged(false)
    }
}

extension View {
    func storyHoldToPause(isEnabled: Bool, onHoldChanged: @escaping (Bool) -> Void) -> some View {
        modifier(StoryHoldToPauseGesture(isEnabled: isEnabled, onHoldChanged: onHoldChanged))
    }
}
