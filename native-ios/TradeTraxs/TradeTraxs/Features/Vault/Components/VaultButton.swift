import SwiftUI

/// Vault affordance — outlined/filled hexagon aligned with Like/Comment/Share.
struct VaultButton: View {
    let ref: VaultContentRef
    @Bindable var store: VaultStore
    var onTap: () -> Void

    @Environment(\.themeColors) private var colors

    private var isVaulted: Bool { store.state(for: ref).isVaulted }

    var body: some View {
        Button(action: onTap) {
            EngagementActionRowLabel(
                kind: .vault(vaulted: isVaulted),
                showsCount: false,
                iconColor: isVaulted ? colors.accent : colors.secondaryText
            )
        }
        .buttonStyle(.plain)
        .engagementActionRowContainer()
        .accessibilityLabel(isVaulted ? "Manage in Vault" : "Add to Vault")
        .accessibilityIdentifier("interaction.vault.\(ref.contentType.rawValue).\(ref.contentID)")
    }
}
