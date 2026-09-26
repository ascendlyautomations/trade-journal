import Foundation
import Observation
import PhotosUI
import SwiftUI
import UIKit

@Observable
@MainActor
final class CreateReelViewModel {
    enum Phase: Equatable {
        case idle
        case ready
        case importingVideo
        case preparingVideo
        case publishing
        case failed(String)
    }

    enum BackgroundPreparationState: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var backgroundPreparationState: BackgroundPreparationState = .idle
    private(set) var isFullVideoImportInProgress = false
    var formError: String?
    private(set) var uploadProgress: Double = 0
    private(set) var pickerTrades: [Trade] = []
    private(set) var isLoadingTrades = false

    var draft: ReelDraft?
    var captionText = ""

    private let feed: any FeedRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var videoPipelineTask: Task<Void, Never>?
    private var backgroundPrepObservationTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var didHandOffBackgroundPublish = false
    private var hasPrepared = false
    private var hasLoadedTrades = false

    private var selectionGeneration: UInt64 = 0
    private var currentSelectionID: String?
    private var lastImportedItemIdentifier: String?

    init(
        feed: any FeedRepository,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onDismiss: @escaping () -> Void
    ) {
        self.feed = feed
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.onDismiss = onDismiss
    }

    var hasUnsavedChanges: Bool {
        draft != nil
            || !captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isPreparingVideo: Bool {
        phase == .importingVideo
    }

    var isBackgroundPreparing: Bool {
        backgroundPreparationState == .preparing
    }

    var previewVideoURL: URL? {
        guard let draft else { return nil }
        let url: URL
        if draft.videoAssetState == .preparedDelivery {
            url = draft.localVideoURL
        } else {
            url = draft.ownedSourceURL ?? draft.localVideoURL
        }
        guard ReelVideoImport.fileIsReadable(at: url) else { return nil }
        return url
    }

    var isPublishing: Bool {
        publishTask != nil || didHandOffBackgroundPublish
    }

    var isCommittingPublish: Bool {
        publishTask != nil
    }

    var canPublish: Bool {
        guard phase == .ready,
              draft != nil,
              !didHandOffBackgroundPublish,
              !isFullVideoImportInProgress,
              videoPipelineTask == nil,
              publishTask == nil
        else { return false }
        if case .failed = backgroundPreparationState { return false }
        return true
    }

    var linkedTradeSummary: String? {
        draft?.linkedTradeSummary
    }

    var linkedTrade: Trade? {
        guard let id = draft?.linkedTradeID else { return nil }
        if let match = pickerTrades.first(where: { $0.id == id }) {
            return match
        }
        return detailCache.trade(id: id)
    }

    func loadIfNeeded() {
        guard !hasPrepared else { return }
        hasPrepared = true
        Task { await prepare() }
    }

    func retryLoad() {
        hasPrepared = false
        loadIfNeeded()
    }

    /// Single entry for PhotosPicker selections — loads provider once, then prepares.
    func importFromPhotosPicker(_ item: PhotosPickerItem) {
        let itemID = item.itemIdentifier ?? UUID().uuidString
        if itemID == lastImportedItemIdentifier {
            if videoPipelineTask != nil || isFullVideoImportInProgress {
                VideoPrepareDiagnostics.logReusedExisting(id: currentSelectionID ?? itemID)
                return
            }
            if draft != nil, phase == .ready, !isFullVideoImportInProgress {
                VideoPrepareDiagnostics.logReusedExisting(id: currentSelectionID ?? itemID)
                return
            }
        }
        lastImportedItemIdentifier = itemID

        selectionGeneration &+= 1
        let generation = selectionGeneration
        let selectionID = UUID().uuidString
        let previousSelectionID = currentSelectionID
        let preservedLinkedTradeID = draft?.linkedTradeID
        let preservedLinkedTradeSummary = draft?.linkedTradeSummary
        let previousDraft = draft

        currentSelectionID = selectionID
        let fastOpenStarted = ContinuousClock.now
        ClipFastOpenDiagnostics.logSelectionReceived(selectionID: selectionID)
        VideoImportDiagnostics.logSelectionReceived(id: selectionID)

        videoPipelineTask?.cancel()
        cancelBackgroundPreparation(for: previousSelectionID)
        formError = nil
        uploadProgress = 0
        backgroundPreparationState = .idle

        cleanupDraftFiles(previousDraft)
        presentComposerShell(
            selectionID: selectionID,
            preservedLinkedTradeID: preservedLinkedTradeID,
            preservedLinkedTradeSummary: preservedLinkedTradeSummary
        )
        ClipFastOpenDiagnostics.logComposerPresented(
            selectionID: selectionID,
            elapsedMs: Self.elapsedMilliseconds(since: fastOpenStarted)
        )

        videoPipelineTask = Task {
            await runPhotosPickerImportPipeline(
                generation: generation,
                selectionID: selectionID,
                photosItem: item,
                fastOpenStarted: fastOpenStarted
            )
        }
    }

    /// Camera recordings — copy into app-owned storage, then prepare once.
    func importFromLocalFile(_ url: URL, contentType: String?) {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        let selectionID = UUID().uuidString
        let previousSelectionID = currentSelectionID
        let preservedLinkedTradeID = draft?.linkedTradeID
        let preservedLinkedTradeSummary = draft?.linkedTradeSummary
        let previousDraft = draft

        currentSelectionID = selectionID
        lastImportedItemIdentifier = nil
        let fastOpenStarted = ContinuousClock.now
        ClipFastOpenDiagnostics.logSelectionReceived(selectionID: selectionID)
        VideoImportDiagnostics.logSelectionReceived(id: selectionID)

        videoPipelineTask?.cancel()
        cancelBackgroundPreparation(for: previousSelectionID)
        formError = nil
        uploadProgress = 0
        backgroundPreparationState = .idle

        cleanupDraftFiles(previousDraft)
        presentComposerShell(
            selectionID: selectionID,
            preservedLinkedTradeID: preservedLinkedTradeID,
            preservedLinkedTradeSummary: preservedLinkedTradeSummary
        )
        ClipFastOpenDiagnostics.logComposerPresented(
            selectionID: selectionID,
            elapsedMs: Self.elapsedMilliseconds(since: fastOpenStarted)
        )

        videoPipelineTask = Task {
            await runLocalFileImportPipeline(
                generation: generation,
                selectionID: selectionID,
                localFileURL: url,
                localContentType: contentType,
                fastOpenStarted: fastOpenStarted
            )
        }
    }

    func clearVideo() {
        guard !isPublishing else { return }
        videoPipelineTask?.cancel()
        videoPipelineTask = nil
        cancelBackgroundPreparation(for: currentSelectionID)
        cleanupDraftFiles(draft)
        draft = nil
        currentSelectionID = nil
        lastImportedItemIdentifier = nil
        backgroundPreparationState = .idle
        isFullVideoImportInProgress = false
        uploadProgress = 0
        if case .failed = phase {
            // Keep failed shell state.
        } else {
            phase = .ready
        }
    }

    func selectLinkedTrade(_ trade: Trade) {
        guard var current = draft else {
            formError = "Choose a video first, then link a trade."
            return
        }
        current.linkedTradeID = trade.id
        current.linkedTradeSummary = Self.summary(for: trade)
        current.caption = captionText
        draft = current
        ExperienceHaptics.play(.selection)
    }

    func clearLinkedTrade() {
        guard var current = draft else { return }
        current.linkedTradeID = nil
        current.linkedTradeSummary = nil
        draft = current
    }

    func loadTradesIfNeeded() {
        guard !hasLoadedTrades else { return }
        hasLoadedTrades = true
        Task { await loadTrades() }
    }

    func publish() {
        if didHandOffBackgroundPublish || publishTask != nil {
            return
        }

        guard validate() else { return }

        guard let draft else {
            formError = "Choose a video to continue."
            return
        }

        guard phase == .ready, videoPipelineTask == nil else { return }

        let sourceURL = draft.ownedSourceURL ?? draft.localVideoURL
        guard ReelVideoImport.fileIsReadable(at: sourceURL) else {
            formError = "Video is no longer available. Please select it again."
            cleanupDraftFiles(self.draft)
            self.draft = nil
            return
        }

        let publishID = UUID().uuidString
        ClipPublishDiagnostics.logTapReceived(
            selectionID: draft.selectionID,
            preparationState: preparationStateLabel,
            publishID: publishID
        )

        publishTask = Task { @MainActor in
            defer { publishTask = nil }
            await commitPublish(publishID: publishID)
        }
    }

    func dismissRequested() {
        guard !isPublishing, !didHandOffBackgroundPublish else { return }
        videoPipelineTask?.cancel()
        cancelBackgroundPreparation(for: currentSelectionID)
        cleanupDraftFiles(draft)
        onDismiss()
    }

    #if DEBUG
    func applyScreenshotFixture(filled: Bool) {
        if filled {
            let trade = CreateReelFixtures.sampleTrade(owner: viewerID ?? CreateReelFixtures.viewerID)
            detailCache.seed(trade)
            draft = CreateReelFixtures.screenshotDraft(linkedTrade: trade)
            currentSelectionID = draft?.selectionID
            captionText = ""
            phase = .ready
        } else {
            draft = nil
            captionText = ""
            currentSelectionID = nil
        }
    }
    #endif

    // MARK: - Private

    private func prepare() async {
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
        guard viewerID != nil else {
            phase = .failed("Sign in to create a clip.")
            return
        }
        phase = .ready
    }

    private func loadTrades() async {
        isLoadingTrades = true
        defer { isLoadingTrades = false }
        guard let viewerID else { return }
        if viewerID.rawValue.hasPrefix("dev.") {
            pickerTrades = CreateReelFixtures.sampleTrades(owner: viewerID)
            return
        }
        do {
            let page = try await trades.trades(
                ownedBy: viewerID,
                accountID: nil,
                page: PageRequest(limit: 30),
                publicOnly: false
            )
            pickerTrades = page.items
        } catch {
            pickerTrades = []
        }
    }

    private func runPhotosPickerImportPipeline(
        generation: UInt64,
        selectionID: String,
        photosItem: PhotosPickerItem,
        fastOpenStarted: ContinuousClock.Instant
    ) async {
        defer {
            if selectionGeneration == generation {
                videoPipelineTask = nil
                isFullVideoImportInProgress = false
            }
        }

        do {
            let posterStarted = ContinuousClock.now
            let importStarted = ContinuousClock.now

            let lightweightPosterTask = Task {
                ClipFastOpenDiagnostics.logLightweightPosterStarted(selectionID: selectionID)
                let poster = await ReelPhotosLightweightPoster.fetch(from: photosItem)
                if let poster {
                    ClipFastOpenDiagnostics.logLightweightPosterReady(
                        selectionID: selectionID,
                        elapsedMs: Self.elapsedMilliseconds(since: posterStarted)
                    )
                    await MainActor.run {
                        guard selectionGeneration == generation else { return }
                        applyLightweightPoster(poster, selectionID: selectionID)
                    }
                }
                return poster
            }

            ClipFastOpenDiagnostics.logFullVideoImportStarted(selectionID: selectionID)
            let owned = try await ReelVideoImport.importFromPhotosPicker(
                photosItem,
                selectionID: selectionID
            )
            let resolvedPoster = await lightweightPosterTask.value

            guard selectionGeneration == generation else {
                VideoImportDiagnostics.logStaleImportDropped(
                    id: selectionID,
                    generation: generation,
                    current: selectionGeneration
                )
                ReelVideoImport.cleanup(selectionID: selectionID)
                return
            }

            ClipFastOpenDiagnostics.logFullVideoImportCompleted(
                selectionID: selectionID,
                elapsedMs: Self.elapsedMilliseconds(since: importStarted),
                bytes: owned.byteCount
            )

            try await finishOwnedVideoImport(
                generation: generation,
                selectionID: selectionID,
                owned: owned,
                fastOpenStarted: fastOpenStarted,
                posterFallbackReason: resolvedPoster == nil ? "photosLightweightUnavailable" : nil
            )
        } catch is CancellationError {
            guard selectionGeneration == generation else { return }
        } catch {
            guard selectionGeneration == generation else { return }
            formError = Self.userMessage(for: error)
            backgroundPreparationState = .idle
            isFullVideoImportInProgress = false
            VideoImportDiagnostics.logImportFailed(
                id: selectionID,
                stage: "pipeline",
                message: error.localizedDescription
            )
        }
    }

    private func runLocalFileImportPipeline(
        generation: UInt64,
        selectionID: String,
        localFileURL: URL,
        localContentType: String?,
        fastOpenStarted: ContinuousClock.Instant
    ) async {
        defer {
            if selectionGeneration == generation {
                videoPipelineTask = nil
                isFullVideoImportInProgress = false
            }
        }

        ClipFastOpenDiagnostics.logFullVideoImportStarted(selectionID: selectionID)
        let importStarted = ContinuousClock.now

        do {
            let owned = try ReelVideoImport.importFromLocalFile(
                localFileURL,
                contentType: localContentType,
                selectionID: selectionID
            )

            guard selectionGeneration == generation else {
                VideoImportDiagnostics.logStaleImportDropped(
                    id: selectionID,
                    generation: generation,
                    current: selectionGeneration
                )
                ReelVideoImport.cleanup(selectionID: selectionID)
                return
            }

            ClipFastOpenDiagnostics.logFullVideoImportCompleted(
                selectionID: selectionID,
                elapsedMs: Self.elapsedMilliseconds(since: importStarted),
                bytes: owned.byteCount
            )

            try await finishOwnedVideoImport(
                generation: generation,
                selectionID: selectionID,
                owned: owned,
                fastOpenStarted: fastOpenStarted,
                posterFallbackReason: "localFileNoPhotoKitPoster"
            )
        } catch is CancellationError {
            guard selectionGeneration == generation else { return }
        } catch {
            guard selectionGeneration == generation else { return }
            formError = Self.userMessage(for: error)
            backgroundPreparationState = .idle
            isFullVideoImportInProgress = false
            VideoImportDiagnostics.logImportFailed(
                id: selectionID,
                stage: "pipeline",
                message: error.localizedDescription
            )
        }
    }

    private func presentComposerShell(
        selectionID: String,
        preservedLinkedTradeID: TradeID?,
        preservedLinkedTradeSummary: String?
    ) {
        let pendingURL = (
            try? ReelVideoImport.ownedSourceURL(selectionID: selectionID, fileExtension: "mov")
        ) ?? URL(fileURLWithPath: NSTemporaryDirectory())

        draft = ReelDraft(
            selectionID: selectionID,
            ownedSourceURL: nil,
            localVideoURL: pendingURL,
            videoAssetState: .sourceMedia,
            contentType: "video/quicktime",
            byteCount: 0,
            durationSeconds: 0,
            thumbnailJPEG: nil,
            thumbnailPreview: nil,
            caption: captionText,
            linkedTradeID: preservedLinkedTradeID,
            linkedTradeSummary: preservedLinkedTradeSummary
        )
        phase = .ready
        isFullVideoImportInProgress = true
    }

    private func applyLightweightPoster(
        _ poster: ReelPhotosLightweightPoster.Result,
        selectionID: String
    ) {
        guard var current = draft, current.selectionID == selectionID else { return }
        current.thumbnailPreview = poster.image
        current.thumbnailJPEG = poster.jpegData
        if poster.durationSeconds > 0 {
            current.durationSeconds = poster.durationSeconds
        }
        draft = current
    }

    private func finishOwnedVideoImport(
        generation: UInt64,
        selectionID: String,
        owned: ReelVideoImport.OwnedSource,
        fastOpenStarted: ContinuousClock.Instant,
        posterFallbackReason: String?
    ) async throws {
        if draft?.thumbnailPreview == nil, let posterFallbackReason {
            ClipFastOpenDiagnostics.logPosterFallbackToOwnedCopy(
                selectionID: selectionID,
                reason: posterFallbackReason
            )
            ClipComposeDiagnostics.logPosterFrameStarted(selectionID: selectionID)
            let posterStarted = ContinuousClock.now
            let poster = try await ReelPosterFrameExtractor.extractPoster(from: owned.url)
            ClipComposeDiagnostics.logPosterFrameReady(
                selectionID: selectionID,
                elapsedMs: Self.elapsedMilliseconds(since: posterStarted)
            )
            await MainActor.run {
                guard selectionGeneration == generation else { return }
                applyLightweightPoster(
                    ReelPhotosLightweightPoster.Result(
                        image: poster.image,
                        jpegData: poster.jpegData,
                        durationSeconds: poster.durationSeconds
                    ),
                    selectionID: selectionID
                )
            }
        }

        guard selectionGeneration == generation else {
            ReelVideoImport.cleanup(selectionID: selectionID)
            return
        }

        await MainActor.run {
            guard var current = draft, current.selectionID == selectionID else { return }
            current.ownedSourceURL = owned.url
            current.localVideoURL = owned.url
            current.contentType = owned.contentType
            current.byteCount = owned.byteCount
            draft = current
            isFullVideoImportInProgress = false
            uploadProgress = 0

            let interactiveMs = Self.elapsedMilliseconds(since: fastOpenStarted)
            ClipComposeDiagnostics.logComposerInteractive(selectionID: selectionID, elapsedMs: interactiveMs)
        }

        startBackgroundPreparationObservation(
            generation: generation,
            selectionID: selectionID,
            ownedSourceURL: owned.url,
            contentType: owned.contentType
        )
    }

    private func commitPublish(publishID: String) async {
        guard !didHandOffBackgroundPublish, let publishDraftBase = draft else { return }
        guard let viewerID else {
            formError = "Sign in to publish."
            return
        }

        didHandOffBackgroundPublish = true
        formError = nil

        var publishDraft = publishDraftBase
        publishDraft.caption = captionText
        let preparationTaskID = publishDraft.selectionID
        let queuedWhilePreparing = publishDraft.videoAssetState != .preparedDelivery

        await ReelBackgroundPreparationRegistry.shared.adoptForUpload(
            preparationTaskID: preparationTaskID
        )

        let tradeIsPublic: Bool? = {
            guard let id = publishDraft.linkedTradeID else { return nil }
            if let match = pickerTrades.first(where: { $0.id == id }) {
                return match.visibility == .public
            }
            if let cached = detailCache.trade(id: id) {
                return cached.visibility == .public
            }
            return nil
        }()

        let snapshot: ReelDraftSnapshot
        do {
            if publishDraft.videoAssetState == .preparedDelivery {
                snapshot = try ReelEncodingPipeline.captureUploadSnapshot(
                    from: publishDraft,
                    publishID: publishID,
                    captionOverride: nil
                )
            } else {
                snapshot = try ReelEncodingPipeline.freezeCommittedSnapshot(
                    from: publishDraft,
                    captionOverride: nil
                )
            }
        } catch {
            didHandOffBackgroundPublish = false
            formError = Self.userMessage(for: error)
            return
        }

        ClipPublishDiagnostics.logCommitted(
            publishID: publishID,
            selectionID: publishDraft.selectionID,
            preparationTaskID: preparationTaskID,
            queuedWhilePreparing: queuedWhilePreparing
        )

        let spec = ReelUploadSpec(
            publishID: publishID,
            snapshot: snapshot,
            authorID: viewerID,
            tradeIsPublic: tradeIsPublic,
            preparationTaskID: preparationTaskID
        )
        let jobID = GlobalUploadCoordinator.shared.enqueueReel(
            spec: spec,
            services: GlobalUploadServices(
                feed: feed,
                profiles: nil,
                trades: trades,
                achievements: nil,
                uploadService: uploadService,
                objectStorage: objectStorage,
                detailCache: detailCache
            )
        )

        var preservedURLs: Set<URL> = [snapshot.localVideoURL]
        if let owned = publishDraft.ownedSourceURL {
            preservedURLs.insert(owned)
        }
        if publishDraft.videoAssetState == .preparedDelivery {
            preservedURLs.insert(publishDraft.localVideoURL)
        }

        backgroundPrepObservationTask?.cancel()
        backgroundPrepObservationTask = nil
        cleanupDraftFiles(publishDraft, preservingVideoURLs: preservedURLs)
        draft = nil
        currentSelectionID = nil
        lastImportedItemIdentifier = nil
        backgroundPreparationState = .idle
        phase = .ready

        ClipPublishDiagnostics.logComposerDismissed(publishID: publishID)
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .reel,
            event: .composerDismissed,
            taskCancelled: Task.isCancelled
        )
        onDismiss()
    }

