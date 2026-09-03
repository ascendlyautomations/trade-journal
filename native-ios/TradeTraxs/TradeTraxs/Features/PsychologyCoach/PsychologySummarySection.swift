import SwiftUI

struct PsychologySummarySection: View {
    let summary: PsychologyCoachSummary
    var onOpenCoach: (() -> Void)?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            Text(summary.title)
                .experienceStyle(.title3, color: colors.primaryText)
                .fontWeight(.bold)

            Text(summary.overview)
                .experienceStyle(.body, color: colors.secondaryText)

            if !summary.doingWell.isEmpty {
                labeledBullets(title: "What You're Doing Well", items: summary.doingWell, tint: colors.success)
            }

            if !summary.watchItems.isEmpty {
                labeledBullets(title: "What to Watch", items: summary.watchItems, tint: colors.warning)
            }

            if !summary.recommendations.isEmpty {
                labeledBullets(title: "Possible Guardrails", items: summary.recommendations, tint: colors.accent)
            }

            if let onOpenCoach {
                Button(action: onOpenCoach) {
                    Label("Open Psychology Coach", systemImage: "person.fill.questionmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .accessibilityIdentifier("psychologyCoach.summary")
    }

    private func labeledBullets(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(item)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                }
            }
        }
    }
}
