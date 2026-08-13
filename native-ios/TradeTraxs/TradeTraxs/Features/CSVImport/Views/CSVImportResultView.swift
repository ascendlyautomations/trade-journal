import SwiftUI

struct CSVImportResultView: View {
    let result: CSVImportResult
    let onDone: () -> Void
    let onAgain: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    var body: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(colors.accent)
            Text("Import Complete")
                .experienceStyle(.title, color: colors.primaryText)
            Text("\(result.importedCount) Trades Imported")
                .experienceStyle(.headline, color: colors.primaryText)
            Text(TradeDisplay.pnlText(Money(amount: result.netPnL)))
                .experienceStyle(
                    .metricLarge,
                    color: theme.metricColor(
                        for: NSDecimalNumber(decimal: result.netPnL).doubleValue
                    )
                )
            if result.skippedInvalidCount > 0 {
                Text("\(result.skippedInvalidCount) rows skipped")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }
            Spacer()
            ExperienceButton(
                title: "Done",
                kind: .primary,
                accessibilityIdentifier: "csvImport.done"
            ) {
                onDone()
            }
            Button(action: onAgain) {
                Text("Import Another CSV")
                    .experienceStyle(.body, color: colors.accent)
            }
            .buttonStyle(.plain)
            .padding(.bottom, ExperienceSpacing.lg)
        }
        .padding(.horizontal, ExperienceSpacing.lg)
        .accessibilityIdentifier("csvImport.result")
    }
}
