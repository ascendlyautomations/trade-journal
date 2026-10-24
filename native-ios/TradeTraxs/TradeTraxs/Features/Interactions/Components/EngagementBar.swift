import SwiftUI

/// Compact like + comment + share + vault row for cards and detail headers.
struct EngagementBar: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore
    @Bindable var vaultStore: VaultStore
    var onCommentTap: () -> Void
    var onShareTap: (() -> Void)? = nil
    /// Tap on the row’s empty space, such as the gap beside Share. Buttons keep their own actions.
    var onEmptyAreaTap: (() -> Void)? = nil
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

            if let onEmptyAreaTap {
                Spacer(minLength: 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEmptyAreaTap)
            } else {
                Spacer(minLength: 0)
            }

            if let vaultRef {
                VaultButton(ref: vaultRef, store: vaultStore) {
                    vaultStore.loadFoldersIfNeeded()
                    showsVaultSheet = true
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: EngagementActionRowMetrics.rowHeight, alignment: .center)
        .background {
            if let onEmptyAreaTap {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onEmptyAreaTap)
            }
        }
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
