import SwiftUI

/// Native Settings disclosure row.
struct SettingsNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var isDestructive: Bool = false
    var showsChevron: Bool = true

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
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("settings.row.\(title)")
    }
}

/// Preference toggle row with optional subtitle.
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

/// Persistent label above an editable field — label stays visible after text is entered.
struct SettingsLabeledField<Content: View>: View {
    let title: String
    var helper: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.footnote, color: colors.secondaryText)
            content()
            if let helper {
                Text(helper)
                    .experienceStyle(.caption, color: colors.tertiaryText)
            }
        }
        .padding(.vertical, ExperienceSpacing.xxs)
        .accessibilityElement(children: .contain)
    }
}

/// Centered, friendly empty / intro copy for sparse Settings pages.
struct SettingsIntroBlock: View {
    let title: String
    let message: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.body, color: colors.primaryText)
            Text(message)
                .experienceStyle(.footnote, color: colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ExperienceSpacing.xs)
    }
}

/// Primary text action for Settings lists (Save, Upgrade, Share).
struct SettingsPrimaryActionLabel: View {
    let title: String
    var systemImage: String? = nil

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            Text(title)
                .experienceStyle(.body, color: colors.accent)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
        .padding(.vertical, ExperienceSpacing.xs)
        .contentShape(Rectangle())
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
