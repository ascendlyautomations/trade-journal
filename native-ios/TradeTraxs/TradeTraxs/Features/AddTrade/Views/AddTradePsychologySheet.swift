import SwiftUI

/// Focused trade psychology editor — opened from Add Trade Trade Review.
struct AddTradePsychologySheet: View {
    @Bindable var viewModel: AddTradeViewModel
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    convictionSelector
                } header: {
                    Text("Conviction")
                } footer: {
                    Text("How strongly you believed in the setup before entry.")
                        .experienceStyle(.caption, color: colors.tertiaryText)
                }

                Section("Before the trade") {
                    Picker("Emotion before trade", selection: $viewModel.emotionSelection) {
                        Text("Not set").tag("")
                        ForEach(TradeReviewCatalog.emotions, id: \.self) { emotion in
                            Text(emotion).tag(emotion)
                        }
                    }
                    .accessibilityIdentifier("addTrade.psychology.emotion")
                }

                Section("Execution") {
                    Toggle("Followed plan", isOn: $viewModel.followedPlan)
                        .accessibilityIdentifier("addTrade.psychology.followedPlan")
                }

                Section("Market") {
                    Picker("Market condition", selection: $viewModel.marketConditionSelection) {
                        Text("Not set").tag("")
                        ForEach(TradeReviewCatalog.marketConditions, id: \.self) { condition in
                            Text(condition).tag(condition)
                        }
                    }
                    .accessibilityIdentifier("addTrade.psychology.marketCondition")
                }

                Section("Psychology notes") {
                    psychologyNotesEditor
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.groupedBackground.ignoresSafeArea())
            .experienceNavigationTitle("Trade Psychology")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("addTrade.psychology.done")
                }
            }
        }
        .accessibilityIdentifier("addTrade.psychologySheet")
    }

    private var convictionSelector: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    if viewModel.confidenceLevel == level {
                        viewModel.confidenceLevel = 0
                    } else {
                        viewModel.confidenceLevel = level
                    }
                } label: {
                    Text("\(level)")
                        .font(ExperienceTypography.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .fill(
                                    viewModel.confidenceLevel == level
                                        ? colors.accent.opacity(0.18)
                                        : colors.fillSecondary
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                                .strokeBorder(
                                    viewModel.confidenceLevel == level
                                        ? colors.accent
                                        : colors.separator,
                                    lineWidth: viewModel.confidenceLevel == level ? 1.5 : 1
                                )
                        )
                        .foregroundStyle(
                            viewModel.confidenceLevel == level
                                ? colors.accent
                                : colors.primaryText
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Conviction \(level) of 5")
                .accessibilityAddTraits(viewModel.confidenceLevel == level ? .isSelected : [])
                .accessibilityIdentifier("addTrade.psychology.conviction.\(level)")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var psychologyNotesEditor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.psychologyNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Thought process before, during, and after…")
                    .experienceStyle(.body, color: colors.tertiaryText)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $viewModel.psychologyNotesText)
                .font(ExperienceTypography.body)
                .foregroundStyle(colors.primaryText)
                .frame(minHeight: 96, alignment: .top)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityIdentifier("addTrade.psychology.notes")
        }
    }
}
