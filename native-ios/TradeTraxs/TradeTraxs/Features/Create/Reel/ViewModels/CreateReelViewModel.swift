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

    private(set) var phase: Phase = .idle
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
    private var publishTask: Task<Void, Never>?
    private var activePublishID: String?
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
        phase == .importingVideo || phase == .preparingVideo
    }

    var isPublishing: Bool {
        phase == .publishing || activePublishID != nil || publishTask != nil
    }

    var canPublish: Bool {
        phase == .ready
            && draft != nil
            && videoPipelineTask == nil
            && activePublishID == nil
            && publishTask == nil
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

    var captionEnabled: Bool {
        draft?.linkedTradeID == nil
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
            if videoPipelineTask != nil || isPreparingVideo {
                VideoPrepareDiagnostics.logReusedExisting(id: currentSelectionID ?? itemID)
                return
            }
            if draft != nil, phase == .ready {
                VideoPrepareDiagnostics.logReusedExisting(id: currentSelectionID ?? itemID)
                return
            }
        }
        lastImportedItemIdentifier = itemID

        selectionGeneration &+= 1
        let generation = selectionGeneration
        let selectionID = UUID().uuidString
        currentSelectionID = selectionID
        VideoImportDiagnostics.logSelectionReceived(id: selectionID)

        videoPipelineTask?.cancel()
        phase = .importingVideo
        formError = nil
        uploadProgress = 0

        videoPipelineTask = Task {
            await runVideoPipeline(
                generation: generation,
                selectionID: selectionID,
                photosItem: item,
                localFileURL: nil,
                localContentType: nil
            )
        }
    }

    /// Camera recordings — copy into app-owned storage, then prepare once.
    func importFromLocalFile(_ url: URL, contentType: String?) {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        let selectionID = UUID().uuidString
        currentSelectionID = selectionID
        lastImportedItemIdentifier = nil
        VideoImportDiagnostics.logSelectionReceived(id: selectionID)

        videoPipelineTask?.cancel()
        phase = .importingVideo
        formError = nil
        uploadProgress = 0

        videoPipelineTask = Task {
            await runVideoPipeline(
                generation: generation,
                selectionID: selectionID,
                photosItem: nil,
                localFileURL: url,
                localContentType: contentType
            )
        }
    }

    func clearVideo() {
        guard !isPublishing else { return }
        videoPipelineTask?.cancel()
        videoPipelineTask = nil
        cleanupDraftFiles(draft)
        draft = nil
        currentSelectionID = nil
        lastImportedItemIdentifier = nil
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
        current.caption = ""
        captionText = ""
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
        ReelPublishDiagnostics.logTapReceived(selectionID: draft?.selectionID)

        if activePublishID != nil || publishTask != nil {
            ReelPublishDiagnostics.logDuplicateInvocationIgnored(
                publishID: activePublishID ?? "in-flight"
            )
            return
        }

        guard let draft else {
            ReelPublishDiagnostics.logRejected(reason: "noDraft")
            formError = "Choose a video to continue."
            return
        }

        if videoPipelineTask != nil || isPreparingVideo {
            ReelPublishDiagnostics.logRejected(reason: "videoPreparing")
            formError = "Wait for video preparation to finish."
            return
        }

        guard phase == .ready else {
            ReelPublishDiagnostics.logRejected(reason: "phaseNotReady")
            return
        }

        let preparedExists = ReelVideoImport.fileIsReadable(at: draft.localVideoURL)
        ReelPublishDiagnostics.logUsingPreparedVideo(
            selectionID: draft.selectionID,
            exists: preparedExists
        )
        guard preparedExists else {
            ReelPublishDiagnostics.logRejected(reason: "preparedVideoMissing")
            formError = "Video is no longer available. Please select it again."
            cleanupDraftFiles(self.draft)
            self.draft = nil
            return
        }

        let publishID = UUID().uuidString
        ReelPublishDiagnostics.logAccepted(
            publishID: publishID,
            selectionID: draft.selectionID
        )
        activePublishID = publishID
        phase = .publishing
        uploadProgress = 0
        formError = nil
        publishTask = Task { await performPublish(publishID: publishID) }
    }

    func dismissRequested() {
        guard !isPublishing else { return }
        videoPipelineTask?.cancel()
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

    private func runVideoPipeline(
        generation: UInt64,
        selectionID: String,
        photosItem: PhotosPickerItem?,
        localFileURL: URL?,
        localContentType: String?
    ) async {
        defer {
            if selectionGeneration == generation {
                videoPipelineTask = nil
            }
        }

        let preservedLinkedTradeID = draft?.linkedTradeID
        let preservedLinkedTradeSummary = draft?.linkedTradeSummary
        let previousDraft = draft

        do {
            let owned: ReelVideoImport.OwnedSource
            if let photosItem {
                owned = try await ReelVideoImport.importFromPhotosPicker(photosItem, selectionID: selectionID)
            } else if let localFileURL {
                owned = try ReelVideoImport.importFromLocalFile(
                    localFileURL,
                    contentType: localContentType,
                    selectionID: selectionID
                )
            } else {
                throw AppError.unknown(message: "Missing video import source.")
            }

            guard selectionGeneration == generation else {
                VideoImportDiagnostics.logStaleImportDropped(
                    id: selectionID,
                    generation: generation,
                    current: selectionGeneration
                )
                ReelVideoImport.cleanup(selectionID: selectionID)
                return
            }

            phase = .preparingVideo
            VideoPrepareDiagnostics.logStarted(id: selectionID)

            let prepared = try await MediaVideoPreparation.prepareLocalVideo(
                from: owned.url,
                contentType: owned.contentType,
                onProgress: { [weak self] value in
                    Task { @MainActor in self?.uploadProgress = value * 0.9 }
                }
            )

            guard selectionGeneration == generation else {
                VideoPrepareDiagnostics.logStalePrepareDropped(
                    id: selectionID,
                    generation: generation,
                    current: selectionGeneration
                )
                MediaVideoPreparation.cleanupTemporaryFile(at: prepared.fileURL)
                ReelVideoImport.cleanup(selectionID: selectionID)
                return
            }

            cleanupDraftFiles(previousDraft)

            let next = ReelDraft(
                selectionID: selectionID,
                ownedSourceURL: owned.url,
                localVideoURL: prepared.fileURL,
                contentType: prepared.contentType,
                byteCount: prepared.byteCount,
                durationSeconds: prepared.durationSeconds,
                thumbnailJPEG: prepared.thumbnailJPEG,
                thumbnailPreview: prepared.thumbnailImage,
                caption: captionText,
                linkedTradeID: preservedLinkedTradeID,
                linkedTradeSummary: preservedLinkedTradeSummary
            )
            draft = next
            phase = .ready
            uploadProgress = 0
            VideoPrepareDiagnostics.logCompleted(id: selectionID, bytes: prepared.byteCount)
        } catch is CancellationError {
            guard selectionGeneration == generation else { return }
            phase = draft == nil ? .ready : .ready
            VideoPrepareDiagnostics.logFailed(
                id: selectionID,
                stage: "cancelled",
                message: "Video preparation was cancelled."
            )
        } catch {
            guard selectionGeneration == generation else { return }
            phase = .ready
            formError = Self.userMessage(for: error)
            VideoPrepareDiagnostics.logFailed(
                id: selectionID,
                stage: "pipeline",
                message: error.localizedDescription
            )
            VideoImportDiagnostics.logImportFailed(
                id: selectionID,
                stage: "pipeline",
                message: error.localizedDescription
            )
        }
    }

    private func performPublish(publishID: String) async {
        var didFinish = false
        defer {
            publishTask = nil
            if activePublishID == publishID {
                activePublishID = nil
                if !didFinish, case .publishing = phase {
                    phase = .ready
                }
            }
        }

        guard activePublishID == publishID else {
            ReelPublishDiagnostics.logDuplicateInvocationIgnored(publishID: publishID)
            return
        }

        ReelPublishDiagnostics.logValidationStarted(publishID: publishID)
        formError = nil
        guard validate() else {
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "validation",
                error: AppError.unknown(message: formError ?? "Validation failed.")
            )
            didFinish = true
            phase = .ready
            return
        }
        ReelPublishDiagnostics.logValidationCompleted(publishID: publishID)

        guard let viewerID, var publishDraft = draft else {
            formError = "Choose a video to publish."
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "validation",
                error: AppError.unknown(message: "Missing draft.")
            )
            didFinish = true
            phase = .ready
            return
        }

        guard ReelVideoImport.fileIsReadable(at: publishDraft.localVideoURL) else {
            formError = "Video is no longer available. Please select it again."
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "validation",
                error: AppError.unknown(message: "Prepared video missing.")
            )
            cleanupDraftFiles(publishDraft)
            draft = nil
            didFinish = true
            phase = .ready
            return
        }

        if captionEnabled {
            publishDraft.caption = captionText
        } else {
            publishDraft.caption = ""
        }

        let linkedTradeID = publishDraft.linkedTradeID
        let tradeIsPublic: Bool? = {
            guard let id = linkedTradeID else { return nil }
            if let match = pickerTrades.first(where: { $0.id == id }) {
                return match.visibility == .public
            }
            if let cached = detailCache.trade(id: id) {
                return cached.visibility == .public
            }
            return nil
        }()

        do {
            if let tradeID = linkedTradeID {
                ReelPublishDiagnostics.logPreflightStarted(
                    publishID: publishID,
                    tradeID: tradeID.rawValue
                )
                if try await feed.tradeHasAttachedReel(tradeID) {
                    let error = AppError.domain(
                        .conflict(message: "This trade already has a clip attached.")
                    )
                    ReelPublishDiagnostics.logFailed(
                        publishID: publishID,
                        stage: "preflight",
                        error: error
                    )
                    throw error
                }
                ReelPublishDiagnostics.logPreflightCompleted(publishID: publishID)
            } else {
                ReelPublishDiagnostics.logPreflightStarted(publishID: publishID, tradeID: nil)
                ReelPublishDiagnostics.logPreflightCompleted(publishID: publishID)
            }

            guard activePublishID == publishID else {
                ReelPublishDiagnostics.logDuplicateInvocationIgnored(publishID: publishID)
                return
            }

            let reel: Reel
            if viewerID.rawValue.hasPrefix("dev.") {
                reel = CreateReelFixtures.sampleReel(
                    author: viewerID,
                    tradeID: linkedTradeID
                )
            } else {
                reel = try await ReelPublishPipeline.publish(
                    publishID: publishID,
                    draft: publishDraft,
                    authorID: viewerID,
                    tradeID: linkedTradeID,
                    tradeIsPublic: tradeIsPublic,
                    feed: feed,
                    uploadService: uploadService,
                    objectStorage: objectStorage,
                    onProgress: { [weak self] value in
                        Task { @MainActor in self?.uploadProgress = value }
                    }
                )
            }

            guard activePublishID == publishID else {
                ReelPublishDiagnostics.logDuplicateInvocationIgnored(publishID: publishID)
                return
            }

            ReelPublishDiagnostics.logCacheRefreshStarted(publishID: publishID)
            detailCache.seed(reel)
            OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
            cleanupDraftFiles(publishDraft)
            draft = nil
            currentSelectionID = nil
            lastImportedItemIdentifier = nil
            ExperienceHaptics.play(.success)
            didFinish = true
            phase = .ready
            onDismiss()
        } catch is CancellationError {
            guard activePublishID == publishID else { return }
            didFinish = true
            phase = .ready
            formError = "Publish was cancelled."
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "cancelled",
                error: AppError.cancelled
            )
        } catch {
            guard activePublishID == publishID else { return }
            didFinish = true
            phase = .ready
            formError = Self.userMessage(for: error)
            ReelPublishDiagnostics.logFailed(
                publishID: publishID,
                stage: "viewModel",
                error: error
            )
        }
    }

    private func cleanupDraftFiles(_ draft: ReelDraft?) {
        guard let draft else { return }
        MediaVideoPreparation.cleanupTemporaryFile(at: draft.localVideoURL)
        if let ownedSourceURL = draft.ownedSourceURL {
            ReelVideoImport.cleanup(url: ownedSourceURL)
        }
        ReelVideoImport.cleanup(selectionID: draft.selectionID)
    }

    private func validate() -> Bool {
        guard draft != nil else {
            formError = "Choose a video to continue."
            return false
        }
        if captionEnabled {
            let caption = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if caption.count > MediaVideoPreparation.maxCaptionLength {
                formError = "Caption must be \(MediaVideoPreparation.maxCaptionLength) characters or less."
                return false
            }
        }
        return true
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
