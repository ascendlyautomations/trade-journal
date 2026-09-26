import SwiftUI

/// Add Trade hub — manual entry or CSV import.
struct TradeEntryHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case csv = "CSV"

        var id: String { rawValue }
    }

    let data: DataEnvironment
    let initialTab: Tab
    let onDismiss: () -> Void

    @State private var tab: Tab
    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        initialTab: Tab = .manual,
        onDismiss: @escaping () -> Void
    ) {
        self.data = data
        self.initialTab = initialTab
        self.onDismiss = onDismiss
        _tab = State(initialValue: initialTab)
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
                case .csv:
                    CSVImportView(
                        data: data,
                        embeddedInTradeEntryHub: true,
                        onDismiss: onDismiss
                    )
                    .accessibilityIdentifier("tradeEntry.importCSV")
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
        .experienceProtectedFormDismiss()
        .accessibilityIdentifier("tradeEntry.hub")
    }

    private var hubHeader: some View {
        Picker("Trade entry method", selection: $tab) {
            ForEach(Tab.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("tradeEntry.modePicker")
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.sm)
        .padding(.bottom, ExperienceSpacing.md)
        .background(colors.groupedBackground)
    }
}
