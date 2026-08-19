import SwiftUI

/// Shared three-dot overflow for content detail headers.
///
/// Share / Copy Link / Report are real actions (never stub-disabled).
/// Owner Edit / Delete appear only when callbacks are provided.
struct DetailOverflowMenu: View {
    let isOwner: Bool
    var onShare: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var editTitle: String = "Edit"
    var deleteTitle: String = "Delete"
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var accessibilityIdentifier: String = "detail.overflow"

    var body: some View {
        Menu {
            Button("Share", systemImage: "square.and.arrow.up") {
                ExperienceHaptics.play(.selection)
                onShare?()
            }
            .disabled(onShare == nil)

            Button("Copy Link", systemImage: "link") {
                onCopyLink?()
            }
            .disabled(onCopyLink == nil)

            if !isOwner {
                Button("Report", systemImage: "flag") {
                    onReport?()
                }
                .disabled(onReport == nil)
            }

            if isOwner, onEdit != nil || onDelete != nil {
                Divider()
                if let onEdit {
                    Button(editTitle, systemImage: "pencil", action: onEdit)
                }
                if let onDelete {
                    Button(deleteTitle, systemImage: "trash", role: .destructive, action: onDelete)
                }
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
