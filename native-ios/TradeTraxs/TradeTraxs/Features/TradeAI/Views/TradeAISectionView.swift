import SwiftUI

/// Trade Detail analysis card — native analysis Menu, Analyze action, custom question field.
struct TradeAISectionView: View {
    @Bindable var viewModel: TradeAISectionViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            header

            Text("What would you like to analyze?")
                .experienceStyle(.caption, color: colors.secondaryText)

            analysisSelectorRow

            Button {
                Task { await viewModel.analyzeSelected() }
            } label: {
                Text(viewModel.isAnalyzing ? "Analyzing…" : "Analyze")
                    .experienceStyle(.headline, color: colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ExperienceSpacing.sm)
                    .background(
                        canAnalyze ? colors.accent : colors.tertiaryText,
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze)
            .accessibilityIdentifier("detail.trade.ai.analyze")

            if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Loading previous analyses")
            }

            if !viewModel.messages.isEmpty {
                messages
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .experienceStyle(.caption, color: colors.error)
            }

            customQuestionField
        }
        .padding(ExperienceSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.fillPrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
        )
        .accessibilityIdentifier("detail.trade.ai.section")
    }

    private var header: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("Trade AI")
                .experienceStyle(.headline, color: colors.primaryText)
            Spacer(minLength: 0)
            if viewModel.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Analyzing trade")
            }
        }
    }

    /// Settings-style row backed by a native `Menu` (no horizontal chip scrolling).
    private var analysisSelectorRow: some View {
        Menu {
            ForEach(viewModel.analysisOptions) { option in
                Button {
                    ExperienceHaptics.play(.selection)
                    viewModel.selectedPrompt = option
                } label: {
                    if option.id == viewModel.selectedPrompt.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: ExperienceSpacing.sm) {
                Text(viewModel.selectedPrompt.title)
                    .experienceStyle(.body, color: colors.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, ExperienceSpacing.sm)
            .background(
                colors.fillSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            )
        }
        .disabled(viewModel.isAnalyzing)
        .accessibilityIdentifier("detail.trade.ai.selector")
        .accessibilityLabel("Analysis type")
        .accessibilityValue(viewModel.selectedPrompt.title)
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            ForEach(viewModel.messages) { message in
                TradeAIMessageCard(message: message)
            }
        }
        .padding(.top, ExperienceSpacing.xs)
    }

    private var customQuestionField: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Ask anything about this trade…")
                .experienceStyle(.caption, color: colors.secondaryText)

            HStack(alignment: .bottom, spacing: ExperienceSpacing.sm) {
                TextField(
                    "Custom question",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .foregroundStyle(colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.sm)
                .padding(.vertical, ExperienceSpacing.xs)
                .background(
                    colors.fillSecondary,
                    in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                )
                .disabled(viewModel.isAnalyzing)
                .accessibilityIdentifier("detail.trade.ai.input")

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            canSendCustom ? colors.accent : colors.tertiaryText
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendCustom)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("detail.trade.ai.send")
            }
        }
    }

    private var canAnalyze: Bool {
        !viewModel.isAnalyzing
    }

    private var canSendCustom: Bool {
        !viewModel.isAnalyzing
            && !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
