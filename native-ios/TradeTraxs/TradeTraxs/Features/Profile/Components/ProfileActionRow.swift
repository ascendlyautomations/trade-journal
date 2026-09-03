import SwiftUI

/// Shared Profile action chrome for owner + visitor — only the available actions change.
struct ProfileActionRow: View {
    enum Mode: Equatable {
        case owner(hasTradeRoom: Bool)
        /// `showsTradeRoom` mirrors web `canShowVisitorRoomCta` (View Trade Room only).
        case visitor(isFollowing: Bool, isRequested: Bool, showsTradeRoom: Bool)
    }

    let mode: Mode
    var onEdit: () -> Void = {}
    var onShare: () -> Void = {}
    var onCreateTradeRoom: () -> Void = {}
    var onViewTradeRoom: () -> Void = {}
    var onFollow: () -> Void = {}
    var onMessage: () -> Void = {}
    var onTradeRoom: () -> Void = {}
    var isMessaging: Bool = false
    var canMessage: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            switch mode {
            case .owner(let hasTradeRoom):
                ownerPrimaryRow
                tradeRoomEmphasisButton(
                    title: hasTradeRoom ? "View Trade Room" : "Create Trade Room",
                    accessibilityIdentifier: hasTradeRoom
                        ? "profile.viewTradeRoom"
                        : "profile.createTradeRoom",
                    action: hasTradeRoom ? onViewTradeRoom : onCreateTradeRoom
                )
            case .visitor(let isFollowing, let isRequested, let showsTradeRoom):
                visitorRow(
                    isFollowing: isFollowing,
                    isRequested: isRequested,
                    showsTradeRoom: showsTradeRoom
                )
            }
        }
        .padding(.top, ExperienceSpacing.xxs)
        .accessibilityIdentifier("profile.actionRow")
    }

    private var ownerPrimaryRow: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            actionChip(
                title: "Edit Profile",
                style: .outline,
                accessibilityIdentifier: "profile.edit",
                action: onEdit
            )
            actionChip(
                title: "Share",
                icon: .share,
                style: .outline,
                accessibilityIdentifier: "profile.share",
                action: onShare
            )
            Spacer(minLength: 0)
        }
    }

    private func visitorRow(isFollowing: Bool, isRequested: Bool, showsTradeRoom: Bool) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            actionChip(
                title: isFollowing ? "Following" : (isRequested ? "Requested" : "Follow"),
                style: (isFollowing || isRequested) ? .outline : .filled,
                accessibilityIdentifier: isFollowing
                    ? "profile.followingButton"
                    : (isRequested ? "profile.requestedButton" : "profile.follow"),
                action: onFollow
            )
            actionChip(
                title: isMessaging ? "Opening…" : "Message",
                style: .outline,
                accessibilityIdentifier: "profile.message",
                isEnabled: canMessage && !isMessaging,
                action: onMessage
            )
            if showsTradeRoom {
                actionChip(
                    title: "View Trade Room",
                    style: .emphasis,
                    accessibilityIdentifier: "profile.viewTradeRoom",
                    action: onTradeRoom
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func tradeRoomEmphasisButton(
        title: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        actionChip(
            title: title,
            style: .emphasis,
            accessibilityIdentifier: accessibilityIdentifier,
            expands: true,
            action: action
        )
    }

    private enum ChipStyle {
        case outline
        case filled
        case emphasis
    }

    private func actionChip(
        title: String,
        icon: AppIcon? = nil,
        style: ChipStyle,
        accessibilityIdentifier: String,
        isEnabled: Bool = true,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            ExperienceHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    ExperienceIcon(icon: icon, size: .sm, color: foreground(for: style))
                }
                Text(title)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .foregroundStyle(foreground(for: style))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: 32)
            .background { background(for: style) }
            .overlay { overlay(for: style) }
            .frame(
                minWidth: ExperienceAccessibility.minTouchTarget,
                minHeight: ExperienceAccessibility.minTouchTarget
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? ExperienceOpacity.opaque : ExperienceOpacity.disabled)
        .fixedSize(horizontal: !expands, vertical: false)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func foreground(for style: ChipStyle) -> Color {
        switch style {
        case .outline, .emphasis: return colors.primaryText
        case .filled: return colors.onAccent
        }
    }

    @ViewBuilder
    private func background(for style: ChipStyle) -> some View {
        switch style {
        case .outline:
            Color.clear
        case .filled:
            RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                .fill(colors.accent)
        case .emphasis:
            RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                .fill(colors.fillSecondary)
        }
    }

    @ViewBuilder
    private func overlay(for style: ChipStyle) -> some View {
        switch style {
        case .outline:
            RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                .stroke(colors.border, lineWidth: ExperienceBorder.thin)
        case .filled:
            EmptyView()
        case .emphasis:
            RoundedRectangle(cornerRadius: ExperienceRadius.button, style: .continuous)
                .stroke(colors.primaryText.opacity(0.22), lineWidth: ExperienceBorder.thin)
        }
    }
}
