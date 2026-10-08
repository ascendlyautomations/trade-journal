import SwiftUI

/// Trade Detail analysis card — results first, custom question + Analyze below.
struct TradeAISectionView: View {
    @Bindable var viewModel: TradeAISectionViewModel

    @Environment(\.themeColors) private var colors
    @State private var entitlementGateRevision = 0

    private var isAnalysisRestricted: Bool {
        _ = entitlementGateRevision
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        return ProMonetizationPolicy.shouldRestrictPremiumPsychologyAndAI(
            demoModeActive: ExploreModeSupport.isActive,
            profileID: profileID
        )
    }

    var body: some View {
        TradeDetailGroupedSurface {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                header

                if isAnalysisRestricted {
                    tradeAIUpgradeBlock
                } else if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Loading previous analyses")
                }

                if !isAnalysisRestricted, !viewModel.messages.isEmpty {
                    messages
                }

                if !isAnalysisRestricted, let error = viewModel.errorMessage {
                    Text(error)
                        .experienceStyle(.caption, color: colors.error)
                }

                if !isAnalysisRestricted, let persistError = viewModel.persistErrorMessage {
                    VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
                        Text(persistError)
                            .experienceStyle(.caption, color: colors.secondaryText)
                        Button("Retry Save") {
                            Task { await viewModel.retryPersistIfNeeded() }
                        }
                        .font(.system(.caption, design: .default).weight(.semibold))
                        .foregroundStyle(colors.accent)
                    }
                }

                if !isAnalysisRestricted {
                    analysisSelectorRow

                    customQuestionSection

                    ComplianceDisclaimerFootnote(
                        text: ComplianceDisclaimerCopy.tradeAI,
                        showsTermsLink: true
                    )
                }
            }
        }
        .accessibilityIdentifier("detail.trade.ai.section")
        .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
            entitlementGateRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .monetizationConfigurationDidChange)) { _ in
            entitlementGateRevision += 1
        }
    }

    private var tradeAIUpgradeBlock: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            Text("Trade AI analysis is included with TraxPro.")
                .experienceStyle(.footnote, color: colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                ExperienceHaptics.play(.selection)
                ProUpgradeCoordinator.shared.present(reason: .feature(.aiAnalyst))
            } label: {
                Text("Upgrade to TraxPro")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("detail.trade.ai.upgrade.traxpro")
        }
        .accessibilityIdentifier("detail.trade.ai.traxpro.gate")
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
