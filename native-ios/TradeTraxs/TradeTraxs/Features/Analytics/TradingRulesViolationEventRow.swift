import SwiftUI

struct TradingRulesViolationEventRow: View {
    let event: TradingRulesComplianceAnalytics.ViolationEvent
    var onOpenTrade: ((TradeID) -> Void)?

    @Environment(\.themeColors) private var colors

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        let canOpen = event.tradeID != nil && onOpenTrade != nil
        Button {
            guard canOpen, let raw = event.tradeID else { return }
            onOpenTrade?(TradeID(raw))
        } label: {
            HStack(alignment: .center, spacing: ExperienceSpacing.sm) {
                Image(systemName: levelIcon)
                    .font(.caption)
                    .foregroundStyle(colors.loss)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.ruleLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                    Text(event.summary)
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(2)
                    if event.level != .trade {
                        Text(levelCaption)
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                    }
                }

                Spacer(minLength: ExperienceSpacing.xs)

                Text(Self.dateFormatter.string(from: event.at))
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .monospacedDigit()

                if canOpen {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tertiaryText)
                }
            }
            .padding(.vertical, ExperienceSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }

    private var levelIcon: String {
        switch event.level {
        case .trade: return "exclamationmark.triangle.fill"
        case .day: return "calendar.badge.exclamationmark"
        case .week: return "calendar"
        }
    }

    private var levelCaption: String {
        switch event.level {
        case .trade: return ""
        case .day: return "Day-level check"
        case .week: return "Week-level check"
        }
    }
}
