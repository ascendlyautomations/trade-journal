import SwiftUI

/// Embedded assistant / user message card inside Trade Detail (not a floating chat).
struct TradeAIMessageCard: View {
    let message: TradeAIMessage

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = true

    private var coachSections: TradeAICoachSections? {
        guard message.role == .assistant else { return nil }
        return TradeAICoachResponseParser.parse(message.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.xs) {
                Image(systemName: message.role == .assistant ? "brain.head.profile" : "person.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                Text(message.role == .assistant ? "Trade AI" : "You")
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
                    .buttonStyle(.plain)
                }
            }

            if isExpanded {
                if let sections = coachSections {
                    coachBody(sections)
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
            message.role == .assistant ? colors.fillPrimary : colors.fillSecondary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            message.role == .assistant ? "detail.trade.ai.assistant" : "detail.trade.ai.user"
        )
    }

    @ViewBuilder
    private func coachBody(_ sections: TradeAICoachSections) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            if let verdict = sections.verdict {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("Verdict")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .textCase(.uppercase)
                    Text(verdict)
                        .font(.system(.body, design: .default).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("detail.trade.ai.verdict")
            }

            if let insight = sections.biggestInsight {
                coachSection(title: "Biggest Insight", body: insight)
            }

            if !sections.keyImprovements.isEmpty {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                    Text("Key Improvements")
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .textCase(.uppercase)
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        ForEach(Array(sections.keyImprovements.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                                Text("•")
                                    .experienceStyle(.body, color: colors.secondaryText)
                                    .frame(width: 12, alignment: .leading)
                                Text(item)
                                    .experienceStyle(.body, color: colors.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if let next = sections.nextTradeFocus {
                coachSection(title: "Next Trade Focus", body: next)
            }
        }
    }

    private func coachSection(title: String, body: String) -> some View {
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

    @ViewBuilder
    private var markdownBody: some View {
        if let attributed = try? AttributedString(
            markdown: message.content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(colors.primaryText)
                .tint(colors.accent)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .experienceStyle(.body, color: colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var shouldOfferCollapse: Bool {
        message.role == .assistant && message.content.count > 420
    }

    private var collapsedPreview: String {
        if let verdict = coachSections?.verdict {
            return verdict
        }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<index]) + "…"
    }
}
