import SwiftUI

/// Compact time-scope menu for the psychology report navigation bar.
struct PsychologyReportDateScopeToolbarMenu: View {
    @Bindable var viewModel: PsychologyReportDetailViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

    private var chevronColor: Color {
        colorScheme == .light ? colors.secondaryText : colors.tertiaryText
    }

    var body: some View {
        Menu {
            ForEach(PsychologyReportTimePreset.allCases) { preset in
                Button {
                    ExperienceHaptics.play(.selection)
                    viewModel.selectPreset(preset)
                } label: {
                    if isSelected(preset) {
                        Label(preset.menuTitle, systemImage: "checkmark")
                    } else {
                        Text(preset.menuTitle)
                    }
                }
            }
            Divider()
            Button {
                ExperienceHaptics.play(.selection)
                viewModel.openCustomDateSheet()
            } label: {
                if case .custom = viewModel.selectedTimeScope {
                    Label(customMenuTitle, systemImage: "checkmark")
                } else {
                    Text("Custom")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.timeScopeMenuTitle)
                    .experienceStyle(.footnote, color: colors.primaryText)
                    .fontWeight(colorScheme == .light ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: chevronColor)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .experienceFilterCapsule()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Report date range")
        .accessibilityValue(viewModel.timeScopeMenuTitle)
        .accessibilityIdentifier("psychologyReport.dateScope")
    }

    private var customMenuTitle: String {
        if case .custom = viewModel.selectedTimeScope {
            return viewModel.timeScopeMenuTitle
        }
        return "Custom"
    }

    private func isSelected(_ preset: PsychologyReportTimePreset) -> Bool {
        if case .preset(let current) = viewModel.selectedTimeScope {
            return current == preset
        }
        return false
    }
}

struct PsychologyReportCustomDateRangeSheet: View {
    @Bindable var viewModel: PsychologyReportDetailViewModel

    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start",
                        selection: customStartBinding,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End",
                        selection: customEndBinding,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .experienceNavigationTitle("Custom Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.applyCustomDateRange()
                        dismiss()
                    }
                    .disabled(!viewModel.canApplyCustomDateRange)
                }
            }
        }
        .accessibilityIdentifier("psychologyReport.customDateSheet")
    }

    private var customStartBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftCustomRangeStart ?? Date() },
            set: { viewModel.draftCustomRangeStart = $0 }
        )
    }

    private var customEndBinding: Binding<Date> {
        Binding(
            get: { viewModel.draftCustomRangeEnd ?? Date() },
            set: { viewModel.draftCustomRangeEnd = $0 }
        )
    }
}