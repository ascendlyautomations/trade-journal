import SwiftUI

/// Shared assistant / user bubble for Trade AI and Psychology Coach conversations.
struct AICoachMessageCard: View {
    let role: AICoachConversationRole
    let content: String
    var assistantTitle: String = "Coach"
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
                if role == .assistant {
                    AICoachMarkdownText(content: content)
                } else {
                    Text(content)
                        .experienceStyle(.body, color: colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
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

    private var shouldOfferCollapse: Bool {
        role == .assistant && content.count > 420
    }

    private var collapsedPreview: String {
        if let verdict = tradeSections?.verdict {
            return verdict
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 160)
        return String(trimmed[..<index]) + "…"
    }
}