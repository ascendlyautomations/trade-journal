import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

@Observable
@MainActor
final class CSVImportViewModel {
    enum Phase: Equatable {
        case chooseFile
        case parsing
        case mapping
        case preview
        case importing
        case result(CSVImportResult)
        case failed(String)
    }

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let onDismiss: () -> Void

    private(set) var phase: Phase = .chooseFile
    private(set) var accounts: [TradingAccount] = []
    private(set) var selectedAccountID: TradingAccountID?
    private(set) var summary: CSVParseSummary?
    private(set) var columnMappings: [CSVColumnMapping] = []
    private(set) var isImporting = false
    private(set) var reviewTradeID: String?

    private var rawCSVText: String?
    private var sourceFileName: String = "import.csv"
    private var parseTask: Task<Void, Never>?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        onDismiss: @escaping () -> Void
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.onDismiss = onDismiss
    }

    var eligibleAccounts: [TradingAccount] {
        accounts.filter { $0.isActive && $0.canAddTrades }
    }

    var selectedAccount: TradingAccount? {
        eligibleAccounts.first { $0.id == selectedAccountID } ?? eligibleAccounts.first
    }

    var importableTrades: [CSVParsedTrade] {
        summary?.trades.filter(\.isImportable) ?? []
    }

    var canImport: Bool {
        selectedAccount != nil
            && !importableTrades.isEmpty
            && !isImporting
            && (phase == .preview)
    }

    var acceptedContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    func loadAccountsIfNeeded() {
        Task { await loadAccounts() }
    }

    func dismiss() {
        onDismiss()
    }

    func openManageAccounts() {
        // Profile Settings stack — preserve import cover until user returns via Create.
        NavigationCoordinatorProxy.openManageAccounts?()
    }

    func selectAccount(_ id: TradingAccountID) {
        selectedAccountID = id
        ExperienceHaptics.play(.selection)
    }

    func ingestPickedFile(url: URL) {
        parseTask?.cancel()
        phase = .parsing
        parseTask = Task {
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                guard data.count <= 10 * 1_024 * 1_024 else {
                    phase = .failed("CSV must be 10 MB or smaller.")
                    return
                }
                guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                else {
                    phase = .failed("Couldn't read this CSV file.")
                    return
                }
                rawCSVText = text
                sourceFileName = url.lastPathComponent
                #if DEBUG
                AppLog.networking.info(
                    "CSV import picked file=\(url.lastPathComponent, privacy: .public) bytes=\(data.count, privacy: .public)"
                )
                #endif
                await parseCurrentText(mappings: nil)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    #if DEBUG
    func ingestFixtureText(_ text: String, fileName: String = "fixture.csv") {
        rawCSVText = text
        sourceFileName = fileName
        phase = .parsing
        Task { await parseCurrentText(mappings: nil) }
    }
    #endif

    func applyMappingsAndContinue() {
        guard columnMappings.contains(where: { $0.field != nil }) else { return }
        phase = .parsing
        Task { await parseCurrentText(mappings: columnMappings) }
    }

    func updateMapping(header: String, field: CSVLogicalField?) {
        guard let index = columnMappings.firstIndex(where: { $0.header == header }) else { return }
        // Keep unique field assignments.
        if let field {
            for i in columnMappings.indices where columnMappings[i].field == field {
                columnMappings[i].field = nil
            }
        }
        columnMappings[index].field = field
    }

    func updateTrade(_ trade: CSVParsedTrade) {
        guard var summary else { return }
        if let index = summary.trades.firstIndex(where: { $0.id == trade.id }) {
            var updated = trade
            if updated.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.status = .invalid
            } else if !updated.warningMessages.isEmpty {
                updated.status = .needsReview
            } else {
                updated.status = .ready
            }
            summary.trades[index] = updated
            self.summary = summary
        }
        reviewTradeID = nil
    }

    func beginReview(_ trade: CSVParsedTrade) {
        reviewTradeID = trade.id
    }

    func cancelReview() {
        reviewTradeID = nil
    }

    func importTrades() {
        guard canImport, let account = selectedAccount else { return }
        isImporting = true
        phase = .importing
        let tradesToImport = importableTrades
        Task {
            do {
                let drafts = tradesToImport.map { Self.draft(from: $0, account: account) }
                let count = try await trades.importCSVTrades(drafts, isInitialImport: true)
                detailCache.invalidateJournalLists()
                TradeJournalMutationStore.shared.noteBulkImport()
                let result = CSVImportResult(
                    importedCount: count,
                    netPnL: tradesToImport.reduce(0) { $0 + $1.realizedPnL },
                    skippedInvalidCount: (summary?.failedCount ?? 0)
                        + (summary?.trades.filter { $0.status == .invalid }.count ?? 0),
                    failureMessage: nil
                )
                ExperienceHaptics.play(.success)
                phase = .result(result)
            } catch {
                ExperienceHaptics.play(.warning)
                phase = .failed(error.localizedDescription)
            }
            isImporting = false
        }
    }

    func resetToChooser() {
        phase = .chooseFile
        summary = nil
        rawCSVText = nil
        columnMappings = []
        reviewTradeID = nil
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    #if DEBUG
    /// Screenshot / UI-preview hook — seeds a parsed summary into preview phase.
    func applySummaryForScreenshot(_ summary: CSVParseSummary) {
        self.summary = summary
        if accounts.isEmpty {
            let owner = ProfileID("dev.csv.screenshots")
            accounts = PropFirmFixtures.accounts(owner: owner)
        }
        if selectedAccountID == nil {
            selectedAccountID = eligibleAccounts.first?.id
        }
        phase = .preview
    }

    /// Screenshot / UI-preview hook — seeds column mappings into mapping phase.
    func applyMappingsForScreenshot(_ mappings: [CSVColumnMapping]) {
        columnMappings = mappings
        phase = .mapping
    }
    #endif

    // MARK: - Private

    private func loadAccounts() async {
        guard let userID = await session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        if profileID.rawValue.hasPrefix("dev.") {
            accounts = PropFirmFixtures.accounts(owner: profileID)
            SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: detailCache)
        } else {
            do {
                accounts = try await SessionAccountsStore.shared.accounts(
                    for: profileID,
                    detailCache: detailCache,
                    repository: trades
                )
            } catch {
                accounts = SessionAccountsStore.shared.cached(for: profileID)
                    ?? detailCache.accounts(for: profileID)
                    ?? []
            }
        }
        if selectedAccountID == nil {
            selectedAccountID = eligibleAccounts.first?.id
        }
        preselectAccountFromCSVIfPossible()
    }

    private func parseCurrentText(mappings: [CSVColumnMapping]?) async {
        guard let text = rawCSVText else {
            phase = .failed("No CSV loaded.")
            return
        }
        let fileName = sourceFileName
        let built: Result<CSVParseSummary, Error> = await Task.detached(priority: .userInitiated) {
            Result { try CSVTradeBuilder.build(fileName: fileName, text: text, mappings: mappings) }
        }.value

        switch built {
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        case .success(let summary):
            self.summary = summary
            #if DEBUG
            AppLog.networking.info(
                "CSV import parsed format=\(summary.format.rawValue, privacy: .public) rows=\(summary.totalRows, privacy: .public) ok=\(summary.successCount, privacy: .public) fail=\(summary.failedCount, privacy: .public)"
            )
            #endif
            if mappings == nil, CSVTradeBuilder.needsManualMapping(summary: summary) {
                columnMappings = CSVHeaderAliases.suggestedMappings(for: summary.headers)
                phase = .mapping
            } else if summary.successCount == 0 {
                if mappings == nil {
                    columnMappings = CSVHeaderAliases.suggestedMappings(for: summary.headers)
                    phase = .mapping
                } else {
                    phase = .failed("No importable trades found. Check column mapping and try again.")
                }
            } else {
                preselectAccountFromCSVIfPossible()
                phase = .preview
            }
        }
    }

    private func preselectAccountFromCSVIfPossible() {
        guard let name = summary?.trades.compactMap(\.csvAccountName).first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return }
        if let match = eligibleAccounts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            selectedAccountID = match.id
        }
    }

    static func draft(from trade: CSVParsedTrade, account: TradingAccount) -> TradeDraft {
        let sizeLabel = account.size.map { NSDecimalNumber(decimal: $0.amount).stringValue }
        let modeLabel: String = {
            switch account.category {
            case .propFirm:
                return account.mode == .funded ? "Funded" : "Eval"
            case .backtest:
                return "backtest"
            case .personal, .broker:
                return account.mode == .sim ? "Sim" : "Live"
            }
        }()
        let categoryLabel: String = {
            switch account.category {
            case .personal: return "Personal"
            case .broker: return "Broker"
            case .propFirm: return "Prop Firm"
            case .backtest: return "Backtest"
            }
        }()
        return TradeDraft(
            accountID: account.id,
            accountName: account.name,
            accountSizeLabel: sizeLabel,
            accountModeLabel: modeLabel,
            accountCategoryLabel: categoryLabel,
            symbol: Symbol(ticker: trade.symbol),
            side: trade.side,
            mode: account.mode == .sim ? .sim : .live,
            quantity: trade.quantity,
            entryPrice: trade.entryPrice,
            exitPrice: trade.exitPrice,
            entryAt: trade.entryAt,
            exitAt: trade.exitAt,
            realizedPnL: Money(amount: trade.realizedPnL),
            riskReward: trade.riskReward,
            points: trade.points,
            sessionLabel: trade.sessionLabel,
            strategy: trade.strategy,
            visibility: .private,
            publicCaption: nil,
            noteBody: trade.notes.isEmpty ? nil : trade.notes,
            imageURL: nil
        )
    }
}

/// Soft bridge so CSV import can open Manage Accounts without coupling to AppRoot.
enum NavigationCoordinatorProxy {
    @MainActor static var openManageAccounts: (() -> Void)?
}
