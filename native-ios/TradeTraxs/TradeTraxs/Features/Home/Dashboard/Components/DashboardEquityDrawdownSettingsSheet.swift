import SwiftUI

struct DashboardEquityDrawdownSettingsSheet: View {
    let accountName: String
    @Binding var limitDigits: String
    @Binding var limitType: LivePersonalDrawdownType
    var isSaving: Bool
    var errorMessage: String?
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(\.themeColors) private var colors
    @FocusState private var limitFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text("Drawdown floor")
                            .experienceStyle(.headline, color: colors.primaryText)
                        Text(accountName)
                            .experienceStyle(.subheadline, color: colors.secondaryText)
                        Text(
                            "Personal drawdown for this Live account (informational floor on the equity curve). Leave blank to clear."
                        )
                        .experienceStyle(.footnote, color: colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: ExperienceSpacing.sm) {
                        ForEach(LivePersonalDrawdownType.allCases, id: \.self) { type in
                            Button {
                                limitType = type
                            } label: {
                                Text(type.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, ExperienceSpacing.sm)
                                    .background(
                                        limitType == type
                                            ? colors.accent.opacity(0.22)
                                            : colors.fillSecondary.opacity(0.35),
                                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                            .stroke(
                                                limitType == type ? colors.accent.opacity(0.55) : colors.border.opacity(0.35),
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .buttonStyle(.experiencePlain)
                            .disabled(isSaving)
                        }
                    }

                    VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                        Text("Max drawdown limit")
                            .experienceStyle(.caption, color: colors.secondaryText)
                        TextField("$0", text: $limitDigits)
                            .keyboardType(.decimalPad)
                            .focused($limitFocused)
                            .padding(ExperienceSpacing.sm)
                            .background(colors.fillSecondary.opacity(0.35), in: RoundedRectangle(cornerRadius: ExperienceRadius.sm))
                            .disabled(isSaving)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .experienceStyle(.footnote, color: colors.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(ExperienceSpacing.md)
            }
            .background(colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Equity curve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: onSave)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("dashboard.equityDrawdownSettings")
    }
}
