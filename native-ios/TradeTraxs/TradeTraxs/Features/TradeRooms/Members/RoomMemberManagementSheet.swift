import SwiftUI

/// Shared owner member actions, Members list and message long-press **Manage User**.
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
    var moderatorActionTitle: String? = nil
    var onModeratorAction: (() -> Void)? = nil

    /// When set, moderator confirm/deny is presented on this sheet (above Manage Member).
    @Binding var showsModeratorConfirmation: Bool
    var moderatorDialogTitle: String = ""
    var moderatorConfirmButtonTitle: String = "Confirm"
    var onConfirmModerator: (() -> Void)? = nil
    var onCancelModerator: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors

    init(
        member: RoomMemberItem,
        imagePipeline: any ImagePipeline,
        canRemove: Bool,
        canBan: Bool,
        onViewProfile: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onBan: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onManageTags: (() -> Void)? = nil,
        moderatorActionTitle: String? = nil,
        onModeratorAction: (() -> Void)? = nil,
        showsModeratorConfirmation: Binding<Bool>? = nil,
        moderatorDialogTitle: String = "",
        moderatorConfirmButtonTitle: String = "Confirm",
        onConfirmModerator: (() -> Void)? = nil,
        onCancelModerator: (() -> Void)? = nil
    ) {
        self.member = member
        self.imagePipeline = imagePipeline
        self.canRemove = canRemove
        self.canBan = canBan
        self.onViewProfile = onViewProfile
        self.onRemove = onRemove
        self.onBan = onBan
        self.onDismiss = onDismiss
        self.onManageTags = onManageTags
        self.moderatorActionTitle = moderatorActionTitle
        self.onModeratorAction = onModeratorAction
        _showsModeratorConfirmation = showsModeratorConfirmation ?? .constant(false)
        self.moderatorDialogTitle = moderatorDialogTitle
        self.moderatorConfirmButtonTitle = moderatorConfirmButtonTitle
        self.onConfirmModerator = onConfirmModerator
        self.onCancelModerator = onCancelModerator
    }

    private var presentsModeratorConfirmation: Bool {
        onConfirmModerator != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    RoomMemberRowView(
                        item: member,
                        imagePipeline: imagePipeline,
                        showsTrailingChevron: false,
                        onOpen: {}
                    )
                    .allowsHitTesting(false)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.vertical, ExperienceSpacing.sm)

                    ExperienceDivider()
                        .padding(.leading, ExperienceSpacing.md)

                    VStack(spacing: 0) {
                        actionRow("View Profile", action: onViewProfile)
                        if let moderatorActionTitle, let onModeratorAction {
                            ExperienceDivider()
                                .padding(.leading, ExperienceSpacing.md)
                            actionRow(moderatorActionTitle, action: onModeratorAction)
                        }
                        if let onManageTags {
                            ExperienceDivider()
                                .padding(.leading, ExperienceSpacing.md)
                            actionRow("Manage Tags", action: onManageTags)
                        }
                        if canRemove {
                            ExperienceDivider()
                                .padding(.leading, ExperienceSpacing.md)
                            actionRow("Remove Member", role: .destructive, action: onRemove)
                        }
                        if canBan {
                            ExperienceDivider()
                                .padding(.leading, ExperienceSpacing.md)
                            actionRow("Ban Member", role: .destructive, action: onBan)
                        }
                    }
                }
                .manageMemberSheetGroupedCard()
                .padding(.horizontal, ExperienceSpacing.md)
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.md)
            }
            .background(colors.groupedBackground.ignoresSafeArea())
            .experienceNavigationTitle("Manage Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .experienceSheetChrome()
        .alert(moderatorDialogTitle, isPresented: moderatorConfirmationBinding) {
            Button(moderatorConfirmButtonTitle, action: { onConfirmModerator?() })
            Button("Cancel", role: .cancel, action: { onCancelModerator?() })
        }
    }

    private var moderatorConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                presentsModeratorConfirmation && showsModeratorConfirmation
            },
            set: { showsModeratorConfirmation = $0 }
        )
    }

    private func actionRow(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                    .experienceStyle(.body, color: role == .destructive ? colors.loss : colors.primaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.experiencePlain)
    }
}

// MARK: - Grouped card (profile + actions)

private struct ManageMemberSheetGroupedCardModifier: ViewModifier {
    @Environment(\.themeColors) private var colors

    func body(content: Content) -> some View {
        content
            .background(
                colors.surfacePrimary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                    .stroke(colors.border.opacity(0.35), lineWidth: ExperienceBorder.hairline)
            }
    }
}

private extension View {
    func manageMemberSheetGroupedCard() -> some View {
        modifier(ManageMemberSheetGroupedCardModifier())
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