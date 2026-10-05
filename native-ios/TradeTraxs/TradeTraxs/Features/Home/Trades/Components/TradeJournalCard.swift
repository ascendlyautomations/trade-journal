import SwiftUI

/// Owner-journal trade card for the Trades history page.
///
/// Distinct from ``ProfileTradeCard`` — no likes/comments/share chrome.
/// Fixed vertical template: header → context (+ optional compact thumbnail) → execution → metrics.
struct TradeJournalCard: View {
    let item: TradeOwnerJournalSummary
    let accountName: String?
    var copyParticipatingAccountLines: [String]? = nil
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void
    var onShare: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var summary: TradeSummary { item.summary }

    private var hasImage: Bool {
        guard let thumbnail = summary.thumbnail else { return false }
        return !thumbnail.id.isEmpty
    }

    private var resolvedAccountName: String? {
        if let accountName, !accountName.isEmpty { return accountName }
        return item.accountName
    }

    private var isCopyGroup: Bool {
        guard let lines = copyParticipatingAccountLines else { return false }
        return !lines.isEmpty
    }

    var body: some View {
        Button(action: onOpen) {
            ExperienceCard {
                cardBody
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "chart.xyaxis.line")
            }
            if let onShare {
                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            }
            if let onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } preview: {
            TradeJournalCardPreview(item: item, accountName: resolvedAccountName)
                .frame(width: 320)
                .padding()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Opens trade detail")
        .accessibilityIdentifier("trades.journalCard.\(item.id.rawValue)")
    }

    // MARK: - Template

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            headerRow
            contextWithOptionalThumbnail
            executionRow
            metricsRow
        }
    }

    /// Context + optional compact screenshot (Profile-style thumbnail on the trailing edge).
    private var contextWithOptionalThumbnail: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            contextSection
                .frame(maxWidth: .infinity, alignment: .leading)
            if hasImage {
                tradeThumbnail
            }
        }
    }

    /// Row 1 — ticker + side (left), P&L (right).
    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text(summary.symbol.ticker)
                    .experienceStyle(.headline, color: colors.primaryText)
                    .lineLimit(1)
                Text(TradeDisplay.sideTitle(summary.side).uppercased())
                    .experienceStyle(
                        .caption,
                        color: summary.side == .long ? colors.profit : colors.loss
                    )
                    .fontWeight(.semibold)
            }
            Spacer(minLength: ExperienceSpacing.xs)
            Text(TradeDisplay.pnlText(summary.realizedPnL))
                .experienceStyle(
                    .metric,
                    color: theme.metricColor(
                        for: NSDecimalNumber(decimal: summary.realizedPnL?.amount ?? 0).doubleValue
                    )
                )
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("P and L \(TradeDisplay.pnlText(summary.realizedPnL))")
        }
    }

    /// Row 2 — date/time + account or copy-trade context (once each).
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            if isCopyGroup {
                Text("Copy Traded")
                    .experienceStyle(.caption, color: colors.primaryText)
                    .fontWeight(.semibold)
                ForEach(copyParticipatingAccountLines ?? [], id: \.self) { line in
                    Text(line)
                        .experienceStyle(.caption, color: colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let account = resolvedAccountName, !account.isEmpty {
                Text(account)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }

            Text(TradeDisplay.journalContextLine(accountName: nil, at: summary.entryAt))
                .experienceStyle(.caption, color: colors.secondaryText)
                .lineLimit(1)
        }
    }

    /// Compact list thumbnail — same treatment as Profile browse cards (~96pt wide).
    private var tradeThumbnail: some View {
        ProfileCompactMediaThumbnail(
            reference: summary.thumbnail,
            purpose: .tradeScreenshot,
            imagePipeline: imagePipeline
        )
        .accessibilityHidden(true)
    }

    /// Entry / exit / size — compact three-column execution row.
    private var executionRow: some View {
        HStack(alignment: .top, spacing: ExperienceSpacing.md) {
            journalFieldColumn(
                title: "Entry",
                value: TradeDisplay.priceText(item.entryPrice)
            )
            journalFieldColumn(
                title: "Exit",
                value: TradeDisplay.priceText(item.exitPrice)
            )
            journalFieldColumn(
                title: "Contracts",
                value: TradeDisplay.contractsText(summary.quantity)
            )
        }
    }

    /// Bottom row — duration, R:R, points (left); visibility (right).
    private var metricsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.sm) {
            if let duration = TradeDisplay.journalCardDuration(for: item) {
                journalInlineMetric(title: "Duration", value: duration, layoutPriority: 1)
            }
            if let rr = TradeDisplay.journalRRText(summary.riskReward) {
                journalInlineMetric(title: "R:R", value: rr)
            }
            if let points = TradeDisplay.pointsText(summary.points) {
                journalInlineMetric(title: "Points", value: points)
            }
            Spacer(minLength: ExperienceSpacing.sm)
            visibilityLabel
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func journalFieldColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
            Text(value)
                .experienceStyle(.footnote, color: colors.primaryText)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func journalInlineMetric(
        title: String,
        value: String,
        layoutPriority: Double = 0
    ) -> some View {
        HStack(spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
            Text(value)
                .experienceStyle(.caption, color: colors.primaryText)
                .fontWeight(.medium)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .layoutPriority(layoutPriority)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private var visibilityLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: visibilitySymbol)
                .font(.caption2)
            Text(visibilityTitle)
                .experienceStyle(.caption2, color: colors.tertiaryText)
        }
        .foregroundStyle(colors.tertiaryText)
        .accessibilityLabel(visibilityTitle)
    }

    private var visibilitySymbol: String {
        switch summary.visibility {
        case .public: return "globe"
        case .private: return "lock.fill"
        case .followersOnly: return "person.2.fill"
        }
    }

    private var visibilityTitle: String {
        switch summary.visibility {
        case .public: return "Public"
        case .private: return "Private"
        case .followersOnly: return "Followers"
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            summary.symbol.ticker,
            TradeDisplay.sideTitle(summary.side),
            TradeDisplay.pnlText(summary.realizedPnL),
        ]
        if isCopyGroup {
            parts.append("Copy Traded")
        } else if let resolvedAccountName, !resolvedAccountName.isEmpty {
            parts.append(resolvedAccountName)
        }
        parts.append(TradeDisplay.journalContextLine(accountName: nil, at: summary.entryAt))
        parts.append(visibilityTitle)
        return parts.joined(separator: ", ")
    }
}

/// Lightweight context-menu preview — no network, no engagement chrome.
private struct TradeJournalCardPreview: View {
    let item: TradeOwnerJournalSummary
    let accountName: String?

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private var summary: TradeSummary { item.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(summary.symbol.ticker)
                        .experienceStyle(.headline, color: colors.primaryText)
                    Text(TradeDisplay.sideTitle(summary.side).uppercased())
                        .experienceStyle(.caption, color: colors.secondaryText)
                }
                Spacer()
                Text(TradeDisplay.pnlText(summary.realizedPnL))
                    .experienceStyle(
                        .metric,
                        color: theme.metricColor(
                            for: NSDecimalNumber(decimal: summary.realizedPnL?.amount ?? 0).doubleValue
                        )
                    )
            }
            if let accountName, !accountName.isEmpty {
                Text(accountName)
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Text(TradeDisplay.journalContextLine(accountName: nil, at: summary.entryAt))
                .experienceStyle(.caption, color: colors.tertiaryText)
        }
        .padding()
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous))
    }
}
