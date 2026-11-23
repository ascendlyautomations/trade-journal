import SwiftUI

struct PsychologyReportDateScopeBar: View {
    @Bindable var viewModel: PsychologyReportDetailViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ExperienceSpacing.xs) {
                    ForEach(PsychologyReportTimePreset.allCases) { preset in
                        presetChip(preset)
                    }
                    customChip
                }
                .padding(.vertical, ExperienceSpacing.xxs)
            }
        }
        .accessibilityIdentifier("psychologyReport.dateScope")
    }

  private func presetChip(_ preset: PsychologyReportTimePreset) -> some View {
        let selected: Bool = {
            if case .preset(let current) = viewModel.selectedTimeScope {
                return current == preset
            }
            return false
        }()
        return Button {
            viewModel.selectPreset(preset)
        } label: {
            Text(preset.menuTitle)
                .experienceStyle(.footnote, color: selected ? colors.accent : colors.primaryText)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, ExperienceSpacing.sm)
                .frame(minHeight: 32)
                .tradingRulesFilterChip()
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: ExperienceRadius.chip, style: .continuous)
                            .stroke(colors.accent.opacity(0.5), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var customChip: some View {
        let selected: Bool = {
            if case .custom = viewModel.selectedTimeScope { return true }
            return false
        }()
        return Button {
            viewModel.openCustomDateSheet()
        } label: {
            HStack(spacing: 4) {
                Text(selected ? viewModel.timeScopeMenuTitle : "Custom")
                    .experienceStyle(.footnote, color: selected ? colors.accent : colors.primaryText)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                ExperienceIcon(icon: .chevronDown, size: .xs, color: colors.tertiaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .frame(minHeight: 32)
            .tradingRulesFilterChip()
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Custom date range")
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