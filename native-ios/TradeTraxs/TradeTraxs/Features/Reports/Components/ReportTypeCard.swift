import SwiftUI

/// Premium catalog card for a Trading Report period — Generate / View Report CTA.
struct ReportTypeCard: View {
    let model: ReportTypeCardModel
    var isGenerating: Bool = false
    let onPrimaryAction: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            HStack(alignment: .top, spacing: ExperienceSpacing.md) {
                iconBadge
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text(model.title)
                        .experienceStyle(.title3, color: colors.primaryText)
                    Text(model.subtitle)
                        .experienceStyle(.subheadline, color: colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: onPrimaryAction) {
                HStack(spacing: ExperienceSpacing.xs) {
                    if isGenerating {
                        ProgressView()
                            .tint(colors.onAccent)
                    }
                    Text(isGenerating ? "Generating…" : model.actionTitle)
                        .font(ExperienceTypography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.sm)
                .foregroundStyle(colors.onAccent)
                .background(colors.accent, in: RoundedRectangle(
                    cornerRadius: ExperienceRadius.button,
                    style: .continuous
                ))
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .accessibilityIdentifier("reports.card.\(model.periodKey.rawValue).action")
        }
        .padding(ExperienceSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(colors.fillSecondary.opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .stroke(colors.border.opacity(0.55), lineWidth: ExperienceBorder.thin)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(colors.accent.opacity(0.12))
                        .frame(width: 120, height: 120)
                        .blur(radius: 28)
                        .offset(x: 36, y: -40)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.card.\(model.periodKey.rawValue)")
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.accent.opacity(0.22),
                            colors.accent.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            Image(systemName: model.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colors.accent)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}
