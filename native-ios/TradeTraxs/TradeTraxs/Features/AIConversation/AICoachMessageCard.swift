import SwiftUI

/// Shared assistant / user bubble for Trade AI and Psychology Coach conversations.
struct AICoachMessageCard: View {
    let role: AICoachConversationRole
    let content: String
    var assistantTitle: String = "Coach"
    var psychologyStructured: PsychologyCoachStructuredSections?

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = true

    private var tradeSections: TradeAICoachSections? {
        guard role == .assistant else { return nil }
        return TradeAICoachResponseParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            header
            if isExpanded {
                if let psychologyStructured, psychologyStructured.isStructured {
                    psychologyBody(psychologyStructured)
                } else {
                    markdownBody
                }
            } else {
                Text(collapsedPreview)
                    .experienceStyle(.body, color: colors.primaryText)
                    .lineLimit(3)
            }
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            role == .assistant ? colors.fillPrimary : colors.fillSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
    }

    private var header: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: role == .assistant ? "sparkles" : "person.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
            Text(role == .assistant ? assistantTitle : "You")
                .experienceStyle(.caption, color: colors.secondaryText)
            Spacer(minLength: 0)
            if shouldOfferCollapse {
                Button {
                    ExperienceHaptics.play(.selection)
                    ExperienceMotion.withAnimation(ExperienceMotion.selection, reduceMotion: reduceMotion) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Collapse" : "Expand")
                        .experienceStyle(.caption2, color: colors.accent)
                }
                .buttonStyle(.experiencePlain)
            }
        }
    }

    @ViewBuilder
    private func psychologyBody(_ sections: PsychologyCoachStructuredSections) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            sectionBlock(title: "Biggest Psychological Insight", body: sections.biggestInsight)
            bulletBlock(title: "Performance Patterns", items: sections.performancePatterns)
            bulletBlock(title: "Areas for Improvement", items: sections.areasForImprovement)
            bulletBlock(title: "Recommended Guardrails", items: sections.recommendedGuardrails)
            sectionBlock(title: "Next Session Focus", body: sections.nextSessionFocus)
        }
    }

    @ViewBuilder
    private func sectionBlock(title: String, body: String?) -> some View {
        if let body, !body.isEmpty {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(title)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .textCase(.uppercase)
                Text(body)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func bulletBlock(title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text(title)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .textCase(.uppercase)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("• \(item)")
                        .experienceStyle(.body, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var markdownBody: some View {
        if let attributed = try? AttributedString(
            markdown: AIGeneratedTextNormalizer.normalize(content),
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(colors.primaryText)
                .tint(colors.accent)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(AIGeneratedTextNormalizer.normalize(content))
                .experienceStyle(.body, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var shouldOfferCollapse: Bool {
        role == .assistant && content.count > 420
    }

    private var collapsedPreview: String {
        if let focus = psychologyStructured?.nextSessionFocus {
            return focus
        }
        if let verdict = tradeSections?.verdict {
            return verdict
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<index]) + "…"
    }
}