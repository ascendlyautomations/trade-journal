import SwiftUI

/// Shared owner copy-trade context for Trades list cards and journal trade detail.
struct CopyTradeOwnerJournalContextView: View {
    let display: CopyTradeOwnerJournalDisplay

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            Text(display.headerTitle)
                .experienceStyle(.caption, color: colors.primaryText)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(display.visibleAccountLines, id: \.self) { line in
                Text(line)
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let overflow = display.overflowSummary, !overflow.isEmpty {
                Text(overflow)
                    .experienceStyle(.caption2, color: colors.tertiaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}