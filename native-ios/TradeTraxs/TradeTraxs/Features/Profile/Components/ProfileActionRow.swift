import SwiftUI

/// Shared Profile action chrome for owner + visitor — only the available actions change.
struct ProfileActionRow: View {
    enum Mode: Equatable {
        case owner(hasTradeRoom: Bool)
        /// `showsTradeRoom` mirrors web `canShowVisitorRoomCta` (View Trade Room only).
        case visitor(isFollowing: Bool, isRequested: Bool, showsTradeRoom: Bool)

        var showsContent: Bool {
            switch self {
            case .owner:
                return true
            case .visitor:
                return true
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            switch mode {
            case .owner:
                ownerPrimaryRow
            case .visitor(let isFollowing, let isRequested, _):
                visitorPrimaryRow(isFollowing: isFollowing, isRequested: isRequested)
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
                expands: true,
                action: onEdit
            )
            actionChip(
                title: "Share",
                icon: .share,
                style: .outline,
                accessibilityIdentifier: "profile.share",
                expands: true,
                action: onShare
            )
        }
    }

    private func visitorPrimaryRow(isFollowing: Bool, isRequested: Bool) -> some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ProfileActionChip(
                title: isFollowing ? "Following" : (isRequested ? "Requested" : "Follow"),
                style: (isFollowing || isRequested) ? .outline : .filled,
                size: .regular,
                accessibilityIdentifier: isFollowing
                    ? "profile.followingButton"
                    : (isRequested ? "profile.requestedButton" : "profile.follow"),
                expands: true,
                action: onFollow
            )
            ProfileActionChip(
                title: isMessaging ? "Opening…" : "Message",
                style: .outline,
                size: .regular,
                accessibilityIdentifier: "profile.message",
                isEnabled: canMessage && !isMessaging,
                expands: true,
                action: onMessage
            )
        }
    }

    private func actionChip(
        title: String,
        icon: AppIcon? = nil,
        style: ProfileActionChipStyle,
        accessibilityIdentifier: String,
        isEnabled: Bool = true,
        expands: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        ProfileActionChip(
            title: title,
            icon: icon,
            style: style,
            size: .regular,
            accessibilityIdentifier: accessibilityIdentifier,
            isEnabled: isEnabled,
            expands: expands,
            action: action
        )
    }
}

// MARK: - Shared action chips

enum ProfileActionChipSize {
    case regular
    case compact
}

struct ProfileActionChip: View {
    let title: String
    var icon: AppIcon? = nil
    let style: ProfileActionChipStyle
    var size: ProfileActionChipSize = .regular
    let accessibilityIdentifier: String
    var isEnabled: Bool = true
    var expands: Bool = false
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    ExperienceIcon(icon: icon, size: .sm, color: foreground)
                }
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: chipHeight)
            .background { background }
            .overlay { overlay }
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

    private var titleFont: Font {
        switch size {
        case .regular:
            return .system(.footnote, design: .default).weight(.semibold)
        case .compact:
            return .system(.caption, design: .default).weight(.semibold)
        }
    }

    private var chipHeight: CGFloat {
        switch size {
        case .regular: return 32
        case .compact: return 28
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular: return 10
        case .compact: return 8
        }
    }

    private var foreground: Color {
        switch style {
        case .outline, .emphasis: return colors.primaryText
        case .filled: return colors.onAccent
        }
    }

    @ViewBuilder
    private var background: some View {
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
    private var overlay: some View {
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

enum ProfileActionChipStyle {
    case outline
    case filled
    case emphasis
}

/// Full-width destination row for profile trade room — below action chips, not in the chip row.
struct ProfileTradeRoomDestinationRow: View {
    var title: String = "View Trade Room"
    var accessibilityIdentifier: String = "profile.viewTradeRoom"
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button {
            ExperienceHaptics.play(.selection)
            action()
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                ExperienceIcon(icon: .chart, size: .sm, color: colors.accent)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                    .experienceStyle(.body, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.xs)
                Image(systemName: AppIcon.forward.systemName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: ExperienceAccessibility.minTouchTarget)
            .background(
                colors.fillSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                    .stroke(colors.border.opacity(ExperienceOpacity.subtle), lineWidth: ExperienceBorder.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
