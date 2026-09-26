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
                guard let url = urls.first else {
                    viewModel.fail("Unable to read this CSV file.")
                    return
                }
                let read = CSVPickedFileReader.read(url)
                switch read {
                case .success(let file):
                    viewModel.ingestPickedFile(data: file.data, fileName: file.name)
                case .failure:
                    viewModel.fail("Unable to read this CSV file.")
                }
            case .failure:
                viewModel.fail("Unable to read this CSV file.")
            }
        }
        .task { viewModel.loadAccountsIfNeeded() }
        .accessibilityIdentifier("csvImport.root")
    }

    private var chooseFile: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text("Import Trades")
                        .experienceStyle(.headline, color: colors.primaryText)

                    Text("Import trades from a supported CSV file.")
                        .experienceStyle(.footnote, color: colors.secondaryText)

                    Text("Supported CSV exports:")
                        .font(ExperienceTypography.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText)

                    Text(
                        "Supports CSV exports from Tradovate and TradeZella, plus NinjaTrader-style and generic CSV formats."
                    )
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        ExperienceHaptics.play(.selection)
                        showsFileImporter = true
                    } label: {
                        SettingsNavigationRow(
                            title: "Choose CSV File",
                            systemImage: "doc.text"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, ExperienceSpacing.xs)
                    .accessibilityIdentifier("csvImport.chooseFile")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ExperienceSpacing.xxs)
            }
        }
        .listSectionSpacing(ExperienceSpacing.xs)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .experienceDashboardGroupedRows()
    }
}

/// Reads a document-picker URL while its security scope is still valid.
/// The bytes are copied before the importer callback returns.
nonisolated enum CSVPickedFileReader {
    struct File: Sendable {
        var name: String
        var data: Data
    }

    static func read(_ url: URL) -> Result<File, Error> {
        print("[CSV] picker returned")
        let scoped = url.startAccessingSecurityScopedResource()
        print("[CSV] access acquired")
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            print("[CSV] bytes read")
            let name = url.lastPathComponent
            return .success(File(name: name.isEmpty ? "import.csv" : name, data: data))
        } catch {
            return .failure(error)
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
                .experienceNavigationTitle("Import CSV")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
        }
    }
}
