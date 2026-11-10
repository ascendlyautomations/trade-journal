import SwiftUI

/// Compact like + comment + share + vault row for cards and detail headers.
struct EngagementBar<Trailing: View>: View {
    let target: InteractionTarget
    @Bindable var store: EngagementStore
    @Bindable var vaultStore: VaultStore
    var onCommentTap: () -> Void
    var onShareTap: (() -> Void)? = nil
    /// Tap on the row’s empty space, such as the gap beside Share. Buttons keep their own actions.
    var onEmptyAreaTap: (() -> Void)? = nil
    var vaultRef: VaultContentRef?
    var visualStyle: EngagementBarVisualStyle = .standard
    @ViewBuilder var trailing: () -> Trailing

    @State private var showsVaultSheet = false

    init(
        target: InteractionTarget,
        store: EngagementStore,
        vaultStore: VaultStore,
        onCommentTap: @escaping () -> Void,
        onShareTap: (() -> Void)? = nil,
        onEmptyAreaTap: (() -> Void)? = nil,
        vaultRef: VaultContentRef? = nil,
        visualStyle: EngagementBarVisualStyle = .standard,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.target = target
        self.store = store
        self.vaultStore = vaultStore
        self.onCommentTap = onCommentTap
        self.onShareTap = onShareTap
        self.onEmptyAreaTap = onEmptyAreaTap
        self.vaultRef = vaultRef
        self.visualStyle = visualStyle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                LikeButton(target: target, store: store)
                CommentButton(target: target, store: store, action: onCommentTap)
                if let onShareTap {
                    ShareButton(action: onShareTap)
                }
            }

            flexibleGap

            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                trailing()
                if let vaultRef {
                    VaultButton(ref: vaultRef, store: vaultStore) {
                        vaultStore.loadFoldersIfNeeded()
                        showsVaultSheet = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: EngagementActionRowMetrics.rowHeight, alignment: .leading)
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

    @ViewBuilder
    private var flexibleGap: some View {
        if let onEmptyAreaTap {
            Spacer(minLength: 0)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: onEmptyAreaTap)
        } else {
            Spacer(minLength: 0)
                .layoutPriority(1)
        }
    }
}
