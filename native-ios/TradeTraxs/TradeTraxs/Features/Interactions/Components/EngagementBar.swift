import SwiftUI

/// Compact like + comment + share + vault row for cards and detail headers.
struct EngagementBar: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore
    @Bindable var vaultStore: VaultStore
    var onCommentTap: () -> Void
    var onShareTap: (() -> Void)? = nil
    var vaultRef: VaultContentRef?
    var visualStyle: EngagementBarVisualStyle = .standard

    @State private var showsVaultSheet = false

    var body: some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            LikeButton(target: target, store: store)
            CommentButton(target: target, store: store, action: onCommentTap)
            if let onShareTap {
                ShareButton(action: onShareTap)
            }

            Spacer(minLength: 0)

            if let vaultRef {
                VaultButton(ref: vaultRef, store: vaultStore) {
                    vaultStore.loadFoldersIfNeeded()
                    showsVaultSheet = true
                }
            }
        }
        .frame(height: EngagementActionRowMetrics.rowHeight, alignment: .center)
        .environment(\.engagementBarVisualStyle, visualStyle)
        .sheet(isPresented: $showsVaultSheet) {
            if let vaultRef {
                VaultDestinationSheet(ref: vaultRef, store: vaultStore)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("interaction.bar.\(target.kind.rawValue).\(target.id)")
    }
}
