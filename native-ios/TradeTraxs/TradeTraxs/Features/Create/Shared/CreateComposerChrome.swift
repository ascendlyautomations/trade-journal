import SwiftUI

/// Shared bottom publish bar — matches `CreatePostView`.
struct CreateComposerPublishBar: View {
    let title: String
    var loadingTitle: String? = nil
    var progress: Double? = nil
    let isEnabled: Bool
    let isLoading: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            ExperienceDivider()
            if let progress {
                ProgressView(value: progress)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .padding(.top, ExperienceSpacing.xs)
            }
            ExperienceButton(
                title: isLoading ? (loadingTitle ?? title) : title,
                kind: .primary,
                isEnabled: isEnabled && !isLoading,
                isLoading: isLoading,
                accessibilityIdentifier: accessibilityIdentifier
            ) {
                action()
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.sm + 2)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
    }
}

/// Teal attachment action — matches New Post `Add photo`.
struct CreateComposerAttachmentAction: View {
    let systemImage: String
    let title: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(ExperienceTypography.subheadline.weight(.semibold))
        }
        .foregroundStyle(colors.accent)
    }
}

/// Circular remove control for attached media previews.
struct CreateComposerPreviewDismissButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.62), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Section label used across create composers.
struct CreateComposerSectionLabel: View {
    let title: String

    @Environment(\.themeColors) private var colors

    var body: some View {
        Text(title)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .textCase(nil)
    }
}

/// Multiline placeholder editor shared by create composers.
struct CreateComposerMultilineField: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 72
    var accessibilityIdentifier: String? = nil
    var accessibilityLabel: String? = nil

    @Environment(\.themeColors) private var colors
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .experienceStyle(.body, color: colors.tertiaryText)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($isFocused)
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.primaryText)
                .frame(minHeight: minHeight, alignment: .top)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .applyOptionalAccessibilityIdentifier(accessibilityIdentifier)
                .applyOptionalAccessibilityLabel(accessibilityLabel)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyOptionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyOptionalAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            accessibilityLabel(label)
        } else {
            self
        }
    }
}
