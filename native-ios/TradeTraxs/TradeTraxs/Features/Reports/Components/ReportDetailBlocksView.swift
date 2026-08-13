import SwiftUI

/// Renders dynamic Trading Report sections returned by the web-parity generator.
struct ReportDetailBlocksView: View {
    let blocks: [TradingReportDetailBlock]
    var bestTrade: ReportDetailState.BestTradeReference?
    var onOpenBestTrade: () -> Void = {}

    @Environment(\.themeColors) private var colors

    var body: some View {
        LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            ForEach(blocks) { block in
                blockView(block)
                    .padding(.horizontal, ExperienceSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: TradingReportDetailBlock) -> some View {
        switch block {
        case .summary(let text):
            sectionCard(title: block.title, accent: colors.accent) {
                markdownText(text)
            }

        case .metrics(let metrics):
            sectionCard(title: block.title, accent: colors.primaryText) {
                metricsGrid(metrics)
            }

        case .strengths(let items):
            bulletSection(title: block.title, items: items, tone: colors.profit)

        case .opportunities(let items):
            bulletSection(title: block.title, items: items, tone: colors.warning)

        case .recommendations(let items):
            bulletSection(title: block.title, items: items, tone: colors.info)

        case .bestTrade:
            ReportBestTradeCard(
                presentation: bestTradePresentation,
                onOpen: onOpenBestTrade
            )

        case .keyTakeaway(let text):
            sectionCard(title: block.title, accent: colors.accent) {
                markdownText(text)
            }
        }
    }

    private var bestTradePresentation: ReportBestTradeCard.Presentation {
        switch bestTrade {
        case .loading: return .loading
        case .available(let trade): return .available(trade)
        case .unavailable: return .unavailable
        case .none: return .loading
        }
    }

    private func bulletSection(title: String, items: [String], tone: Color) -> some View {
        sectionCard(title: title, accent: tone) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: ExperienceSpacing.sm) {
                        Circle()
                            .fill(tone)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        markdownText(item)
                    }
                    .padding(ExperienceSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tone.opacity(0.08), in: RoundedRectangle(
                        cornerRadius: ExperienceRadius.sm,
                        style: .continuous
                    ))
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text(title)
                .experienceStyle(.headline, color: accent)
            content()
        }
        .padding(ExperienceSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .fill(colors.fillSecondary.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                        .stroke(colors.border.opacity(0.45), lineWidth: ExperienceBorder.thin)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.detail.section.\(title.lowercased())")
    }

    private func metricsGrid(_ metrics: TradingReportMetrics) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
                GridItem(.flexible(), spacing: ExperienceSpacing.sm),
            ],
            spacing: ExperienceSpacing.sm
        ) {
            metricCell("Net P&L", formatPnl(metrics.netPnl))
            metricCell(
                "Win Rate",
                metrics.tradesTaken > 0
                    ? String(format: "%.1f%%", metrics.winRate)
                    : "—"
            )
            metricCell(
                "Average RR",
                metrics.averageRr.map { formatRR($0) } ?? "—"
            )
            metricCell(
                "Profit Factor",
                metrics.profitFactor.map { String(format: "%.2f", $0) } ?? "—"
            )
            metricCell("Trades Taken", "\(metrics.tradesTaken)")
            metricCell(
                "Best Day",
                metrics.bestDayLabel.map {
                    "\($0) (\(formatPnl(metrics.bestDayPnl ?? 0)))"
                } ?? "—"
            )
            metricCell(
                "Worst Day",
                metrics.worstDayLabel.map {
                    "\($0) (\(formatPnl(metrics.worstDayPnl ?? 0)))"
                } ?? "—"
            )
            metricCell("Best Session", metrics.bestSessionLabel ?? "—")
            metricCell("Worst Session", metrics.worstSessionLabel ?? "—")
            metricCell("Most Traded", metrics.mostTradedSymbol ?? "—")
            metricCell(
                "Avg Hold Time",
                metrics.averageHoldTimeSeconds.map(formatHold) ?? "—"
            )
        }
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary.opacity(0.65), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .experienceStyle(.subheadline, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatPnl(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted = absValue.formatted(
            .number.precision(.fractionLength(2)).grouping(.automatic)
        )
        return value < 0 ? "-$\(formatted)" : "$\(formatted)"
    }

    private func formatRR(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func formatHold(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
