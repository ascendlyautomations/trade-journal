import SwiftUI

struct BrokerImportProgressView: View {
    @Bindable var model: BrokerImportFlowModel
    let data: DataEnvironment
    var onReviewImportedTrades: ([TradeID]) -> Void
    var onEditSingleImportedTrade: (TradeID) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    Color.clear
                case .running(let snap):
                    runningContent(snap)
                case .awaitingTradovateConfirmation(let previews):
                    confirmationContent(previews)
                case .success(let count, let ids):
                    successContent(count: count, tradeIDs: ids)
                case .upToDate:
                    upToDateContent
                case .failed(let message, let canRetry):
                    failedContent(message: message, canRetry: canRetry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.groupedBackground.ignoresSafeArea())
            .experienceNavigationTitle("Importing Trades")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if canDismiss {
                        Button("Close") { model.close(reset: true); onClose() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isBlockingDismiss)
        .accessibilityIdentifier("brokerImport.progress")
    }

    private var isBlockingDismiss: Bool {
        if case .running = model.phase { return true }
        if case .awaitingTradovateConfirmation = model.phase { return false }
        return false
    }

    private var canDismiss: Bool {
        switch model.phase {
        case .running: return false
        default: return true
        }
    }

    @ViewBuilder
    private func runningContent(_ snap: BrokerImportFlowModel.BrokerImportProgressSnapshot) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)
            accountHeader(title: snap.accountTitle, subtitle: snap.accountSubtitle)
            ProgressView(value: snap.progress)
                .progressViewStyle(.linear)
                .tint(colors.accent)
                .padding(.horizontal, ExperienceSpacing.xl)
            Text("\(Int((snap.progress * 100).rounded()))%")
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(colors.primaryText)
            Text(snap.stage.title)
                .experienceStyle(.body, color: colors.secondaryText)
            if let caption = snap.processedCaption {
                Text(caption)
                    .experienceStyle(.footnote, color: colors.tertiaryText)
            }
            Spacer()
        }
        .padding(ExperienceSpacing.md)
        .animation(
            ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
            value: snap.progress
        )
    }

    @ViewBuilder
    private func confirmationContent(_ previews: [TradovateImportPreviewTrade]) -> some View {
        BrokerTradovateImportPreviewView(
            trades: previews,
            isConfirming: model.isPersistingTradovateImport,
            embedInParentNavigation: true,
            onConfirm: { model.confirmTradovateImport() },
            onCancel: { model.cancelTradovateConfirmation(); onClose() }
        )
    }

    private var upToDateContent: some View {
        outcomeScaffold(
            symbol: "checkmark.circle",
            title: "You're up to date",
            message: "No new trades were found for this account.",
            primaryTitle: "Done",
            primaryAction: { model.close(reset: true); onClose() }
        )
    }

    private func successContent(count: Int, tradeIDs: [TradeID]) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(colors.profit)
                .accessibilityHidden(true)
            Text("Import Complete")
                .font(.title2.weight(.bold))
                .foregroundStyle(colors.primaryText)
            Text(count == 1 ? "1 trade imported" : "\(count) trades imported")
                .experienceStyle(.body, color: colors.secondaryText)
            Spacer()
            if count == 1, let id = tradeIDs.first {
                ExperienceButton(title: "Add journal details", kind: .primary) {
                    model.close(reset: true)
                    onEditSingleImportedTrade(id)
                    onClose()
                }
                .padding(.horizontal, ExperienceSpacing.md)
                Button("Done") {
                    model.close(reset: true)
                    onClose()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            } else {
                ExperienceButton(title: "Review Imported Trades", kind: .primary) {
                    model.close(reset: true)
                    onReviewImportedTrades(tradeIDs)
                    onClose()
                }
                .padding(.horizontal, ExperienceSpacing.md)
                Button("Done") {
                    model.close(reset: true)
                    onClose()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
    }

    private func failedContent(message: String, canRetry: Bool) -> some View {
        outcomeScaffold(
            symbol: "exclamationmark.triangle.fill",
            title: "Import Failed",
            message: message,
            primaryTitle: canRetry ? "Retry" : "Close",
            primaryAction: {
                if canRetry {
                    model.retryImport()
                } else {
                    model.close(reset: true)
                    onClose()
                }
            },
            secondaryTitle: canRetry ? "Close" : nil,
            secondaryAction: canRetry ? { model.close(reset: true); onClose() } : nil
        )
    }

    private func outcomeScaffold(
        symbol: String,
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(colors.secondaryText)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(colors.primaryText)
            Text(message)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.md)
            Spacer()
            ExperienceButton(title: primaryTitle, kind: .primary, action: primaryAction)
                .padding(.horizontal, ExperienceSpacing.md)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(ExperienceSpacing.md)
    }

    private func accountHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: ExperienceSpacing.xxs) {
            Text(title)
                .experienceStyle(.headline, color: colors.primaryText)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .experienceStyle(.footnote, color: colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }
}
