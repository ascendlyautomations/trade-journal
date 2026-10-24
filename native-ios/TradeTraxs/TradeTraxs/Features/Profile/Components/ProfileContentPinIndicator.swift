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

/// Pin badge for picture-grid tiles. Sits in the top-right corner over the photo.
struct ProfileGridPinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.black.opacity(0.62), in: Circle())
            .accessibilityLabel("Pinned to profile")
    }
}
