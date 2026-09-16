import SwiftUI

/// Shared three-dot overflow for content detail headers.
///
/// Share / Copy Link / Report are real actions (never stub-disabled).
/// Owner Edit / Delete appear only when callbacks are provided.
struct DetailOverflowMenu: View {
    let isOwner: Bool
    var shareTitle: String = "Share"
    var onShare: (() -> Void)? = nil
    var onCopyLink: (() -> Void)? = nil
    var onAddToVault: (() -> Void)? = nil
    var onManageInVault: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var editTitle: String = "Edit"
    var deleteTitle: String = "Delete"
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var accessibilityIdentifier: String = "detail.overflow"

    private var showsMenu: Bool {
        if onShare != nil || onCopyLink != nil { return true }
        if onAddToVault != nil || onManageInVault != nil { return true }
        if !isOwner, onReport != nil { return true }
        if isOwner, onEdit != nil || onDelete != nil { return true }
        return false
    }

    var body: some View {
        if showsMenu {
            Menu {
                if isOwner, let onEdit {
                    Button(editTitle, systemImage: "pencil", action: onEdit)
                }

                if let onManageInVault {
                    Button("Manage in Vault", systemImage: "hexagon.fill") {
                        ExperienceHaptics.play(.selection)
                        onManageInVault()
                    }
                } else if let onAddToVault {
                    Button("Add to Vault", systemImage: "hexagon") {
                        ExperienceHaptics.play(.selection)
                        onAddToVault()
                    }
                }

                if onShare != nil || onCopyLink != nil {
                    Button(shareTitle, systemImage: "square.and.arrow.up") {
                        ExperienceHaptics.play(.selection)
                        onShare?()
                    }
                    .disabled(onShare == nil)

                    Button("Copy Link", systemImage: "link") {
                        onCopyLink?()
                    }
                    .disabled(onCopyLink == nil)
                }

                if !isOwner, onReport != nil {
                    Button("Report", systemImage: "flag") {
                        onReport?()
                    }
                }

                if isOwner, let onDelete {
                    Button(deleteTitle, systemImage: "trash", role: .destructive, action: onDelete)
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
}
