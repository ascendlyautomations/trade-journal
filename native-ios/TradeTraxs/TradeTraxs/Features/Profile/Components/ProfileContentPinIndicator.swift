import SwiftUI

/// Subtle inline marker for content pinned to the owner Profile showcase.
struct ProfileContentPinIndicator: View {
    var body: some View {
        Text("📌")
            .font(.system(size: 13))
            .baselineOffset(1)
            .accessibilityLabel("Pinned to profile")
    }
}
