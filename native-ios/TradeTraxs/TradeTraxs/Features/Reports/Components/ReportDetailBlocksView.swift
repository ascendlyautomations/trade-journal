import SwiftUI

/// Renders dynamic Trading Report sections returned by the web-parity generator.
struct ReportDetailBlocksView: View {
    let blocks: [TradingReportDetailBlock]
    var bestTrade: ReportDetailState.BestTradeReference?
    var onOpenBestTrade: () -> Void = {}

    @Environment(\.themeColors) private var colors

    var body: some View {
        LazyVStack(alignment: .leading, spacing: ReportDetailLayout.sectionSpacing) {
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

        case .strengthsAndWeaknesses(let strengths, let weaknesses):
            strengthsAndWeaknessesSection(strengths: strengths, weaknesses: weaknesses)

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

    private func strengthsAndWeaknessesSection(strengths: [String], weaknesses: [String]) -> some View {
        sectionCard(title: "Strengths & Weaknesses", accent: colors.primaryText) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                if !strengths.isEmpty {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text("Strengths")
                            .experienceStyle(.footnote, color: colors.profit)
                            .fontWeight(.semibold)
                        ForEach(strengths, id: \.self) { item in
                            strengthWeaknessRow(item, tone: colors.profit)
                        }
                    }
                }
                if !weaknesses.isEmpty {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text("Weaknesses")
                            .experienceStyle(.footnote, color: colors.warning)
                            .fontWeight(.semibold)
                        ForEach(weaknesses, id: \.self) { item in
                            strengthWeaknessRow(item, tone: colors.warning)
                        }
                    }
                }
            }
        }
    }

    private func strengthWeaknessRow(_ item: String, tone: Color) -> some View {
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
            metricCell(
                "Net P&L",
                metrics.knownResultCount > 0 ? formatPnl(metrics.netPnl) : "—"
            )
            metricCell(
                "Win Rate",
                metrics.knownResultCount > 0
                    ? NumberDisplay.percent(metrics.winRate, minimumFractionDigits: 1, maximumFractionDigits: 1)
                    : "—"
            )
            metricCell(
                "Average RR",
                metrics.averageRr.map { formatRR($0) } ?? "—"
            )
            metricCell(
                "Profit Factor",
                metrics.profitFactor.map { NumberDisplay.ratio($0, fractionDigits: 2) } ?? "—"
            )
            metricCell("Trades Taken", NumberDisplay.integer(metrics.tradesTaken))
            labelAndPnLMetricCell(
                "Best Day",
                dayLabel: metrics.bestDayLabel,
                pnl: metrics.bestDayPnl
            )
            labelAndPnLMetricCell(
                "Worst Day",
                dayLabel: metrics.worstDayLabel,
                pnl: metrics.worstDayPnl
            )
            labelAndPnLMetricCell(
                "Best Session",
                dayLabel: metrics.bestSessionLabel,
                pnl: metrics.bestSessionPnl
            )
            labelAndPnLMetricCell(
                "Worst Session",
                dayLabel: metrics.worstSessionLabel,
                pnl: metrics.worstSessionPnl
            )
            metricCell("Most Traded", metrics.mostTradedSymbol ?? "—")
            metricCell(
                "Avg Hold Time",
                metrics.averageHoldTimeSeconds.map(formatHold) ?? "—"
            )
        }
    }

    private func labelAndPnLMetricCell(_ title: String, dayLabel: String?, pnl: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .experienceStyle(.caption2, color: colors.tertiaryText)
                .tracking(0.4)
            if let dayLabel, let pnl {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabel)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(colors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(formatPnl(pnl))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(metricPnLTone(pnl))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("—")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(colors.primaryText)
            }
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundSecondary.opacity(0.65), in: RoundedRectangle(
            cornerRadius: ExperienceRadius.sm,
            style: .continuous
        ))
    }

    private func metricPnLTone(_ pnl: Double) -> Color {
        if pnl > 0.01 { return colors.profit }
        if pnl < -0.01 { return colors.loss }
        return colors.primaryText
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
        NumberDisplay.reportPnL(value)
    }

    private func formatRR(_ value: Double) -> String {
        NumberDisplay.decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }

    private func formatHold(_ seconds: Int) -> String {
        TradeHoldDuration.formatSeconds(seconds) ?? "—"
    }
}
