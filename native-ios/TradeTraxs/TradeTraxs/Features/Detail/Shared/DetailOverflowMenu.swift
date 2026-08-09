import SwiftUI

/// Shared three-dot overflow — actions are placeholders until later phases.
struct DetailOverflowMenu: View {
    let isOwner: Bool
    var accessibilityIdentifier: String = "detail.overflow"

    var body: some View {
        Menu {
            Button("Share", systemImage: "square.and.arrow.up") {}
                .disabled(true)
            Button("Copy Link", systemImage: "link") {}
                .disabled(true)
            Button("Report", systemImage: "flag") {}
                .disabled(true)
            if isOwner {
                Divider()
                Button("Edit", systemImage: "pencil") {}
                    .disabled(true)
                Button("Delete", systemImage: "trash", role: .destructive) {}
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: ExperienceAccessibility.minTouchTarget,
                    height: ExperienceAccessibility.minTouchTarget
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
