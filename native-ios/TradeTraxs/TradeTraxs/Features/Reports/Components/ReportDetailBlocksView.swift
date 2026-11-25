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
            keyMetricsSectionCard(title: block.title) {
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
        .modifier(ReportDetailSectionSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.detail.section.\(title.lowercased())")
    }

    private func keyMetricsSectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
            content()
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ReportDetailSectionSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.detail.section.\(title.lowercased())")
    }

    private func metricsGrid(_ metrics: TradingReportMetrics) -> some View {
        ReportKeyMetricsGrid(metrics: metrics)
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

}