    private func startBackgroundPreparationObservation(
        generation: UInt64,
        selectionID: String,
        ownedSourceURL: URL,
        contentType: String
    ) {
        backgroundPrepObservationTask?.cancel()
        backgroundPreparationState = .preparing
        let prepStarted = ContinuousClock.now

        ClipPrepareDiagnostics.logBackgroundStarted(
            selectionID: selectionID,
            preparationTaskID: selectionID
        )

        Task {
            await ReelBackgroundPreparationRegistry.shared.startIfNeeded(
                preparationTaskID: selectionID,
                selectionID: selectionID,
                ownedSourceURL: ownedSourceURL,
                contentType: contentType
            )
        }

        backgroundPrepObservationTask = Task {
            do {
                let package = try await ReelBackgroundPreparationRegistry.shared.awaitPrepared(
                    preparationTaskID: selectionID
                )
                let adopted = await ReelBackgroundPreparationRegistry.shared.isAdoptedForUpload(
                    preparationTaskID: selectionID
                )
                let prepMs = Self.elapsedMilliseconds(since: prepStarted)
                await MainActor.run {
                    guard selectionGeneration == generation else {
                        if !adopted {
                            MediaVideoPreparation.cleanupTemporaryFile(at: package.prepared.fileURL)
                        }
                        return
                    }
                    if adopted { return }
                    guard var current = draft, current.selectionID == selectionID else { return }

                    ClipPrepareDiagnostics.logBackgroundCompleted(
                        selectionID: selectionID,
                        preparationTaskID: selectionID,
                        bytes: package.prepared.byteCount,
                        elapsedMs: prepMs
                    )

                    cleanupDraftFiles(
                        current,
                        preservingVideoURLs: [package.prepared.fileURL, ownedSourceURL]
                    )
                    current.localVideoURL = package.prepared.fileURL
                    current.videoAssetState = .preparedDelivery
                    current.contentType = package.prepared.contentType
                    current.byteCount = package.prepared.byteCount
                    current.durationSeconds = package.prepared.durationSeconds
                    if current.thumbnailJPEG == nil {
                        current.thumbnailJPEG = package.prepared.thumbnailJPEG
                    }
                    if current.thumbnailPreview == nil {
                        current.thumbnailPreview = package.prepared.thumbnailImage
                    }
                    draft = current
                    backgroundPreparationState = .ready
                }
            } catch is CancellationError {
                return
            } catch {
                let adopted = await ReelBackgroundPreparationRegistry.shared.isAdoptedForUpload(
                    preparationTaskID: selectionID
                )
                await MainActor.run {
                    guard selectionGeneration == generation, !adopted else { return }
                    guard draft?.selectionID == selectionID else { return }
                    let message = Self.userMessage(for: error)
                    backgroundPreparationState = .failed(message)
                    formError = message
                    ClipPrepareDiagnostics.logBackgroundFailed(
                        selectionID: selectionID,
                        preparationTaskID: selectionID,
                        reason: error.localizedDescription
                    )
                }
            }
        }
    }

