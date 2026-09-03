import SwiftUI
import UniformTypeIdentifiers

/// Create → Import CSV — file pick → parse → map (if needed) → preview → import.
struct CSVImportView: View {
    @State private var viewModel: CSVImportViewModel
    @State private var showsFileImporter = false
    @Environment(\.themeColors) private var colors

    private let embeddedInTradeEntryHub: Bool

    init(
        data: DataEnvironment,
        embeddedInTradeEntryHub: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.embeddedInTradeEntryHub = embeddedInTradeEntryHub
        _viewModel = State(
            initialValue: CSVImportViewModel(
                trades: data.trades,
                session: data.session,
                detailCache: data.detailCache,
                onDismiss: onDismiss
            )
        )
    }

    init(viewModel: CSVImportViewModel, embeddedInTradeEntryHub: Bool = false) {
        self.embeddedInTradeEntryHub = embeddedInTradeEntryHub
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .chooseFile:
                chooseFile
            case .parsing, .importing:
                ProgressView(viewModel.phase == .parsing ? "Reading CSV…" : "Importing trades…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .mapping:
                CSVImportMappingView(viewModel: viewModel)
            case .preview:
                CSVImportPreviewView(viewModel: viewModel)
            case .result(let result):
                CSVImportResultView(
                    result: result,
                    onDone: viewModel.dismiss,
                    onAgain: viewModel.resetToChooser
                )
            case .failed(let message):
                ExperienceErrorState(
                    title: "Couldn't import CSV",
                    message: message,
                    onRetry: viewModel.resetToChooser
                )
            }
        }
        .experienceScreenBackground()
        .modifier(CSVImportChromeModifier(
            embeddedInTradeEntryHub: embeddedInTradeEntryHub,
            onClose: { viewModel.dismiss() }
        ))
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: viewModel.acceptedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.ingestPickedFile(url: url)
                }
            case .failure(let error):
                viewModel.fail(UserFacingError.message(for: error))
            }
        }
        .task { viewModel.loadAccountsIfNeeded() }
        .accessibilityIdentifier("csvImport.root")
    }

    private var chooseFile: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(colors.accent)
            Text("Import broker CSV trades")
                .experienceStyle(.title, color: colors.primaryText)
                .multilineTextAlignment(.center)
            Text("Choose a Tradovate, TradeZella, NinjaTrader-style, or generic CSV. TradeTraxs detects the format and fills in as much as possible.")
                .experienceStyle(.body, color: colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ExperienceSpacing.lg)

            ExperienceButton(
                title: "Choose CSV File",
                kind: .primary,
                accessibilityIdentifier: "csvImport.chooseFile"
            ) {
                showsFileImporter = true
            }
            .padding(.horizontal, ExperienceSpacing.lg)

            Spacer()
        }
    }
}

private struct CSVImportChromeModifier: ViewModifier {
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
