import Foundation
import Observation
import OSLog
import UIKit

@Observable
@MainActor
final class ScreenshotImportViewModel {
    enum Phase: Equatable {
        case choosePhotos
        case analyzing
        case needsAIFallback(String)
        case aiAnalyzing
        case preview
        case importing
        case result(CSVImportResult)
        case failed(String)
    }

    private let trades: any TradeRepository
    private let ai: (any AIRepository)?
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let onDismiss: () -> Void

    private(set) var phase: Phase = .choosePhotos
    private(set) var accounts: [TradingAccount] = []
    private(set) var selectedAccountID: TradingAccountID?
    private(set) var summary: CSVParseSummary?
    private(set) var metadataByTradeID: [String: ScreenshotImportTradeMetadata] = [:]
    private(set) var isImporting = false
    private(set) var reviewTradeID: String?
    private(set) var selectedPhotoCount = 0
    private(set) var extractionQuality: ScreenshotExtractionQuality = .confident
    private(set) var isAIAssisted = false
    private(set) var aiErrorMessage: String?

    private var analyzeTask: Task<Void, Never>?
    /// Temporary in-memory images — discarded on reset/dismiss/import.
    private var loadedImages: [UIImage] = []
    private var lastBlocksByImage: [[OCRTextBlock]] = []
    private var lastDeterministicResult: ScreenshotImportProcessResult?
    private var aiSessionCache: [String: ScreenshotAIExtractionV1] = [:]
    private var lastRequestFingerprint: String?

    init(
        trades: any TradeRepository,
        ai: (any AIRepository)? = nil,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        onDismiss: @escaping () -> Void
    ) {
        self.trades = trades
        self.ai = ai
        self.session = session
        self.detailCache = detailCache
        self.onDismiss = onDismiss
    }

    var eligibleAccounts: [TradingAccount] {
        let base = TradingAccountDropdownFilter.selectableForNewTrades(accounts)
        let resolved = OwnerAccountDropdownSupport.resolvedAccounts(
            profileID: ownerProfileID,
            fallback: accounts
        )
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        return base.map { byID[$0.id] ?? $0 }
    }

    var ownerProfileID: ProfileID? {
        accounts.first?.ownerProfileID
    }

    var selectedAccount: TradingAccount? {
        eligibleAccounts.first { $0.id == selectedAccountID } ?? eligibleAccounts.first
    }

    var canAnalyzeWithAI: Bool {
        ai != nil && !loadedImages.isEmpty && phase != .aiAnalyzing
    }

    var importableTrades: [CSVParsedTrade] {
        summary?.trades.filter { trade in
            guard trade.isImportable else { return false }
            return metadataByTradeID[trade.id]?.isSelectedForImport ?? true
        } ?? []
    }

    var canImport: Bool {
        selectedAccount != nil
            && !importableTrades.isEmpty
            && !isImporting
            && phase == .preview
    }

    var previewConfig: TradeImportPreviewConfig {
        TradeImportPreviewConfig(
            sourceTitle: isAIAssisted ? "Screenshot import" : "Screenshot import",
            sourceDetail: previewDetailText,
            sourceSystemImage: "photo.on.rectangle.angled",
            accessibilityPrefix: "screenshotImport"
        )
    }

    private var previewDetailText: String {
        guard let summary else { return "Review detected trades before importing." }
        let dupes = metadataByTradeID.values.filter { $0.duplicateClassification != .newTrade }.count
        var detail = "Found \(summary.successCount) possible trades · \(summary.failedCount) rows skipped"
        if isAIAssisted {
            detail = "AI-assisted extraction — review before importing · \(summary.successCount) trades"
        } else if extractionQuality == .uncertain {
            detail += " · Some fields need review"
        }
        if dupes > 0 {
            detail += " · \(dupes) duplicate warnings"
        }
        return detail
    }

    func loadAccountsIfNeeded() {
        Task { await loadAccounts() }
    }

    func dismiss() {
        clearTemporaryImages()
        onDismiss()
    }

    func openManageAccounts() {
        NavigationCoordinatorProxy.openManageAccounts?()
    }

    func selectAccount(_ id: TradingAccountID) {
        selectedAccountID = id
        ExperienceHaptics.play(.selection)
        Task { await refreshDuplicateClassification() }
    }