    private func cancelBackgroundPreparation(for selectionID: String?) {
        backgroundPrepObservationTask?.cancel()
        backgroundPrepObservationTask = nil
        guard let selectionID else { return }
        Task {
            await ReelBackgroundPreparationRegistry.shared.cancel(preparationTaskID: selectionID)
        }
    }

    private var preparationStateLabel: String {
        switch backgroundPreparationState {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case .ready: return "ready"
        case .failed: return "failed"
        }
    }

    private func cleanupDraftFiles(_ draft: ReelDraft?, preservingVideoURLs: Set<URL> = []) {
        guard let draft else { return }
        if !preservingVideoURLs.contains(draft.localVideoURL) {
            MediaVideoPreparation.cleanupTemporaryFile(at: draft.localVideoURL)
        }
        if let ownedSourceURL = draft.ownedSourceURL, !preservingVideoURLs.contains(ownedSourceURL) {
            ReelVideoImport.cleanup(url: ownedSourceURL)
        }
        if preservingVideoURLs.isEmpty {
            ReelVideoImport.cleanup(selectionID: draft.selectionID)
        }
    }

    private func validate() -> Bool {
        guard draft != nil else {
            formError = "Choose a video to continue."
            return false
        }
        let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.count > MediaVideoPreparation.maxCaptionLength {
            formError = "Caption must be \(MediaVideoPreparation.maxCaptionLength) characters or less."
            return false
        }
        return true
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    private static func summary(for trade: Trade) -> String {
        var parts = ["\(trade.symbol.ticker) · \(trade.side.rawValue.capitalized)"]
        if let pnl = trade.realizedPnL {
            let amount = NSDecimalNumber(decimal: pnl.amount).stringValue
            parts.append(pnl.amount >= 0 ? "+$\(amount)" : "-$\(amount.replacingOccurrences(of: "-", with: ""))")
        }
        return parts.joined(separator: " · ")
    }

    private static func userMessage(for error: Error) -> String {
        if let failure = error as? VideoPreparationFailure {
            switch failure {
            case .compressionFailed, .outputValidationFailed:
                return MediaVideoPreparation.compressionFailedMessage
            case .durationExceeded:
                return MediaVideoPreparation.durationLimitMessage
            case .sourceTooLarge:
                return MediaVideoPreparation.sourceTooLargeMessage
            case .unsupportedVideo:
                return "Clips support MP4 and MOV videos only."
            case .cancelled:
                return "Publish was cancelled."
            default:
                return MediaVideoPreparation.compressionFailedMessage
            }
        }
        if let app = error as? AppError {
            switch app {
            case .unknown(let message) where !message.isEmpty:
                if message.contains("already has a clip") {
                    return "This trade already has a clip attached."
                }
                if message.contains("Couldn't read") || message.contains("helper application") {
                    return "Couldn't import that video. Please select it again."
                }
                return message
            case .unknown:
                return "Couldn't publish clip. Try again."
            case .authentication(.sessionExpired), .authentication(.invalidCredentials):
                return "Your session expired. Sign in again and retry."
            case .authentication:
                return "Sign in to publish clips."
            case .cancelled:
                return "Publish was cancelled."
            case .transport(let network):
                switch network {
                case .unauthorized, .forbidden:
                    return "Couldn't upload this clip. Check your account permissions and try again."
                case .server(let code, _) where code == 413:
                    return "This clip is too large to upload. Try a shorter video."
                case .connectivity, .timeout:
                    return "Couldn't reach the server. Check your connection and try again."
                default:
                    return "Couldn't upload this clip. Try again in a moment."
                }
            case .notImplemented:
                return "Publishing isn't available yet."
            }
        }
        if let domain = error as? DomainError, case .conflict(let message) = domain {
            return message
        }
        return "Couldn't publish clip. Try again."
    }
}
