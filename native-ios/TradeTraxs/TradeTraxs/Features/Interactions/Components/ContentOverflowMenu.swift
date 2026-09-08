import SwiftUI

/// Compact three-dot overflow for feed cards, profile grids, and clip overlays.
struct ContentOverflowMenu: View {
    let isOwner: Bool
    var onReport: (() -> Void)? = nil
    var onAddToVault: (() -> Void)? = nil
    var onManageInVault: (() -> Void)? = nil
    var editTitle: String = "Edit"
    var deleteTitle: String = "Delete"
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var foregroundColor: Color? = nil
    var accessibilityIdentifier: String = "content.overflow"

    @Environment(\.themeColors) private var colors

    private var showsMenu: Bool {
        if onAddToVault != nil || onManageInVault != nil { return true }
        if !isOwner, onReport != nil { return true }
        if isOwner, onEdit != nil || onDelete != nil { return true }
        return false
    }

    var body: some View {
        if showsMenu {
            Menu {
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

                if !isOwner, let onReport {
                    Button("Report", systemImage: "flag") {
                        ExperienceHaptics.play(.selection)
                        onReport()
                    }
                }

                if isOwner {
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
                    .foregroundStyle(foregroundColor ?? colors.secondaryText)
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
