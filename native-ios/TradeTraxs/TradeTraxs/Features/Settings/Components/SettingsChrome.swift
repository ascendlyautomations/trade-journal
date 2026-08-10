import SwiftUI

/// Native Settings disclosure row.
struct SettingsNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var isDestructive: Bool = false

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isDestructive ? colors.loss : colors.accent)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.body, color: isDestructive ? colors.loss : colors.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.tertiaryText)
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.row.\(title)")
    }
}

/// Preference toggle row with optional footer.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    @Environment(\.themeColors) private var colors

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(title)
                    .experienceStyle(.body, color: colors.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(!isEnabled)
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityIdentifier("settings.toggle.\(title)")
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .experienceStyle(.body, color: colors.primaryText)
            Spacer(minLength: ExperienceSpacing.sm)
            Text(value)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.info.\(title)")
    }
}

struct SettingsInlineError: View {
    let message: String
    var onRetry: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.warning)
            Text(message)
                .experienceStyle(.footnote, color: colors.secondaryText)
            Spacer(minLength: 0)
            if let onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .experienceStyle(.footnote, color: colors.accent)
                }
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
    }
}
