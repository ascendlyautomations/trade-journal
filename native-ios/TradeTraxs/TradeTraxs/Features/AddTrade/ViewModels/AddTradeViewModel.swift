import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AddTradeViewModel {
    enum Phase: Equatable {
        case idle
        case loadingAccounts
        case ready
        case saving
        case failed(String)
    }

    enum Mode: Equatable {
        case create
        case edit(TradeID)
    }

    enum Field: Hashable {
        case symbol
        case entry
        case exit
        case contracts
        case pnl
        case points
        case rr
    }

    private(set) var phase: Phase = .idle
    private(set) var mode: Mode = .create
    private(set) var accounts: [TradingAccount] = []
    private(set) var selectedAccountID: TradingAccountID?
    private(set) var fieldErrors: [Field: String] = [:]
    var formError: String?
    private(set) var isUploadingMedia = false

    var symbolText = ""
    var side: TradeSide = .long
    var entryPriceText = ""
    var exitPriceText = ""
    var contractsText = "1"
    var pnlText = ""
    var pointsText = ""
    var rrText = ""
    var entryAt: Date = .now
    var exitAt: Date = .now
    var includeExitTime = true
    var strategyText = ""
    var notesText = ""
    var publicCaptionText = ""
    var shareToProfile = false
    var screenshotData: Data?
    var screenshotPreview: UIImage?
    /// Local new-clip draft — uploaded + inserted with `trade_id` after trade save.
    var reelDraft: ReelDraft?
    private(set) var isPreparingClipVideo = false
    /// Secondary path: link an already-uploaded unattached clip (`reels.trade_id`).
    var linkedReel: Reel?
    private(set) var unattachedReels: [Reel] = []
    private(set) var isLoadingReels = false
    /// Trade saved but clip create/link failed — retry clip only (no duplicate trade).
    private(set) var tradeAwaitingClip: TradeID?
    /// Back-compat alias used by older tests / UI identifiers.
    var tradeAwaitingReelLink: TradeID? { tradeAwaitingClip }

    private let trades: any TradeRepository
    private let feed: any FeedRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let imagePipeline: (any ImagePipeline)?
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var saveTask: Task<Void, Never>?
    private var hasLoadedAccounts = false
    private var hasLoadedReels = false
    private var editingTrade: Trade?
    private var editingOriginalAccountID: TradingAccountID?
    private var existingImageURL: String?
    private var removeExistingScreenshot = false
    private var hydratedFingerprint: String?
    private static var lastAccountID: TradingAccountID?

    #if DEBUG
    private(set) var lastProbe: AddTradeLoadProbe.Snapshot?
    #endif

    init(
        trades: any TradeRepository,
        feed: any FeedRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        imagePipeline: (any ImagePipeline)? = nil,
        mode: Mode = .create,
        onDismiss: @escaping () -> Void
    ) {
        self.trades = trades
        self.feed = feed
        self.session = session
        self.detailCache = detailCache
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.imagePipeline = imagePipeline
        self.mode = mode
        self.onDismiss = onDismiss
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var navigationTitle: String {
        isEditing ? "Edit Trade" : "Add Trade"
    }

    var primarySaveTitle: String {
        isEditing ? "Save Changes" : "Save Trade"
    }

    var loadFailureTitle: String {
        isEditing ? "Couldn't open Edit Trade" : "Couldn't open Add Trade"
    }

    var selectedAccount: TradingAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    var eligibleAccounts: [TradingAccount] {
        accounts.filter { $0.isActive && $0.canAddTrades }
    }

    var ineligibleAccounts: [TradingAccount] {
        accounts.filter { $0.isActive && !$0.canAddTrades }
    }

    /// Picker list — edit mode keeps the original account even when read-only.
    var accountsForPicker: [TradingAccount] {
        var list = eligibleAccounts
        if let selected = selectedAccount,
           !list.contains(where: { $0.id == selected.id })
        {
            list.insert(selected, at: 0)
        }
        return list
    }

    var recentSymbols: [String] {
        if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
            return AddTradeFixtures.recentSymbols
        }
        // Prefer tickers already in the session detail cache / recent trades seed.
        let fromCache = detailCache.recentTradeTickers(limit: 8)
        return fromCache.isEmpty ? [] : fromCache
    }

    var hasUnsavedChanges: Bool {
        if isEditing {
            return formFingerprint != hydratedFingerprint
                || screenshotData != nil
                || removeExistingScreenshot
                || reelDraft != nil
                || linkedReel != nil
                || tradeAwaitingClip != nil
        }
        return !symbolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pnlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !entryPriceText.isEmpty
            || !exitPriceText.isEmpty
            || !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !strategyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !rrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || screenshotData != nil
            || reelDraft != nil
            || linkedReel != nil
            || contractsText != "1"
            || shareToProfile
            || tradeAwaitingClip != nil
    }

    /// Trade-linked clips inherit description from Share caption / `public_description`.
    var clipContextNote: String {
        if shareToProfile {
            let caption = publicCaptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if caption.isEmpty {
                return "Clip description will use your Share caption when you add one."
            }
            return "Clip description uses Share caption"
        }
        return "Clip stays private with this trade unless you Share to Profile."
    }

    var canSave: Bool {
        phase != .saving && phase != .loadingAccounts
    }

    var reviewSummary: String {
        let strategy = strategyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if strategy.isEmpty { return "Strategy / setup" }
        return strategy
    }

    /// Web stores `trades.rr` as a decimal ratio (e.g. `2.35`); UI shows `1 : 2.35`.
    var riskRewardDisplay: String {
        guard let value = Self.parseDecimal(rrText) else {
            return rrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : rrText
        }
        return Self.formatRiskReward(value)
    }

    /// Filtered recent symbols for the instrument picker search field.
    func filteredRecentSymbols(matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return recentSymbols }
        return recentSymbols.filter { $0.contains(q) }
    }

    /// Normalizes ticker the same way insert mapping does (trim + uppercase).
    static func normalizeSymbol(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Web `parseOptionalRr` — finite number, blank → nil.
    static func parseOptionalRiskReward(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseDecimal(trimmed)
    }

    static func formatRiskReward(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        let formatted = formatter.string(from: number) ?? "\(value)"
        return "1 : \(formatted)"
    }

    func loadIfNeeded() {
        guard !hasLoadedAccounts else { return }
        hasLoadedAccounts = true
        Task { await loadAccounts() }
    }

    func retryLoad() {
        hasLoadedAccounts = false
        loadIfNeeded()
    }

    func selectAccount(_ id: TradingAccountID) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        let keepOriginal = isEditing && id == editingOriginalAccountID
        guard account.canAddTrades || keepOriginal else {
            formError = "This account is read-only and cannot accept new trades."
            return
        }
        ExperienceHaptics.play(.selection)
        selectedAccountID = id
        Self.lastAccountID = id
        formError = nil
    }

    func applySymbol(_ ticker: String) {
        ExperienceHaptics.play(.selection)
        symbolText = Self.normalizeSymbol(ticker)
        fieldErrors[.symbol] = nil
    }

    func applyCustomSymbol(_ ticker: String) {
        let normalized = Self.normalizeSymbol(ticker)
        guard !normalized.isEmpty else {
            fieldErrors[.symbol] = "Symbol is required"
            return
        }
        // Free-text ticker — same storage as web (`trades.ticker`); no instrument table.
        applySymbol(normalized)
    }

    func setScreenshot(_ image: UIImage?) {
        guard let image else {
            clearScreenshot()
            return
        }
        screenshotPreview = image
        screenshotData = Self.prepareScreenshotJPEG(image)
        removeExistingScreenshot = false
    }

    func clearScreenshot() {
        screenshotData = nil
        screenshotPreview = nil
        if existingImageURL != nil {
            removeExistingScreenshot = true
        }
    }

    func applyClipVideo(from url: URL, contentType: String?) {
        isPreparingClipVideo = true
        formError = nil
        Task {
            do {
                let prepared = try await MediaVideoPreparation.prepareLocalVideo(
                    from: url,
                    contentType: contentType
                )
                linkedReel = nil
                reelDraft = ReelDraft(
                    localVideoURL: prepared.fileURL,
                    contentType: prepared.contentType,
                    byteCount: prepared.byteCount,
                    durationSeconds: prepared.durationSeconds,
                    thumbnailJPEG: prepared.thumbnailJPEG,
                    thumbnailPreview: prepared.thumbnailImage,
                    caption: "",
                    linkedTradeID: nil,
                    linkedTradeSummary: nil
                )
                ExperienceHaptics.play(.selection)
            } catch {
                formError = Self.userMessage(for: error)
            }
            isPreparingClipVideo = false
        }
    }

    func clearReelDraft() {
        reelDraft = nil
    }

    func selectLinkedReel(_ reel: Reel) {
        ExperienceHaptics.play(.selection)
        reelDraft = nil
        linkedReel = reel
        formError = nil
    }

    func clearLinkedReel() {
        linkedReel = nil
    }

    func clearClip() {
        reelDraft = nil
        linkedReel = nil
    }

    func loadUnattachedReelsIfNeeded() {
        guard !hasLoadedReels else { return }
        hasLoadedReels = true
        Task { await loadUnattachedReels() }
    }

    /// Reload accounts after Manage Accounts mutations (no polling).
    func reloadAccountsAfterMutation() {
        guard let viewerID else { return }
        Task { await refreshAccountsFromNetwork(viewerID: viewerID, forceNetwork: true) }
    }

    #if DEBUG
    func applyClipDraftFixture() {
        reelDraft = CreateReelFixtures.screenshotDraft()
        linkedReel = nil
    }
    #endif

    func save() {
        guard canSave, saveTask == nil else { return }
        saveTask = Task { await performSave() }
    }

    func dismissRequested() {
        onDismiss()
    }

    // MARK: - Private

    private func loadAccounts() async {
        #if DEBUG
        AddTradeLoadProbe.begin()
        #endif
        phase = .loadingAccounts
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }

        if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
            accounts = AddTradeFixtures.accounts(owner: viewerID)
            detailCache.seed(accounts: accounts, for: viewerID)
            selectDefaultAccount()
            guard await hydrateEditTradeIfNeeded() else { return }
            phase = .ready
            #if DEBUG
            AddTradeLoadProbe.noteRequest("fixtures")
            lastProbe = AddTradeLoadProbe.usableForm(loaded: ["accounts"])
            #endif
            return
        }

        guard let viewerID else {
            phase = .failed(isEditing ? "Sign in to edit trades." : "Sign in to add trades.")
            return
        }

        if let cached = SessionAccountsStore.shared.cached(for: viewerID)
            ?? detailCache.accounts(for: viewerID),
           !cached.isEmpty
        {
            accounts = cached
            selectDefaultAccount()
            guard await hydrateEditTradeIfNeeded() else { return }
            phase = .ready
            #if DEBUG
            AddTradeLoadProbe.noteRequest("accountsCache", blocking: false)
            lastProbe = AddTradeLoadProbe.usableForm(loaded: ["accountsCache"])
            #endif
            // Background revalidate only when session cache is stale/missing.
            if !SessionAccountsStore.shared.isFresh(for: viewerID) {
                Task { await refreshAccountsFromNetwork(viewerID: viewerID, forceNetwork: true) }
            }
            return
        }

        await refreshAccountsFromNetwork(viewerID: viewerID, forceNetwork: false)
        guard await hydrateEditTradeIfNeeded() else { return }
        #if DEBUG
        lastProbe = AddTradeLoadProbe.usableForm(loaded: ["accounts"])
        #endif
    }

    private func refreshAccountsFromNetwork(viewerID: ProfileID, forceNetwork: Bool = false) async {
        #if DEBUG
        AddTradeLoadProbe.noteRequest("accounts")
        #endif
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: viewerID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: forceNetwork
            )
            accounts = loaded
            if editingTrade == nil {
                selectDefaultAccount()
            }
            phase = .ready
        } catch {
            if accounts.isEmpty {
                phase = .failed("Couldn't load trading accounts.")
            } else {
                phase = .ready
            }
        }
    }

    private func selectDefaultAccount() {
        if case .edit = mode, selectedAccountID != nil { return }
        if let last = Self.lastAccountID,
           eligibleAccounts.contains(where: { $0.id == last })
        {
            selectedAccountID = last
            return
        }
        selectedAccountID = eligibleAccounts.first?.id
    }

    @discardableResult
    private func hydrateEditTradeIfNeeded() async -> Bool {
        guard case .edit(let tradeID) = mode else { return true }
        do {
            let trade: Trade
            if let cached = detailCache.trade(id: tradeID) {
                trade = cached
            } else if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
                throw AppError.unknown(message: "Trade not found")
            } else {
                trade = try await trades.trade(id: tradeID)
                detailCache.seed(trade)
            }
            apply(trade: trade)
            await loadExistingScreenshotPreviewIfNeeded()
            return true
        } catch {
            phase = .failed(Self.userMessage(for: error))
            return false
        }
    }

    private func apply(trade: Trade) {
        editingTrade = trade
        editingOriginalAccountID = trade.accountID
        selectedAccountID = trade.accountID
        symbolText = trade.symbol.ticker
        side = trade.side
        entryPriceText = Self.decimalFieldText(trade.entryPrice)
        exitPriceText = Self.decimalFieldText(trade.exitPrice)
        contractsText = Self.decimalFieldText(trade.quantity).isEmpty ? "1" : Self.decimalFieldText(trade.quantity)
        pnlText = Self.decimalFieldText(trade.realizedPnL?.amount)
        pointsText = Self.decimalFieldText(trade.points)
        rrText = Self.decimalFieldText(trade.riskReward)
        entryAt = trade.entryAt
        if let exit = trade.exitAt {
            exitAt = exit
            includeExitTime = true
        } else {
            exitAt = trade.entryAt
            includeExitTime = false
        }
        strategyText = trade.strategy ?? ""
        notesText = trade.notePreview ?? ""
        publicCaptionText = trade.publicCaption ?? ""
        shareToProfile = trade.visibility == .public
        existingImageURL = trade.thumbnail?.id
        removeExistingScreenshot = false
        screenshotData = nil
        hydratedFingerprint = formFingerprint
    }

    private func loadExistingScreenshotPreviewIfNeeded() async {
        guard let urlString = existingImageURL, !urlString.isEmpty else { return }
        guard screenshotPreview == nil else { return }
        guard let pipeline = imagePipeline else { return }
        do {
            let data = try await pipeline.data(
                for: ImageRequest(
                    reference: MediaReference(id: urlString, kind: .image, altText: nil),
                    purpose: .tradeScreenshot
                )
            )
            if let image = UIImage(data: data) {
                screenshotPreview = image
            }
        } catch {
            // Preview is optional — save still preserves existingImageURL.
        }
    }

    private var formFingerprint: String {
        [
            selectedAccountID?.rawValue ?? "",
            symbolText,
            side.rawValue,
            entryPriceText,
            exitPriceText,
            contractsText,
            pnlText,
            pointsText,
            rrText,
            String(entryAt.timeIntervalSince1970),
            includeExitTime ? String(exitAt.timeIntervalSince1970) : "nil",
            strategyText,
            notesText,
            publicCaptionText,
            shareToProfile ? "1" : "0",
        ].joined(separator: "|")
    }

    private static func decimalFieldText(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private func performSave() async {
        formError = nil
        fieldErrors = [:]

        // Partial recovery: trade already exists — only retry clip create/link.
        if let pendingTradeID = tradeAwaitingClip {
            phase = .saving
            do {
                try await attachClipIfNeeded(to: pendingTradeID, tradeIsPublic: shareToProfile)
                tradeAwaitingClip = nil
                ExperienceHaptics.play(.tradeSaved)
                phase = .ready
                onDismiss()
            } catch {
                phase = .ready
                formError = "Trade was saved, but the clip didn’t finish. Tap Save to retry the clip only."
            }
            saveTask = nil
            return
        }

        guard validate() else {
            saveTask = nil
            return
        }
        guard let account = selectedAccount else {
            formError = "Choose an account that can accept trades."
            saveTask = nil
            return
        }
        let keepOriginalAccount = isEditing && account.id == editingOriginalAccountID
        guard account.canAddTrades || keepOriginalAccount else {
            formError = "Choose an account that can accept trades."
            saveTask = nil
            return
        }

        phase = .saving
        var uploadedStoragePath: String?
        do {
            var imageURL: String?
            if let screenshotData {
                isUploadingMedia = true
                let uploaded = try await uploadScreenshot(screenshotData)
                uploadedStoragePath = uploaded.storagePath
                imageURL = uploaded.publicURL
                isUploadingMedia = false
            } else if isEditing {
                imageURL = removeExistingScreenshot ? nil : existingImageURL
            }

            let ticker = symbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let quantity = Self.parseDecimal(contractsText) ?? 1
            let pnl = Self.parseDecimal(pnlText) ?? 0
            // Edit preserves a manually-set session when present; create auto-detects.
            let sessionLabel: String = {
                if isEditing, let existing = editingTrade?.sessionLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !existing.isEmpty
                {
                    return existing
                }
                return TradingSessionLabel.session(from: entryAt) ?? "NY"
            }()
            let draft = TradeDraft(
                accountID: account.id,
                accountName: account.name,
                accountSizeLabel: account.size.map { "\($0.amount)" },
                accountModeLabel: account.mode.rawValue,
                accountCategoryLabel: account.category.rawValue,
                symbol: Symbol(ticker: ticker),
                side: side,
                mode: mapTradeMode(from: account),
                quantity: quantity,
                entryPrice: Self.parseDecimal(entryPriceText),
                exitPrice: Self.parseDecimal(exitPriceText),
                entryAt: entryAt,
                exitAt: includeExitTime ? exitAt : nil,
                realizedPnL: Money(amount: pnl),
                riskReward: Self.parseOptionalRiskReward(rrText),
                points: Self.parseDecimal(pointsText) ?? 0,
                sessionLabel: sessionLabel,
                strategy: Self.nilIfEmpty(strategyText),
                visibility: shareToProfile ? .public : .private,
                publicCaption: Self.nilIfEmpty(publicCaptionText),
                noteBody: Self.nilIfEmpty(notesText),
                imageURL: imageURL
            )

            let trade: Trade
            if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
                if let previous = editingTrade {
                    trade = Self.fixtureUpdatedTrade(from: draft, previous: previous)
                } else {
                    trade = Self.fixtureTrade(from: draft, owner: viewerID)
                }
            } else if let previous = editingTrade {
                trade = try await trades.update(id: previous.id, draft: draft, previous: previous)
            } else {
                trade = try await trades.save(draft)
            }

            detailCache.seed(trade)
            if isEditing {
                TradeJournalMutationStore.shared.noteUpdated(trade)
            } else {
                TradeJournalMutationStore.shared.noteCreated(trade)
            }
            Self.lastAccountID = account.id

            do {
                try await attachClipIfNeeded(to: trade.id, tradeIsPublic: shareToProfile)
            } catch {
                tradeAwaitingClip = trade.id
                phase = .ready
                formError = "Trade was saved, but the clip didn’t finish. Tap Save to retry the clip only."
                saveTask = nil
                return
            }

            ExperienceHaptics.play(.tradeSaved)
            phase = .ready
            onDismiss()
        } catch {
            isUploadingMedia = false
            if let path = uploadedStoragePath {
                try? await objectStorage.delete(
                    bucket: StorageBucket.screenshots.rawValue,
                    path: path
                )
            }
            phase = .ready
            formError = Self.userMessage(for: error)
        }
        saveTask = nil
    }

    private func loadUnattachedReels() async {
        isLoadingReels = true
        defer { isLoadingReels = false }
        guard let viewerID else { return }
        if viewerID.rawValue.hasPrefix("dev.") {
            unattachedReels = AddTradeFixtures.unattachedReels(owner: viewerID)
            return
        }
        do {
            unattachedReels = try await feed.unattachedReels(for: viewerID, limit: 30)
        } catch {
            unattachedReels = []
        }
    }

    private func attachClipIfNeeded(to tradeID: TradeID, tradeIsPublic: Bool) async throws {
        if let draft = reelDraft {
            try await publishReelDraft(draft, tradeID: tradeID, tradeIsPublic: tradeIsPublic)
            return
        }
        try await linkReelIfNeeded(to: tradeID)
    }

    private func publishReelDraft(
        _ draft: ReelDraft,
        tradeID: TradeID,
        tradeIsPublic: Bool
    ) async throws {
        guard let viewerID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        isUploadingMedia = true
        defer { isUploadingMedia = false }

        if viewerID.rawValue.hasPrefix("dev.") {
            let reel = CreateReelFixtures.sampleReel(author: viewerID, tradeID: tradeID)
            detailCache.seed(reel)
            OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
            return
        }

        let reel = try await ReelPublishPipeline.publish(
            draft: draft,
            authorID: viewerID,
            tradeID: tradeID,
            tradeIsPublic: tradeIsPublic,
            feed: feed,
            uploadService: uploadService,
            objectStorage: objectStorage
        )
        detailCache.seed(reel)
        OwnerProfileOptimisticStore.shared.noteReelCreated(reel)
    }

    private func linkReelIfNeeded(to tradeID: TradeID) async throws {
        guard let reel = linkedReel else { return }
        if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
            ContentMutationStore.shared.noteReelLinked(reel.id)
            return
        }
        if try await feed.tradeHasAttachedReel(tradeID) {
            throw AppError.domain(.conflict(message: "This trade already has a clip attached."))
        }
        try await feed.attachReel(id: reel.id, to: tradeID)
        ContentMutationStore.shared.noteReelLinked(reel.id)
    }

    private func validate() -> Bool {
        var errors: [Field: String] = [:]
        let ticker = symbolText.trimmingCharacters(in: .whitespacesAndNewlines)
        if ticker.isEmpty {
            errors[.symbol] = "Symbol is required"
        }
        let keepOriginalAccount = isEditing && selectedAccountID == editingOriginalAccountID
        if selectedAccountID == nil
            || (selectedAccount?.canAddTrades != true && !keepOriginalAccount)
        {
            formError = "Choose an eligible trading account."
        }
        if Self.parseDecimal(contractsText) == nil {
            errors[.contracts] = "Enter a valid contract count"
        }
        if !pnlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseDecimal(pnlText) == nil
        {
            errors[.pnl] = "Enter a valid P&L"
        }
        if !rrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseOptionalRiskReward(rrText) == nil
        {
            errors[.rr] = "Enter a valid R:R"
        }
        if !entryPriceText.isEmpty, Self.parseDecimal(entryPriceText) == nil {
            errors[.entry] = "Invalid entry price"
        }
        if !exitPriceText.isEmpty, Self.parseDecimal(exitPriceText) == nil {
            errors[.exit] = "Invalid exit price"
        }
        if includeExitTime, exitAt < entryAt {
            formError = formError ?? "Exit time must be after entry time."
        }
        if entryAt > Date().addingTimeInterval(60) {
            formError = formError ?? "Entry time can't be in the future."
        }
        fieldErrors = errors
        return errors.isEmpty && formError == nil
    }

    private struct UploadedScreenshot {
        var storagePath: String
        var publicURL: String
    }

    private func uploadScreenshot(_ data: Data) async throws -> UploadedScreenshot {
        guard let viewerID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        let path = "\(viewerID.rawValue)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let reference = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.screenshots.rawValue,
                path: path,
                data: data,
                contentType: "image/jpeg",
                purpose: .tradeScreenshot
            )
        )
        let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.screenshots.rawValue,
            path: reference.id
        )?.absoluteString ?? reference.id
        return UploadedScreenshot(storagePath: reference.id, publicURL: publicURL)
    }

    #if DEBUG
    func applyScreenshotFixture() {
        symbolText = "MNQ"
        side = .long
        entryPriceText = "21452.25"
        exitPriceText = "21468.75"
        contractsText = "2"
        pnlText = "660"
        rrText = "2.35"
        pointsText = "16.5"
        strategyText = "Opening Range Breakout"
        notesText = "Waited for confirmation above VWAP."
        shareToProfile = false
    }

    func applyScreenshotMediaFixture() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360))
        let image = renderer.image { context in
            UIColor(red: 0.05, green: 0.12, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            UIColor.systemGreen.setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 40, y: 260))
            path.addLine(to: CGPoint(x: 180, y: 200))
            path.addLine(to: CGPoint(x: 320, y: 220))
            path.addLine(to: CGPoint(x: 480, y: 120))
            path.addLine(to: CGPoint(x: 600, y: 90))
            path.lineWidth = 3
            path.stroke()
        }
        setScreenshot(image)
    }
    #endif

    private func mapTradeMode(from account: TradingAccount) -> TradeMode {
        switch account.mode {
        case .backtest: return .backtest
        case .sim: return .sim
        default: return .live
        }
    }

    private static func nilIfEmpty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDecimal(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cleaned = trimmed
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "+", with: "")
        return DecimalParser.parse(cleaned)
    }

    private static func prepareScreenshotJPEG(_ image: UIImage) -> Data? {
        MediaImagePreparation.jpegData(from: image)
    }

    private static func fixtureTrade(from draft: TradeDraft, owner: ProfileID) -> Trade {
        Trade(
            id: TradeID("dev.addtrade.\(UUID().uuidString)"),
            ownerProfileID: owner,
            accountID: draft.accountID,
            symbol: draft.symbol,
            side: draft.side,
            mode: draft.mode,
            quantity: draft.quantity,
            entryPrice: draft.entryPrice,
            exitPrice: draft.exitPrice,
            entryAt: draft.entryAt,
            exitAt: draft.exitAt,
            realizedPnL: draft.realizedPnL,
            riskReward: draft.riskReward,
            points: draft.points,
            sessionLabel: draft.sessionLabel,
            visibility: draft.visibility,
            publicCaption: draft.publicCaption,
            thumbnail: draft.imageURL.map { MediaReference(id: $0, kind: .image, altText: nil) },
            notePreview: draft.noteBody.map { String($0.prefix(140)) },
            strategy: draft.strategy,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private static func fixtureUpdatedTrade(from draft: TradeDraft, previous: Trade) -> Trade {
        var trade = previous
        trade.accountID = draft.accountID
        trade.symbol = draft.symbol
        trade.side = draft.side
        trade.mode = draft.mode
        trade.quantity = draft.quantity
        trade.entryPrice = draft.entryPrice
        trade.exitPrice = draft.exitPrice
        trade.entryAt = draft.entryAt
        trade.exitAt = draft.exitAt
        trade.realizedPnL = draft.realizedPnL
        trade.riskReward = draft.riskReward
        trade.points = draft.points
        trade.sessionLabel = draft.sessionLabel
        trade.visibility = draft.visibility
        trade.publicCaption = draft.publicCaption
        trade.thumbnail = draft.imageURL.map { MediaReference(id: $0, kind: .image, altText: nil) }
        trade.notePreview = draft.noteBody.map { String($0.prefix(140)) }
        trade.strategy = draft.strategy
        trade.updatedAt = .now
        return trade
    }

    private static func userMessage(for error: Error) -> String {
        if let domain = error as? DomainError {
            switch domain {
            case .tradeValidation(let v):
                switch v {
                case .missingSymbol: return "Symbol is required."
                case .accountRequired: return "Choose a trading account."
                case .accountReadOnly: return "This account is read-only."
                case .exitBeforeEntry: return "Exit time must be after entry."
                case .invalidQuantity: return "Invalid contracts."
                case .invalidPrice: return "Invalid price."
                case .unsupportedMode: return "Unsupported account mode."
                case .message(let m): return m
                }
            case .businessRule(.dailyLimitExceeded(let cap)):
                return "Free plan daily trade limit reached (\(cap)/day)."
            case .permission(.notAuthenticated):
                return "Sign in to add trades."
            default:
                break
            }
        }
        let text = String(describing: error).lowercased()
        if text.contains("daily") || text.contains("free_plan") {
            return "Free plan daily trade limit reached (\(FreeTierPolicy.dailyTradeLimit)/day)."
        }
        if text.contains("can_add_trades") || text.contains("read_only") || text.contains("accountreadonly") {
            return "This account can't accept new trades."
        }
        return "Couldn't save trade. Check your connection and try again."
    }
}

extension DetailPresentationCache {
    fileprivate func recentTradeTickers(limit: Int) -> [String] {
        _ = limit
        return []
    }
}
