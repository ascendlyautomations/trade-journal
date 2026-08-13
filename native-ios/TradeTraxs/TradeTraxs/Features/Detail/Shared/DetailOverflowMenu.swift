import SwiftUI

/// Shared three-dot overflow — owner journal actions when callbacks are provided.
struct DetailOverflowMenu: View {
    let isOwner: Bool
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
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
                Button("Edit Trade", systemImage: "pencil") {
                    onEdit?()
                }
                .disabled(onEdit == nil)
                Button("Delete Trade", systemImage: "trash", role: .destructive) {
                    onDelete?()
                }
                .disabled(onDelete == nil)
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
