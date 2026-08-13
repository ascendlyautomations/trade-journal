import SwiftUI

/// Brief heart burst for double-tap Like — SF Symbol only, non-blocking.
struct LikeFeedbackOverlay: View {
    var isVisible: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            if isVisible {
                Image(systemName: "heart.fill")
                    .font(.system(size: reduceMotion ? 56 : 72, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                    .scaleEffect(reduceMotion ? 1 : 1)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.35).combined(with: .opacity)
                    )
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }
}
