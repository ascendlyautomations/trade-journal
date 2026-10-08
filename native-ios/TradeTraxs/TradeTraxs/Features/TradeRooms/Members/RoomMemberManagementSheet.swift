import SwiftUI

/// Shared owner member actions — Members list and message long-press **Manage User**.
struct RoomMemberManagementSheet: View {
    let member: RoomMemberItem
    let imagePipeline: any ImagePipeline
    let canRemove: Bool
    let canBan: Bool
    let onViewProfile: () -> Void
    let onRemove: () -> Void
    let onBan: () -> Void
    let onDismiss: () -> Void
    var onManageTags: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RoomMemberRowView(
                        item: member,
                        imagePipeline: imagePipeline,
                        showsTrailingChevron: false,
                        onOpen: {}
                    )
                    .allowsHitTesting(false)
                    .listRowBackground(colors.surfaceSecondary)
                }

                Section {
                    Button("View Profile") {
                        onViewProfile()
                    }
                    .foregroundStyle(colors.primaryText)
                    if let onManageTags {
                        Button("Manage Tags") {
                            onManageTags()
                        }
                        .foregroundStyle(colors.primaryText)
                    }
                    if canRemove {
                        Button("Remove Member", role: .destructive) {
                            onRemove()
                        }
                    }
                    if canBan {
                        Button("Ban Member", role: .destructive) {
                            onBan()
                        }
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .scrollContentBackground(.hidden)
            .experienceNavigationTitle("Manage Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .experienceScreenBackground()
        .presentationDetents([.medium, .large])
        .presentationBackground(colors.sheetBackground)
    }
}

extension View {
    func roomMemberModerationConfirmations(
        showsRemoveConfirmation: Binding<Bool>,
        showsBanConfirmation: Binding<Bool>,
        removeDialogTitle: String,
        onConfirmRemove: @escaping () -> Void,
        onConfirmBan: @escaping () -> Void,
        onCancelRemove: @escaping () -> Void,
        onCancelBan: @escaping () -> Void
    ) -> some View {
        modifier(
            RoomMemberModerationConfirmationModifier(
                showsRemoveConfirmation: showsRemoveConfirmation,
                showsBanConfirmation: showsBanConfirmation,
                removeDialogTitle: removeDialogTitle,
                onConfirmRemove: onConfirmRemove,
                onConfirmBan: onConfirmBan,
                onCancelRemove: onCancelRemove,
                onCancelBan: onCancelBan
            )
        )
    }
}

private struct RoomMemberModerationConfirmationModifier: ViewModifier {
    @Binding var showsRemoveConfirmation: Bool
    @Binding var showsBanConfirmation: Bool
    var removeDialogTitle: String
    let onConfirmRemove: () -> Void
    let onConfirmBan: () -> Void
    let onCancelRemove: () -> Void
    let onCancelBan: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                removeDialogTitle,
                isPresented: $showsRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Member", role: .destructive, action: onConfirmRemove)
                Button("Cancel", role: .cancel, action: onCancelRemove)
            }
            .alert("Ban this user?", isPresented: $showsBanConfirmation) {
                Button("Ban User", role: .destructive, action: onConfirmBan)
                Button("Cancel", role: .cancel, action: onCancelBan)
            } message: {
                Text("Are you sure you want to ban this user from this Trade Room?")
            }
    }
}
