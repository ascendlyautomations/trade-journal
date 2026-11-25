import SwiftUI

struct DailyCheckInView: View {
    @State private var viewModel: DailyCheckInViewModel
    var onClose: () -> Void
    var onOpenHistory: (() -> Void)?

    @Environment(\.themeColors) private var colors

    private let sectionCardRadius = ExperienceRadius.md
    private let sectionCardPadding = ExperienceSpacing.sm

    init(data: DataEnvironment, onClose: @escaping () -> Void, onOpenHistory: (() -> Void)? = nil) {
        _viewModel = State(
            initialValue: DailyCheckInViewModel(
                repository: data.dailyCheckIns,
                session: data.session,
                existing: TraderDailyCheckInStore.shared.todayCheckIn
            )
        )
        self.onClose = onClose
        self.onOpenHistory = onOpenHistory
    }

    /// Tests / previews.
    init(viewModel: DailyCheckInViewModel, onClose: @escaping () -> Void, onOpenHistory: (() -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onClose = onClose
        self.onOpenHistory = onOpenHistory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                sleepSection
                morningSection
                mentalStateSection
                notesSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .experienceStyle(.caption, color: colors.loss)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        if await viewModel.save() {
                            ExperienceHaptics.play(.success)
                            onClose()
                        } else {
                            ExperienceHaptics.play(.error)
                        }
                    }
                } label: {
                    Group {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(colors.onAccent)
                        } else {
                            Text("Save Check-In")
                                .font(ExperienceTypography.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: ExperienceSpacing.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("dailyCheckIn.save")
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(colors.groupedBackground.ignoresSafeArea())
        .experienceNavigationTitle("Daily Check-In")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { onClose() }
            }
            if let onOpenHistory {
                ToolbarItem(placement: .primaryAction) {
                    Button("History", action: onOpenHistory)
                }
            }
        }
        .experienceProtectedFormDismiss()
        .accessibilityIdentifier("dailyCheckIn.sheet")
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionLabel("Sleep")

            VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                Text("Hours of Sleep")
                    .font(ExperienceTypography.footnote.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                HStack(spacing: ExperienceSpacing.sm) {
                    TextField("7.5", text: sleepHoursBinding.numericInput(.unsignedDecimal(maxFractionDigits: 1)))
                        .font(ExperienceTypography.subheadline)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, ExperienceSpacing.sm)
                        .padding(.vertical, ExperienceSpacing.xxs)
                        .frame(minHeight: ExperienceSpacing.minTouchTarget, alignment: .center)
                        .background(
                            colors.fillSecondary,
                            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .stroke(colors.border, lineWidth: ExperienceBorder.thin)
                        )
                        .accessibilityIdentifier("dailyCheckIn.sleepHours")
                    Text("hours")
                        .experienceStyle(.callout, color: colors.secondaryText)
                }
            }

            CompactRatingSelector(
                title: "Sleep Quality",
                value: $viewModel.draft.sleepQuality,
                lowLabel: "Poor",
                highLabel: "Great",
                density: .compact
            )
            .accessibilityIdentifier("dailyCheckIn.sleepQuality")
        }
        .padding(sectionCardPadding)
        .experienceDashboardCard(cornerRadius: sectionCardRadius)
    }

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionLabel("Morning")
            CompactRatingSelector(
                title: "How's your morning?",
                value: $viewModel.draft.morningRating,
                lowLabel: "Rough",
                highLabel: "Great",
                density: .compact
            )
            .accessibilityIdentifier("dailyCheckIn.morning")
        }
        .padding(sectionCardPadding)
        .experienceDashboardCard(cornerRadius: sectionCardRadius)
    }

    private var mentalStateSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionLabel("Mental State")
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                CompactRatingSelector(
                    title: "Stress",
                    value: $viewModel.draft.stressLevel,
                    lowLabel: "Calm",
                    highLabel: "Very Stressed",
                    density: .compact
                )
                .accessibilityIdentifier("dailyCheckIn.stress")
                CompactRatingSelector(
                    title: "Energy",
                    value: $viewModel.draft.energyLevel,
                    lowLabel: "Low",
                    highLabel: "High",
                    density: .compact
                )
                .accessibilityIdentifier("dailyCheckIn.energy")
                CompactRatingSelector(
                    title: "Focus",
                    value: $viewModel.draft.focusLevel,
                    lowLabel: "Scattered",
                    highLabel: "Sharp",
                    density: .compact
                )
                .accessibilityIdentifier("dailyCheckIn.focus")
            }
        }
        .padding(sectionCardPadding)
        .experienceDashboardCard(cornerRadius: sectionCardRadius)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            sectionLabel("Notes")
            Text("Anything affecting your trading today?")
                .experienceStyle(.caption, color: colors.secondaryText)
            TextEditor(text: $viewModel.draft.notes)
                .font(ExperienceTypography.subheadline)
                .frame(minHeight: 64, maxHeight: 104)
                .scrollContentBackground(.hidden)
                .padding(ExperienceSpacing.xs)
                .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                .accessibilityIdentifier("dailyCheckIn.notes")
                .experienceTextInputProbe(
                    screen: "dailyCheckIn",
                    field: "dailyCheckIn.notes",
                    text: viewModel.draft.notes,
                    isFocused: false
                )
        }
        .padding(sectionCardPadding)
        .experienceDashboardCard(cornerRadius: sectionCardRadius)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(ExperienceTypography.subheadline.weight(.semibold))
            .foregroundStyle(colors.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var sleepHoursBinding: Binding<String> {
        Binding(
            get: { viewModel.sleepHoursText },
            set: { viewModel.sleepHoursText = $0 }
        )
    }
}