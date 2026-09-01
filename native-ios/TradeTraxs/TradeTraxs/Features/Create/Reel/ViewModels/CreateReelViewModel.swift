import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class CreateReelViewModel {
    enum Phase: Equatable {
        case idle
        case ready
        case preparingVideo
        case publishing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var formError: String?
    private(set) var uploadProgress: Double = 0
    private(set) var isPreparingVideo = false
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
    private var publishTask: Task<Void, Never>?
    private var hasPrepared = false
    private var hasLoadedTrades = false

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

    var canPublish: Bool {
        phase == .ready || phase == .preparingVideo
    }

    var linkedTradeSummary: String? {
        draft?.linkedTradeSummary
    }

    /// Trade-linked clips cannot store `reels.caption` (DB check).
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

    func applyLocalVideo(from url: URL, contentType: String?) {
        guard phase == .ready || phase == .preparingVideo else { return }
        isPreparingVideo = true
        phase = .preparingVideo
        formError = nil
        Task {
            do {
                let prepared = try await MediaVideoPreparation.prepareLocalVideo(
                    from: url,
                    contentType: contentType
                )
                let next = ReelDraft(
                    localVideoURL: prepared.fileURL,
                    contentType: prepared.contentType,
                    byteCount: prepared.byteCount,
                    durationSeconds: prepared.durationSeconds,
                    thumbnailJPEG: prepared.thumbnailJPEG,
                    thumbnailPreview: prepared.thumbnailImage,
                    caption: captionText,
                    linkedTradeID: draft?.linkedTradeID,
                    linkedTradeSummary: draft?.linkedTradeSummary
                )
                draft = next
                phase = .ready
            } catch {
                phase = .ready
                formError = Self.userMessage(for: error)
            }
            isPreparingVideo = false
        }
    }

    func clearVideo() {
        draft = nil
    }

    func selectLinkedTrade(_ trade: Trade) {
        guard var current = draft else {
            // Allow selecting trade before video — store summary on a temporary shell.
            formError = "Choose a video first, then link a trade."
            return
        }
        current.linkedTradeID = trade.id
        current.linkedTradeSummary = Self.summary(for: trade)
        // Caption lives on the trade when linked.
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
        guard canPublish, publishTask == nil else { return }
        publishTask = Task { await performPublish() }
    }

    func dismissRequested() {
        onDismiss()
    }

    #if DEBUG
    func applyScreenshotFixture(filled: Bool) {
        if filled {
            let trade = CreateReelFixtures.sampleTrade(owner: viewerID ?? CreateReelFixtures.viewerID)
            draft = CreateReelFixtures.screenshotDraft(linkedTrade: trade)
            captionText = ""
        } else {
            draft = nil
            captionText = ""
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

    private func performPublish() async {
        formError = nil
        guard validate() else {
            publishTask = nil
            return
        }
        guard let viewerID, var draft else {
            formError = "Choose a video to publish."
            publishTask = nil
            return
        }

        if captionEnabled {
            draft.caption = captionText
        } else {
            draft.caption = ""
        }

        phase = .publishing
        uploadProgress = 0
        do {
            let reel: Reel
            if viewerID.rawValue.hasPrefix("dev.") {
                reel = CreateReelFixtures.sampleReel(
                    author: viewerID,
                    tradeID: draft.linkedTradeID
                )
            } else {
                let tradeIsPublic: Bool? = {
                    guard let id = draft.linkedTradeID else { return nil }
                    return pickerTrades.first(where: { $0.id == id })?.visibility == .public
                }()
                reel = try await ReelPublishPipeline.publish(
                    draft: draft,
                    authorID: viewerID,
                    tradeID: draft.linkedTradeID,
                    tradeIsPublic: tradeIsPublic,
                    feed: feed,
                    uploadService: uploadService,
                    objectStorage: objectStorage,
                    onProgress: { [weak self] value in
                        Task { @MainActor in self?.uploadProgress = value }
                    }
                )
            }

            detailCache.seed(reel)
            OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
            ExperienceHaptics.play(.success)
            phase = .ready
            onDismiss()
        } catch {
            phase = .ready
            formError = Self.userMessage(for: error)
        }
        publishTask = nil
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
        if let app = error as? AppError, case .unknown(let message) = app, !message.isEmpty {
            if message.contains("already has a clip") {
                return "This trade already has a clip attached."
            }
            return message
        }
        if let domain = error as? DomainError, case .conflict(let m) = domain {
            return m
        }
        return "Couldn't publish clip. Check your connection and try again."
    }
}
