import SwiftUI

struct DailyCheckInView: View {
    @State private var viewModel: DailyCheckInViewModel
    var onClose: () -> Void
    var onOpenHistory: (() -> Void)?

    @Environment(\.themeColors) private var colors

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
            VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                sleepSection
                morningSection
                mentalStateSection
                notesSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .experienceStyle(.footnote, color: colors.loss)
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
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(colors.accent)
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("dailyCheckIn.save")
            }
            .padding(ExperienceSpacing.md)
        }
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
        .accessibilityIdentifier("dailyCheckIn.sheet")
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            sectionLabel("Sleep")

            VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                Text("Hours of Sleep")
                    .font(ExperienceTypography.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primaryText)
                HStack(spacing: ExperienceSpacing.sm) {
                    TextField("7.5", text: sleepHoursBinding)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("dailyCheckIn.sleepHours")
                    Text("hours")
                        .experienceStyle(.body, color: colors.secondaryText)
                }
            }

            CompactRatingSelector(
                title: "Sleep Quality",
                value: $viewModel.draft.sleepQuality,
                lowLabel: "Poor",
                highLabel: "Great"
            )
            .accessibilityIdentifier("dailyCheckIn.sleepQuality")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            sectionLabel("Morning")
            CompactRatingSelector(
                title: "How's your morning?",
                value: $viewModel.draft.morningRating,
                lowLabel: "Rough",
                highLabel: "Great"
            )
            .accessibilityIdentifier("dailyCheckIn.morning")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var mentalStateSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            sectionLabel("Mental State")
            CompactRatingSelector(
                title: "Stress",
                value: $viewModel.draft.stressLevel,
                lowLabel: "Very Stressed",
                highLabel: "Calm"
            )
            .accessibilityIdentifier("dailyCheckIn.stress")
            CompactRatingSelector(
                title: "Energy",
                value: $viewModel.draft.energyLevel,
                lowLabel: "Low",
                highLabel: "High"
            )
            .accessibilityIdentifier("dailyCheckIn.energy")
            CompactRatingSelector(
                title: "Focus",
                value: $viewModel.draft.focusLevel,
                lowLabel: "Scattered",
                highLabel: "Sharp"
            )
            .accessibilityIdentifier("dailyCheckIn.focus")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            sectionLabel("Notes")
            Text("Anything affecting your trading today?")
                .experienceStyle(.footnote, color: colors.secondaryText)
            TextEditor(text: $viewModel.draft.notes)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(ExperienceSpacing.sm)
                .background(colors.fillSecondary, in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
                .accessibilityIdentifier("dailyCheckIn.notes")
        }
        .padding(ExperienceSpacing.md)
        .background(colors.surfacePrimary, in: RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExperienceRadius.card, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .experienceStyle(.headline, color: colors.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var sleepHoursBinding: Binding<String> {
        Binding(
            get: { viewModel.sleepHoursText },
            set: { viewModel.sleepHoursText = $0 }
        )
    }
}
