import PhotosUI
import SwiftUI

/// Create → Import Screenshot — on-device Vision OCR → review → bulk import.
struct ScreenshotImportView: View {
    @State private var viewModel: ScreenshotImportViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @Environment(\.themeColors) private var colors

    private let embeddedInTradeEntryHub: Bool

    init(
        data: DataEnvironment,
        embeddedInTradeEntryHub: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.embeddedInTradeEntryHub = embeddedInTradeEntryHub
        _viewModel = State(
            initialValue: ScreenshotImportViewModel(
                trades: data.trades,
                ai: data.ai,
                session: data.session,
                detailCache: data.detailCache,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: ScreenshotImportViewModel, embeddedInTradeEntryHub: Bool = false) {
        self.embeddedInTradeEntryHub = embeddedInTradeEntryHub
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Group {
            switch viewModel.phase {
            case .choosePhotos:
                choosePhotos(viewModel: viewModel)
            case .analyzing, .importing, .aiAnalyzing:
                ProgressView(progressTitle(for: viewModel.phase))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsAIFallback(let reason):
                aiFallbackPrompt(reason: reason, viewModel: viewModel)
            case .preview:
                preview(viewModel: viewModel)
            case .result(let result):
                CSVImportResultView(
                    result: result,
                    onDone: { viewModel.dismiss() },
                    onAgain: { viewModel.resetToChooser() }
                )
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't import screenshots",
                    message: message,
                    onRetry: { viewModel.resetToChooser() }
                )
            }
        }
        .experienceScreenBackground()
        .modifier(ScreenshotImportChromeModifier(
            embeddedInTradeEntryHub: embeddedInTradeEntryHub,
            onClose: { viewModel.dismiss() }
        ))
        .task { viewModel.loadAccountsIfNeeded() }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .choosePhotos {
                pickerItems = []
            }
        }
        .accessibilityIdentifier("screenshotImport.root")
    }

    private func progressTitle(for phase: ScreenshotImportViewModel.Phase) -> String {
        switch phase {
        case .aiAnalyzing:
            return "Analyzing with AI…"
        case .importing:
            return "Importing trades…"
        default:
            return "Analyzing screenshots…"
        }
    }

    private func choosePhotos(viewModel: ScreenshotImportViewModel) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("Import trades from screenshots")
                .experienceStyle(.title, color: colors.primaryText)
                .multilineTextAlignment(.center)
            Text("Select one or more trade-history screenshots. TradeTraxs reads them on your device, then you review before importing.")
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 12,
                matching: .screenshots
            ) {
                Text("Choose Screenshots")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, ExperienceSpacing.lg)
            .accessibilityIdentifier("screenshotImport.choosePhotos")
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { await loadPickerImages(newItems, viewModel: viewModel) }
            }

            Spacer()
        }
    }

    private func aiFallbackPrompt(
        reason: String,
        viewModel: ScreenshotImportViewModel
    ) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("We couldn't confidently read this trade history")
                .experienceStyle(.title, color: colors.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)
            Text(reason)
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)

            if let aiError = viewModel.aiErrorMessage {
                Text(aiError)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ExperienceSpacing.lg)
            }

            if viewModel.canAnalyzeWithAI {
                ExperienceButton(
                    title: "Analyze with AI",
                    kind: .primary,
                    accessibilityIdentifier: "screenshotImport.analyzeWithAI"
                ) {
                    viewModel.analyzeWithAI()
                }
                .padding(.horizontal, ExperienceSpacing.lg)

                ComplianceDisclaimerFootnote(text: ComplianceDisclaimerCopy.screenshotAI)
                    .padding(.horizontal, ExperienceSpacing.lg)
            }

            if viewModel.summary?.successCount ?? 0 > 0 {
                Button {
                    viewModel.reviewPartialDeterministicResults()
                } label: {
                    Text("Review partial results")
                        .experienceStyle(.body, color: colors.accent)
                }
            }

            Button {
                viewModel.resetToChooser()
            } label: {
                Text("Choose different screenshots")
                    .experienceStyle(.body, color: colors.secondaryText)
            }

            Spacer()
        }
        .accessibilityIdentifier("screenshotImport.aiFallback")
    }

    private func loadPickerImages(
        _ items: [PhotosPickerItem],
        viewModel: ScreenshotImportViewModel
    ) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data)
            {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            viewModel.fail("Couldn't load selected screenshots.")
            return
        }
        viewModel.ingestImages(images)
    }

    @ViewBuilder
    private func preview(viewModel: ScreenshotImportViewModel) -> some View {
        if let summary = viewModel.summary {
            VStack(spacing: 0) {
                if viewModel.isAIAssisted {
                    aiAssistedBanner
                } else if viewModel.extractionQuality == .uncertain, viewModel.canAnalyzeWithAI {
                    uncertainBanner(viewModel: viewModel)
                }
                TradeImportPreviewContent(
                    config: viewModel.previewConfig,
                    summary: summary,
                    eligibleAccounts: viewModel.eligibleAccounts,
                    selectedAccountID: Binding(
                        get: { viewModel.selectedAccountID },
                        set: { newValue in
                            if let id = newValue {
                                viewModel.selectAccount(id)
                            }
                        }
                    ),
                    ownerProfileID: viewModel.ownerProfileID,
                    importableTrades: viewModel.importableTrades,
                    canImport: viewModel.canImport,
                    isImporting: viewModel.isImporting,
                    reviewTradeID: viewModel.reviewTradeID,
                    onManageAccounts: { viewModel.openManageAccounts() },
                    onSelectAccount: { viewModel.selectAccount($0) },
                    onBeginReview: { viewModel.beginReview($0) },
                    onCancelReview: { viewModel.cancelReview() },
                    onUpdateTrade: { viewModel.updateTrade($0) },
                    onImport: { viewModel.importTrades() },
                    screenshotMetadataByTradeID: viewModel.metadataByTradeID,
                    onToggleImportSelection: { viewModel.toggleImportSelection(for: $0) }
                )
            }
        }
    }

    private var aiAssistedBanner: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xs) {
            HStack(spacing: ExperienceSpacing.sm) {
                Image(systemName: "sparkles")
                Text("AI-assisted extraction — review before importing")
                    .experienceStyle(.footnote, color: colors.primaryText)
                Spacer()
            }
            ComplianceDisclaimerFootnote(text: ComplianceDisclaimerCopy.screenshotAI)
        }
        .padding(ExperienceSpacing.md)
        .background(colors.backgroundSecondary.opacity(0.95))
        .accessibilityIdentifier("screenshotImport.aiAssistedBanner")
    }

    private func uncertainBanner(viewModel: ScreenshotImportViewModel) -> some View {
        HStack(spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Some fields need review")
                    .experienceStyle(.footnote, color: colors.primaryText)
                Text("Analyze with AI may improve unclear layouts.")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Spacer()
            Button("Analyze with AI") {
                viewModel.analyzeWithAI()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(ExperienceSpacing.md)
        .background(colors.backgroundSecondary.opacity(0.95))
        .accessibilityIdentifier("screenshotImport.uncertainBanner")
    }
}

private struct ScreenshotImportChromeModifier: ViewModifier {
    let embeddedInTradeEntryHub: Bool
    let onClose: () -> Void

    func body(content: Content) -> some View {
        if embeddedInTradeEntryHub {
            content
        } else {
            content
                .experienceNavigationTitle("Import Trades")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
        }
    }
}
