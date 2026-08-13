import SwiftUI

/// Manual column mapping for unrecognized / flexible CSVs.
struct CSVImportMappingView: View {
    @Bindable var viewModel: CSVImportViewModel
    @Environment(\.themeColors) private var colors

    var body: some View {
        List {
            Section {
                Text("Map each CSV column to a TradeTraxs field. Required: Date, Symbol, Direction, P&L.")
                    .experienceStyle(.footnote, color: colors.secondaryText)
            }

            Section("Columns") {
                ForEach(viewModel.columnMappings) { mapping in
                    Picker(mapping.header, selection: binding(for: mapping.header)) {
                        Text("Ignore Column").tag(Optional<CSVLogicalField>.none)
                        ForEach(CSVLogicalField.allCases) { field in
                            Text(field.displayName).tag(Optional(field))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExperienceButton(
                title: "Continue",
                kind: .primary,
                isEnabled: hasRequiredMappings,
                accessibilityIdentifier: "csvImport.mapping.continue"
            ) {
                viewModel.applyMappingsAndContinue()
            }
            .padding(ExperienceSpacing.md)
            .background(colors.backgroundPrimary.opacity(0.96))
        }
        .accessibilityIdentifier("csvImport.mapping")
    }

    private var hasRequiredMappings: Bool {
        let mapped = Set(viewModel.columnMappings.compactMap(\.field))
        return CSVLogicalField.requiredForFlexibleImport.allSatisfy(mapped.contains)
    }

    private func binding(for header: String) -> Binding<CSVLogicalField?> {
        Binding(
            get: { viewModel.columnMappings.first(where: { $0.header == header })?.field },
            set: { viewModel.updateMapping(header: header, field: $0) }
        )
    }
}
