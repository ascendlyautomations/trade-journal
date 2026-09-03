import SwiftUI

/// Add Trade hub — manual entry, CSV import, or screenshot import.
struct TradeEntryHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case importTrades = "Import"

        var id: String { rawValue }
    }

    enum ImportChannel: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case screenshot = "Screenshot"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .csv:
                return "Import trades from your broker CSV export"
            case .screenshot:
                return "Import trades from trade-history screenshots"
            }
        }
    }

    let data: DataEnvironment
    let initialTab: Tab
    let initialImportChannel: ImportChannel
    let onDismiss: () -> Void

    @State private var tab: Tab
    @State private var importChannel: ImportChannel
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        initialTab: Tab = .manual,
        initialImportChannel: ImportChannel = .csv,
        onDismiss: @escaping () -> Void
    ) {
        self.data = data
        self.initialTab = initialTab
        self.initialImportChannel = initialImportChannel
        self.onDismiss = onDismiss
        _tab = State(initialValue: initialTab)
        _importChannel = State(initialValue: initialImportChannel)
    }

    var body: some View {
        VStack(spacing: 0) {
            hubHeader

            Group {
                switch tab {
                case .manual:
                    AddTradeView(
                        data: data,
                        mode: .create,
                        embeddedInTradeEntryHub: true,
                        onDismiss: onDismiss
                    )
                    .accessibilityIdentifier("tradeEntry.manual")
                case .importTrades:
                    importContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Add Trade")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDismiss)
            }
        }
        .accessibilityIdentifier("tradeEntry.hub")
    }

    @ViewBuilder
    private var importContent: some View {
        switch importChannel {
        case .csv:
            CSVImportView(
                data: data,
                embeddedInTradeEntryHub: true,
                onDismiss: onDismiss
            )
            .accessibilityIdentifier("tradeEntry.importCSV")
        case .screenshot:
            ScreenshotImportView(
                data: data,
                embeddedInTradeEntryHub: true,
                onDismiss: onDismiss
            )
            .accessibilityIdentifier("tradeEntry.importScreenshot")
        }
    }

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Picker("Trade entry method", selection: $tab) {
                ForEach(Tab.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tradeEntry.modePicker")

            if tab == .importTrades {
                Picker("Import method", selection: $importChannel) {
                    ForEach(ImportChannel.allCases) { channel in
                        Text(channel.rawValue).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("tradeEntry.importChannelPicker")
            }

            Text(subtitle)
                .experienceStyle(.caption, color: colors.secondaryText)
                .accessibilityIdentifier("tradeEntry.modeSubtitle")
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, ExperienceSpacing.xs)
        .background(colors.groupedBackground)
    }

    private var subtitle: String {
        switch tab {
        case .manual:
            return "Enter a trade manually"
        case .importTrades:
            return importChannel.subtitle
        }
    }
}