    func ingestImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        analyzeTask?.cancel()
        phase = .analyzing
        aiErrorMessage = nil
        isAIAssisted = false
        analyzeTask = Task {
            await analyzeLoadedImages(images)
        }
    }

    func analyzeWithAI() {
        guard canAnalyzeWithAI else { return }
        phase = .aiAnalyzing
        aiErrorMessage = nil
        Task { await runAIExtraction() }
    }

    func reviewPartialDeterministicResults() {
        guard let lastDeterministicResult, lastDeterministicResult.summary.successCount > 0 else { return }
        applyProcessResult(lastDeterministicResult)
        isAIAssisted = false
        phase = .preview
        Task { await refreshDuplicateClassification() }
    }

    func updateTrade(_ trade: CSVParsedTrade) {
        guard var summary else { return }
        if let index = summary.trades.firstIndex(where: { $0.id == trade.id }) {
            var updated = trade
            recomputeDerivedFields(&updated)
            if updated.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.status = .invalid
            } else if !updated.warningMessages.isEmpty {
                updated.status = .needsReview
            } else {
                updated.status = .ready
            }
            summary.trades[index] = updated
            self.summary = summary
            if var metadata = metadataByTradeID[trade.id] {
                metadata.warnings = updated.warningMessages
                metadataByTradeID[trade.id] = metadata
            }
        }
        reviewTradeID = nil
    }

    func toggleImportSelection(for tradeID: String) {
        guard var metadata = metadataByTradeID[tradeID] else { return }
        metadata.isSelectedForImport.toggle()
        metadataByTradeID[tradeID] = metadata
        ExperienceHaptics.play(.selection)
    }

    func metadata(for tradeID: String) -> ScreenshotImportTradeMetadata? {
        metadataByTradeID[tradeID]
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
                let drafts = tradesToImport.map { trade -> TradeDraft in
                    var draft = CSVImportViewModel.draft(from: trade, account: account)
                    draft.importSource = .screenshot
                    draft.importFingerprint = metadataByTradeID[trade.id]?.importFingerprint
                    return draft
                }
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
                clearTemporaryImages()
                ExperienceHaptics.play(.success)
                phase = .result(result)
            } catch {
                ExperienceHaptics.play(.warning)
                phase = .failed(UserFacingError.message(for: error))
            }
            isImporting = false
        }
    }

    func resetToChooser() {
        clearTemporaryImages()
        phase = .choosePhotos
        summary = nil
        metadataByTradeID = [:]
        selectedPhotoCount = 0
        reviewTradeID = nil
        extractionQuality = .confident
        isAIAssisted = false
        aiErrorMessage = nil
        lastBlocksByImage = []
        lastDeterministicResult = nil
        aiSessionCache = [:]
        lastRequestFingerprint = nil
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    #if DEBUG
    func applySummaryForScreenshot(_ summary: CSVParseSummary) {
        self.summary = summary
        if accounts.isEmpty {
            let owner = ProfileID("dev.screenshot.import")
            accounts = PropFirmFixtures.accounts(owner: owner)
        }
        if selectedAccountID == nil {
            selectedAccountID = eligibleAccounts.first?.id
        }
        phase = .preview
    }
    #endif

    /// Test seam — processes fixture OCR blocks without Photos/Vision.
    func ingestBlocksForTesting(_ blocksByImage: [[OCRTextBlock]]) {
        phase = .analyzing
        Task {
            let result = ScreenshotTradeImportPipeline.process(blocksByImage: blocksByImage)
            lastBlocksByImage = blocksByImage
            lastDeterministicResult = result
            applyProcessResult(result)
            extractionQuality = result.extractionQuality
            await loadAccounts()
            await refreshDuplicateClassification()
            transitionAfterDeterministicParse(result, blocksByImage: blocksByImage)
        }
    }

    /// Test seam — inject AI repository responses without network.
    func applyAIExtractionForTesting(_ extraction: ScreenshotAIExtractionV1, imagesProcessed: Int) {
        let result = ScreenshotTradeImportPipeline.processAIExtraction(
            extraction,
            imagesProcessed: imagesProcessed
        )
        isAIAssisted = true
        applyProcessResult(result)
        phase = .preview
    }

    // MARK: - Private

    private func analyzeLoadedImages(_ images: [UIImage]) async {
        do {
            loadedImages = images
            selectedPhotoCount = images.count
            let cgImages = images.compactMap(\.cgImage)
            guard !cgImages.isEmpty else {
                phase = .failed("Couldn't read screenshot images.")
                return
            }

            let blocks = try await Task.detached(priority: .userInitiated) {
                try await ScreenshotTradeOCRService.recognizeText(in: cgImages)
            }.value
            lastBlocksByImage = blocks

            let result = ScreenshotTradeImportPipeline.process(blocksByImage: blocks)
            lastDeterministicResult = result
            extractionQuality = result.extractionQuality

            #if DEBUG
            AppLog.networking.info(
                "Screenshot import parsed images=\(cgImages.count, privacy: .public) trades=\(result.summary.successCount, privacy: .public) quality=\(result.extractionQuality.rawValue, privacy: .public)"
            )
            logDeterministicDiagnostic(result: result, blocks: blocks)
            #endif

            await loadAccounts()
            transitionAfterDeterministicParse(result, blocksByImage: blocks)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func transitionAfterDeterministicParse(
        _ result: ScreenshotImportProcessResult,
        blocksByImage: [[OCRTextBlock]]
    ) {
        switch result.extractionQuality {
        case .confident:
            applyProcessResult(result)
            Task { await refreshDuplicateClassification() }
            phase = .preview
        case .uncertain:
            applyProcessResult(result)
            Task { await refreshDuplicateClassification() }
            phase = .preview
        case .insufficient:
            if ai != nil {
                let reason = ScreenshotImportConfidenceEvaluator.fallbackReason(
                    result: result,
                    blocksByImage: blocksByImage
                )
                phase = .needsAIFallback(reason)
            } else {
                phase = .failed("No recognizable trades found. Try a clearer trade-history screenshot.")
            }
        }
    }

    private func runAIExtraction() async {
        guard let ai else {
            phase = .needsAIFallback("AI analysis is unavailable.")
            return
        }

        let prepared = ScreenshotAIImagePreparer.prepare(loadedImages)
        guard !prepared.isEmpty else {
            aiErrorMessage = "Couldn't prepare screenshots for AI analysis."
            restoreAfterAIFailure()
            return
        }

        let fingerprint = ScreenshotAIRequestFingerprint.make(
            images: prepared,
            ocrBlocks: lastBlocksByImage
        )
        lastRequestFingerprint = fingerprint

        if let cached = aiSessionCache[fingerprint] {
            let result = ScreenshotTradeImportPipeline.processAIExtraction(
                cached,
                imagesProcessed: prepared.count
            )
            isAIAssisted = true
            applyProcessResult(result)
            await refreshDuplicateClassification()
            phase = result.summary.successCount > 0 ? .preview : .needsAIFallback("AI couldn't find trades in this screenshot.")
            return
        }

        let request = ScreenshotAIExtractRequest(
            schemaVersion: "v1",
            requestFingerprint: fingerprint,
            detectedPlatformHint: lastDeterministicResult?.summary.format.rawValue,
            deterministicWarnings: lastDeterministicResult?.summary.failures.map(\.reason) ?? [],
            screenshots: prepared.map { image in
                ScreenshotAIExtractRequest.ScreenshotPayload(
                    index: image.index,
                    mimeType: image.mimeType,
                    base64: image.base64,
                    ocrBlocks: ScreenshotSensitiveOCRRedactor.redactBlocks(
                        lastBlocksByImage.indices.contains(image.index)
                            ? lastBlocksByImage[image.index]
                            : []
                    )
                )
            }
        )

        do {
            let response = try await ai.extractScreenshotTrades(request)
            guard let extraction = response.extraction else {
                aiErrorMessage = response.error ?? "AI couldn't extract trades from this screenshot."
                restoreAfterAIFailure()
                return
            }
            aiSessionCache[fingerprint] = extraction
            let result = ScreenshotTradeImportPipeline.processAIExtraction(
                extraction,
                imagesProcessed: prepared.count
            )
            isAIAssisted = true
            applyProcessResult(result)
            await refreshDuplicateClassification()
            if result.summary.successCount == 0 {
                phase = .needsAIFallback("AI couldn't find trades in this screenshot.")
            } else {
                phase = .preview
            }
        } catch {
            aiErrorMessage = UserFacingError.message(for: error)
            restoreAfterAIFailure()
        }
    }

    private func restoreAfterAIFailure() {
        if let lastDeterministicResult, lastDeterministicResult.summary.successCount > 0 {
            applyProcessResult(lastDeterministicResult)
            extractionQuality = lastDeterministicResult.extractionQuality
            isAIAssisted = false
            phase = .preview
            Task { await refreshDuplicateClassification() }
        } else if ai != nil {
            let reason = lastDeterministicResult.map {
                ScreenshotImportConfidenceEvaluator.fallbackReason(
                    result: $0,
                    blocksByImage: lastBlocksByImage
                )
            } ?? "We couldn't confidently read this trade history."
            phase = .needsAIFallback(reason)
        } else {
            phase = .failed(aiErrorMessage ?? "Screenshot extraction failed.")
        }
    }

    private func applyProcessResult(_ result: ScreenshotImportProcessResult) {
        summary = result.summary
        metadataByTradeID = result.metadataByTradeID
        extractionQuality = result.extractionQuality
        isAIAssisted = result.isAIAssisted
    }

    private func refreshDuplicateClassification() async {
        guard var summary, let profileID = ownerProfileID, let accountID = selectedAccountID else { return }
        let existing: [Trade]
        if profileID.rawValue.hasPrefix("dev.") {
            existing = []
        } else {
            existing = (try? await SessionOwnerTradesStore.shared.trades(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                limit: 500,
                forceNetwork: false
            )) ?? SessionOwnerTradesStore.shared.cached(for: profileID) ?? []
        }

        for index in summary.trades.indices {
            let trade = summary.trades[index]
            guard trade.isImportable else { continue }
            var metadata = metadataByTradeID[trade.id] ?? .empty()
            let fingerprint = metadata.importFingerprint ?? ImportFingerprint.forAggregatedTrade(
                symbol: trade.symbol,
                side: trade.side,
                quantity: trade.quantity,
                entryPrice: trade.entryPrice,
                exitPrice: trade.exitPrice,
                entryAt: trade.entryAt,
                exitAt: trade.exitAt,
                accountID: accountID.rawValue
            )
            metadata.importFingerprint = fingerprint
            let classification = ImportDuplicateDetector.classify(
                candidate: .init(trade: trade, fingerprint: fingerprint, metadata: metadata),
                existingTrades: existing,
                accountID: accountID
            )
            ImportDuplicateDetector.applyClassification(to: &metadata, classification: classification)
            metadataByTradeID[trade.id] = metadata
            var updated = trade
            updated.warningMessages = Array(Set(updated.warningMessages + metadata.warnings))
            if classification == .exactDuplicate {
                updated.status = .needsReview
            }
            if isAIAssisted {
                updated.status = .needsReview
            }
            summary.trades[index] = updated
        }
        self.summary = summary
    }

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
                    repository: trades,
                    requiresFullOwnerSnapshot: true
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
    }

    private func recomputeDerivedFields(_ trade: inout CSVParsedTrade) {
        if let entry = trade.entryPrice, let exit = trade.exitPrice {
            trade.points = trade.side == .short ? entry - exit : exit - entry
        }
        if let exitAt = trade.exitAt {
            trade.durationSeconds = TradeHoldDuration.compute(entryAt: trade.entryAt, exitAt: exitAt)?.seconds
        }
        trade.sessionLabel = TradingSessionLabel.session(from: trade.entryAt)

        var warnings: [String] = []
        if trade.realizedPnL == 0, trade.warningMessages.contains(where: { $0 == "P&L missing" }) {
            warnings.append("P&L missing")
        }
        if trade.entryPrice == nil { warnings.append("Review entry price") }
        if trade.exitPrice == nil { warnings.append("Review exit price") }
        if trade.exitAt == nil { warnings.append("Confirm date") }
        trade.warningMessages = warnings
    }

    private func clearTemporaryImages() {
        loadedImages.removeAll()
        selectedPhotoCount = 0
    }

    #if DEBUG
    private func logDeterministicDiagnostic(
        result: ScreenshotImportProcessResult,
        blocks: [[OCRTextBlock]]
    ) {
        let rows = ScreenshotTradeTableReconstructor.reconstruct(blocksByImage: blocks)
        let platform = ScreenshotTradePlatformRegistry.detectPlatform(in: rows)
        let diagnostic = ScreenshotImportConfidenceEvaluator.diagnostic(
            result: result,
            blocksByImage: blocks,
            platform: platform
        )
        AppLog.networking.debug(
            "Screenshot deterministic diagnostic platform=\(diagnostic.platformDetected, privacy: .public) fills=\(diagnostic.fillsParsed, privacy: .public) failures=\(diagnostic.failureCount, privacy: .public) ocr=\(diagnostic.averageOCRConfidence, privacy: .public) reason=\(diagnostic.fallbackReason, privacy: .public)"
        )
    }
    #endif
}
