import SwiftUI

/// Shared compact row chrome for Dashboard quick actions (~56–64pt).
enum DashboardQuickActionStyle {
    static let iconDiameter: CGFloat = 32
    static let rowMinHeight: CGFloat = 60
    static let horizontalPadding = ExperienceSpacing.md
    static let verticalPadding = ExperienceSpacing.sm
    static let cornerRadius = ExperienceRadius.sm
}

struct DashboardQuickActionRow<Icon: View>: View {
    let title: String
    let subtitle: String
    let accessibilityIdentifier: String
    let accessibilityHint: String?
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    init(
        title: String,
        subtitle: String,
        accessibilityIdentifier: String,
        accessibilityHint: String? = nil,
        @ViewBuilder icon: @escaping () -> Icon,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityHint = accessibilityHint
        self.icon = icon
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ExperienceSpacing.sm) {
                icon()

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
            .padding(.horizontal, DashboardQuickActionStyle.horizontalPadding)
            .padding(.vertical, DashboardQuickActionStyle.verticalPadding)
            .frame(minHeight: DashboardQuickActionStyle.rowMinHeight, alignment: .center)
            .background(colors.surfacePrimary)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DashboardQuickActionStyle.cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: DashboardQuickActionStyle.cornerRadius,
                    style: .continuous
                )
                .stroke(colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint(accessibilityHint ?? "")
    }
}
