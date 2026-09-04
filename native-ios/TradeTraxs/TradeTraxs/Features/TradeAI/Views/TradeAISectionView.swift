import SwiftUI

/// Trade Detail analysis card — results first, custom question + Analyze below.
struct TradeAISectionView: View {
    @Bindable var viewModel: TradeAISectionViewModel

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            header

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

            analysisSelectorRow

            customQuestionSection

            ComplianceDisclaimerFootnote(
                text: ComplianceDisclaimerCopy.tradeAI,
                showsTermsLink: true
            )
        }
        .padding(ExperienceSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            colors.fillPrimary,
            in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
        )
        .accessibilityIdentifier("detail.trade.ai.section")
    }

    private var header: some View {
        HStack(spacing: ExperienceSpacing.xs) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("Trade AI")
                .experienceStyle(.subheadline, color: colors.primaryText)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
            if viewModel.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Analyzing trade")
            }
        }
    }

    /// Preset analysis type — shown when no results yet; still used when custom question is blank.
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
            HStack(spacing: ExperienceSpacing.xs) {
                Text(viewModel.selectedPrompt.title)
                    .experienceStyle(.caption, color: colors.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
            }
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, 8)
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
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ForEach(viewModel.messages) { message in
                TradeAIMessageCard(message: message)
            }
        }
    }

    private var customQuestionSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            Text("Custom Question")
                .experienceStyle(.caption2, color: colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.35)

            TextField(
                "Ask anything about this trade…",
                text: $viewModel.draft,
                axis: .vertical
            )
            .lineLimit(1 ... 3)
            .textFieldStyle(.plain)
            .foregroundStyle(colors.primaryText)
            .padding(.horizontal, ExperienceSpacing.sm)
            .padding(.vertical, 8)
            .background(
                colors.fillSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
            )
            .disabled(viewModel.isAnalyzing)
            .accessibilityIdentifier("detail.trade.ai.input")

            Button {
                Task { await viewModel.analyzeTapped() }
            } label: {
                Text(viewModel.isAnalyzing ? "Analyzing…" : "Analyze Trade")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundStyle(canAnalyze ? colors.onAccent : colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        canAnalyze ? colors.accent : colors.tertiaryText.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze)
            .accessibilityIdentifier("detail.trade.ai.analyze")
        }
    }

    private var canAnalyze: Bool {
        !viewModel.isAnalyzing
    }
}
