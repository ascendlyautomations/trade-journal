import SwiftUI

/// Unified compact catalog row for Performance and Psychology reports.
struct ReportCard: View {
    enum TrailingBehavior {
        /// Trailing label is visual only; the whole card uses `onTap`.
        case decorative
        /// Trailing label is its own button (e.g. Choose Period).
        case interactive(() -> Void)
    }

    let systemImage: String
    let title: String
    let subtitle: String
    var trailingTitle: String
    var isGenerating: Bool = false
    var isDisabled: Bool = false
    var trailingBehavior: TrailingBehavior = .decorative
    let onTap: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        switch trailingBehavior {
        case .decorative:
            Button(action: onTap) {
                cardContent(showTrailingAsButton: false)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isGenerating)
        case .interactive(let trailingAction):
            cardContent(showTrailingAsButton: true, trailingAction: trailingAction)
        }
    }

    @ViewBuilder
    private func cardContent(
        showTrailingAsButton: Bool,
        trailingAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: ExperienceSpacing.md) {
            if showTrailingAsButton {
                Button(action: onTap) {
                    leadingContent
                }
                .buttonStyle(.plain)
                .disabled(isDisabled || isGenerating)
            } else {
                leadingContent
            }

            Spacer(minLength: ExperienceSpacing.xs)

            trailingLabel(showAsButton: showTrailingAsButton, action: trailingAction)
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var leadingContent: some View {
        HStack(spacing: ExperienceSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(colors.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func trailingLabel(showAsButton: Bool, action: (() -> Void)?) -> some View {
        Group {
            if isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .tint(colors.accent)
            } else if showAsButton, let action {
                Button(action: action) {
                    Text(trailingTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text(trailingTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.accent)
            }
        }
        .frame(minWidth: 72, alignment: .trailing)
    }

    static func trailingTitle(for actionTitle: String, isGenerating: Bool) -> String {
        if isGenerating { return "Generating…" }
        switch actionTitle {
        case "View Report": return "View ›"
        case "Generate": return "Generate ›"
        case "Choose Period": return "Choose Period ›"
        default:
            return actionTitle.hasSuffix("›") ? actionTitle : "\(actionTitle) ›"
        }
    }
}
