import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AddTradeViewModel {
    /// Sentinel ``Picker`` tag — not a real account id (Add Trade account menu only).
    static let addAccountPickerTag = "__add_trade_add_account__"
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
        case account
        case symbol
        case strategy
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
    var showsVideoTooLongAlert = false
    private(set) var isUploadingMedia = false

    var symbolText = ""
    var side: TradeSide = .long
    var entryPriceText = ""
    var exitPriceText = ""
    var contractsText = ""
    var pnlText = ""
    var pointsText = ""
    var rrText = ""
    var entryAt: Date = .now
    var exitAt: Date = .now
    var includeExitTime = false
    var strategyText = ""
    var notesText = ""
    var timeframeSelection = ""
    var customTimeframeText = ""
    var newsEvent = false
    var confidenceLevel = 0
    var emotionSelection = ""
    var followedPlan = false
    var marketConditionSelection = ""
    var psychologyNotesText = ""
    var screenshotDisplayMode: TradeScreenshotDisplayMode = .fit
    var publicCaptionText = ""
    var shareToProfile = false
    var screenshotData: Data?
    var screenshotPreview: UIImage?
    var hasScreenshotPreview: Bool { screenshotPreview != nil }

    var hasScreenshotAttached: Bool {
        screenshotPreview != nil || (existingImageURL != nil && !removeExistingScreenshot)
    }

    var computedHoldDurationLabel: String? {
        guard includeExitTime else { return nil }
        return TradeHoldDuration.compute(entryAt: entryAt, exitAt: exitAt)?.text
    }

    /// Local new-clip draft — uploaded + inserted with `trade_id` after trade save.
    var reelDraft: ReelDraft?
    private(set) var isPreparingClipVideo = false
    /// Secondary path: link an already-uploaded unattached clip (`reels.trade_id`).
    var linkedReel: Reel?
    private(set) var unattachedReels: [Reel] = []
    private(set) var isLoadingReels = false
    /// Trade saved but clip create/link failed — retry clip only (no duplicate trade).
    private(set) var tradeAwaitingClip: TradeID?
    /// After create save — optional post-trade reflection before dismiss.
    private(set) var pendingPostTradeReflection: Trade?
    /// Back-compat alias used by older tests / UI identifiers.
    var tradeAwaitingReelLink: TradeID? { tradeAwaitingClip }

    private let trades: any TradeRepository
    private let tradeDetailRepository: any TradeDetailRepository
    private let feed: any FeedRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let uploadService: any UploadService
    private let objectStorage: any ObjectStorageProviding
    private let uploadServices: GlobalUploadServices
    private let imagePipeline: (any ImagePipeline)?
    var clipLinkImagePipeline: (any ImagePipeline)? { imagePipeline }
    var clipLinkObjectStorage: any ObjectStorageProviding { objectStorage }
    private let copyTradingGroups: (any CopyTradingGroupRepository)?
    private let contentDrafts: (any ContentDraftRepository)?
    private let onDismiss: () -> Void

    private var viewerID: ProfileID?
    private var saveTask: Task<Void, Never>?
    private var isEnqueueingTradeSave = false
    private var hasLoadedAccounts = false
    private var hasLoadedReels = false
    private var editingTrade: Trade?
    private var editingOriginalAccountID: TradingAccountID?
    private var existingImageURL: String?
    private var removeExistingScreenshot = false
    private var hydratedFingerprint: String?
    private static var lastAccountID: TradingAccountID?
    private(set) var copyGroups: [CopyTradingGroup] = []
    var selectedCopyGroupID: String?
    private(set) var isSavingDraft = false
    private var activeDraftID: UUID?
    private var retainedDraftImagePath: String?
    private var didClearDraftImage = false
    private var didRestoreDraftMedia = false

    #if DEBUG
    private(set) var lastProbe: AddTradeLoadProbe.Snapshot?
    #endif

    init(
        trades: any TradeRepository,
        tradeDetailRepository: any TradeDetailRepository,
        feed: any FeedRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        uploadServices: GlobalUploadServices,
        imagePipeline: (any ImagePipeline)? = nil,
        copyTradingGroups: (any CopyTradingGroupRepository)? = nil,
        contentDrafts: (any ContentDraftRepository)? = nil,
        restoredDraft: ContentDraft? = nil,
        mode: Mode = .create,
        onDismiss: @escaping () -> Void
    ) {
        self.trades = trades
        self.tradeDetailRepository = tradeDetailRepository
        self.feed = feed
        self.session = session
        self.detailCache = detailCache
        self.uploadService = uploadService
        self.objectStorage = objectStorage
        self.uploadServices = uploadServices
        self.imagePipeline = imagePipeline
        self.copyTradingGroups = copyTradingGroups
        self.contentDrafts = contentDrafts
        self.mode = mode
        self.onDismiss = onDismiss
        if let restoredDraft, restoredDraft.type == .trade, !isEditing {
            applyTradeDraft(restoredDraft)
        }
    }

    /// Tests and legacy call sites — constructs the default detail repository boundary.
    convenience init(
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
        self.init(
            trades: trades,
            tradeDetailRepository: DefaultTradeDetailRepository(
                trades: trades,
                session: session,
                detailCache: detailCache
            ),
            feed: feed,
            session: session,
            detailCache: detailCache,
            uploadService: uploadService,
            objectStorage: objectStorage,
            uploadServices: GlobalUploadServices(
                feed: feed,
                profiles: nil,
                trades: trades,
                achievements: nil,
                uploadService: uploadService,
                objectStorage: objectStorage,
                detailCache: detailCache
            ),
            imagePipeline: imagePipeline,
            mode: mode,
            onDismiss: onDismiss
        )
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
        ownerAccountSource().first(where: { $0.id == selectedAccountID })
    }

    /// Backtest accounts surface Strategy/Setup above direction in the Trade section.
    var prioritizesStrategySetupField: Bool {
        selectedAccount?.mode == .backtest
    }

    /// Accounts that may receive new trades: owned and active. Dropdown visibility is separate.
    var eligibleAccounts: [TradingAccount] {
        ownerAccountSource().filter(\.isActive)
    }

    var ineligibleAccounts: [TradingAccount] {
        ownerAccountSource().filter { !$0.isActive }
    }

    /// Picker list — active accounts toggled ON in Settings (`show_in_account_dropdowns`).
    var accountsForPicker: [TradingAccount] {
        let preserveID = isEditing ? editingOriginalAccountID : selectedAccountID
        let tier = viewerID.map { TradeEntryEntitlementGate.viewerTier(profileID: $0) } ?? .free
        return TradingAccountDropdownFilter.visibleForManualTradePicker(
            from: ownerAccountSource(),
            preservingSelection: preserveID,
            tradeEntryAllowed: {
                TradeEntryEntitlementGate.accountAllowsNewTrade($0, viewerTier: tier)
            }
        )
    }

    private func ownerAccountSource() -> [TradingAccount] {
        let resolved = OwnerAccountDropdownSupport.resolvedAccounts(
            profileID: viewerID,
            fallback: accounts,
            detailCache: detailCache
        )
        return resolved.isEmpty ? accounts : resolved
    }


    /// SwiftUI `Picker` tag — must match a row in ``accountsForPicker`` (avoids stale selection warnings).
    var accountPickerSelectionTag: String {
        let visible = Set(accountsForPicker.map(\.id.rawValue))
        guard let raw = selectedAccountID?.rawValue, visible.contains(raw) else { return "" }
        return raw
    }

    private(set) var instrumentCatalogRevision = 0

    var ownerAccountsProfileID: ProfileID? { viewerID }

    var instrumentPickerSnapshot: InstrumentPickerSnapshot {
        if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
            return AddTradeFixtures.instrumentPickerSnapshot
        }
        guard let viewerID else { return .empty }
        return InstrumentCatalog.pickerSnapshot(for: viewerID, detailCache: detailCache)
    }

    var recentSymbols: [String] {
        instrumentPickerSnapshot.mostUsed
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
            || !psychologyNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !timeframeSelection.isEmpty
            || newsEvent
            || confidenceLevel > 0
            || !emotionSelection.isEmpty
            || followedPlan
            || !marketConditionSelection.isEmpty
            || !rrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || screenshotData != nil
            || reelDraft != nil
            || linkedReel != nil
            || !contractsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var hasPsychologyDetails: Bool {
        TradeReviewCatalog.hasPsychologyDetails(
            confidence: confidenceLevel,
            emotion: emotionSelection,
            followedPlan: followedPlan,
            marketCondition: marketConditionSelection,
            psychologyNotes: psychologyNotesText
        )
    }

    var psychologySummary: String {
        TradeReviewCatalog.psychologySummary(
            confidence: confidenceLevel,
            emotion: emotionSelection,
            followedPlan: followedPlan,
            marketCondition: marketConditionSelection,
            psychologyNotes: psychologyNotesText
        )
    }

    func copyNotesToCaption() {
        let notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return }
        publicCaptionText = notesText
    }

    /// Web stores `trades.rr` as a decimal ratio (e.g. `2.35`); UI shows `1 : 2.35`.
    var riskRewardDisplay: String {
        guard let value = Self.parseDecimal(rrText, style: .riskReward) else {
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

    /// Web `parseOptionalRr` — finite number, blank → nil. Accepts `1:2.35` reward-multiple input.
    static func parseOptionalRiskReward(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let colon = trimmed.firstIndex(of: ":") {
            let reward = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return parseDecimal(reward, style: .riskReward)
        }
        return parseDecimal(trimmed, style: .riskReward)
    }

    static func formatRiskReward(_ value: Decimal) -> String {
        "1 : \(NumberDisplay.decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 2))"
    }

    func loadIfNeeded() {
        guard !hasLoadedAccounts else { return }
        hasLoadedAccounts = true
        Task {
            await loadAccounts()
            await loadCopyTradingGroupsIfNeeded()
        }
    }

    func retryLoad() {
        hasLoadedAccounts = false
        loadIfNeeded()
    }

    func selectAccount(_ id: TradingAccountID) {
        guard ownerAccountSource().contains(where: { $0.id == id }) else { return }
        guard accountsForPicker.contains(where: { $0.id == id }) else { return }
        let keepOriginal = isEditing && id == editingOriginalAccountID
        ExperienceHaptics.play(.selection)
        selectedAccountID = id
        if keepOriginal || viewerID != nil {
            Self.lastAccountID = id
            fieldErrors[.account] = nil
        }
    }

    func clearAccountSelection() {
        selectedAccountID = nil
        fieldErrors[.account] = nil
    }

    var showsCopyGroupPicker: Bool {
        !isEditing && !copyGroups.isEmpty
    }

    var selectedCopyGroup: CopyTradingGroup? {
        guard !isEditing else { return nil }
        return copyGroups.first(where: { $0.id == selectedCopyGroupID })
    }

    /// Copy-group membership in sort order — not filtered by `can_add_trades` or dropdown visibility.
    func resolvedCopyGroupAccounts(_ group: CopyTradingGroup) -> [TradingAccount] {
        let source = ownerAccountSource()
        let byID = Dictionary(uniqueKeysWithValues: source.map { ($0.id.rawValue, $0) })
        return group.accountIDs.compactMap { byID[$0] }.filter(\.isActive)
    }

    func resolvedCopyAccounts(_ group: CopyTradingGroup) -> [TradingAccount] {
        resolvedCopyGroupAccounts(group)
    }

    func selectCopyGroup(_ groupID: String?) {
        if let groupID, !groupID.isEmpty {
            if ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: viewerID) {
                selectedCopyGroupID = nil
                return
            }
        }
        selectedCopyGroupID = groupID
        fieldErrors[.account] = nil
        guard let group = selectedCopyGroup else { return }
        let members = resolvedCopyGroupAccounts(group)
        guard let first = members.first else { return }
        selectedAccountID = first.id
        if let viewerID,
           TradeEntryEntitlementGate.accountAllowsNewTrade(
               first,
               viewerTier: TradeEntryEntitlementGate.viewerTier(profileID: viewerID)
           )
        {
            Self.lastAccountID = first.id
        }
        syncAccountFieldErrorForCopyGroup(members)
    }

    func loadCopyTradingGroupsIfNeeded() async {
        guard !isEditing, copyGroups.isEmpty, let copyTradingGroups, let viewerID,
              !viewerID.rawValue.hasPrefix("dev.")
        else { return }
        copyGroups = (try? await copyTradingGroups.groups(for: viewerID)) ?? []
    }

    func addExitTime() {
        includeExitTime = true
        if exitAt < entryAt {
            exitAt = entryAt
        }
    }

    func removeExitTime() {
        includeExitTime = false
    }

    var hasTradeReviewContent: Bool {
        !strategyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !timeframeSelection.isEmpty
            || !customTimeframeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || newsEvent
            || hasPsychologyDetails
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
        applySymbol(normalized)
        if let viewerID {
            InstrumentCatalog.registerCustom(normalized, for: viewerID)
            instrumentCatalogRevision &+= 1
        }
    }

    func deleteCustomInstrument(_ ticker: String) {
        guard let viewerID else { return }
        InstrumentCatalog.removeCustom(ticker, for: viewerID)
        instrumentCatalogRevision &+= 1
        ExperienceHaptics.play(.selection)
    }

    func setScreenshot(_ result: ImageCropSelectionResult) {
        guard let applied = ComposerCropImageState.apply(result) else { return }
        screenshotPreview = applied.finalImage
        screenshotData = applied.uploadData
        screenshotDisplayMode = .fit
        removeExistingScreenshot = false
    }

    func setScreenshot(_ image: UIImage?) {
        guard let image else {
            clearScreenshot()
            return
        }
        let pixelSize = MediaImageOrientation.pixelSize(of: image)
        setScreenshot(
            ImageCropSelectionResult(
                image: image,
                aspectMode: .original,
                sourcePixelSize: pixelSize
            )
        )
    }

    func clearScreenshot() {
        screenshotData = nil
        screenshotPreview = nil
        didClearDraftImage = true
        if existingImageURL != nil {
            removeExistingScreenshot = true
        }
    }

    func applyClipVideo(from url: URL, contentType: String?) {
        formError = nil
        Task {
            do {
                try await VideoUploadDurationValidation.validateReelUploadDuration(at: url)
                isPreparingClipVideo = true
                let prepared = try await ReelEncodingPipeline.prepareForUpload(
                    from: url,
                    contentType: contentType
                )
                linkedReel = nil
                reelDraft = ReelDraft(
                    selectionID: UUID().uuidString,
                    ownedSourceURL: nil,
                    localVideoURL: prepared.fileURL,
                    videoAssetState: .preparedDelivery,
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
                if VideoUploadDurationValidation.isTooLong(error) {
                    showsVideoTooLongAlert = true
                } else {
                    formError = Self.userMessage(for: error)
                }
            }
            isPreparingClipVideo = false
        }
    }

    func clearReelDraft() {
        if let url = reelDraft?.localVideoURL {
            MediaVideoPreparation.cleanupTemporaryFile(at: url)
        }
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
        let createdID = AccountMutationStore.shared.latestAccountID
        Task {
            if let cached = SessionAccountsStore.shared.cached(for: viewerID)
                ?? detailCache.accounts(for: viewerID)
            {
                accounts = cached
            } else {
                await refreshAccountsFromNetwork(viewerID: viewerID, forceNetwork: true)
            }
            applyAccountSelectionAfterReload(preferredID: createdID)
        }
    }

    /// Opens Manage Accounts in the tab stack (only works when Add Trade is not covering the shell).
    func openManageAccounts() {
        NavigationCoordinatorProxy.openManageAccounts?()
    }

    /// True when the user has no trading accounts at all (not merely ineligible for entry).
    var hasNoTradingAccounts: Bool { accounts.isEmpty }

    private func applyAccountSelectionAfterReload(preferredID: TradingAccountID?) {
        reconcileAccountSelection(preferredID: preferredID)
    }

    /// Create mode: keep a visible picker selection. Edit mode preserves the trade's account.
    private func reconcileAccountSelection(preferredID: TradingAccountID? = nil) {
        if isEditing {
            if selectedAccountID == nil, let original = editingOriginalAccountID {
                selectedAccountID = original
            }
            syncAccountFieldErrorForCurrentSelection()
            return
        }

        if let group = selectedCopyGroup {
            let members = resolvedCopyGroupAccounts(group)
            if members.isEmpty {
                selectedCopyGroupID = nil
            } else if let first = members.first {
                selectedAccountID = first.id
                if let viewerID,
                   TradeEntryEntitlementGate.accountAllowsNewTrade(
                       first,
                       viewerTier: TradeEntryEntitlementGate.viewerTier(profileID: viewerID)
                   )
                {
                    Self.lastAccountID = first.id
                }
                syncAccountFieldErrorForCopyGroup(members)
                return
            }
        }

        let pickerRows = accountsForPicker
        func isVisibleInPicker(_ id: TradingAccountID) -> Bool {
            pickerRows.contains(where: { $0.id == id })
        }

        if let preferredID, isVisibleInPicker(preferredID) {
            selectedAccountID = preferredID
            syncAccountFieldErrorForCurrentSelection()
            Self.lastAccountID = preferredID
            return
        }

        if let current = selectedAccountID, isVisibleInPicker(current) {
            syncAccountFieldErrorForCurrentSelection()
            return
        }

        if let last = Self.lastAccountID, isVisibleInPicker(last) {
            selectedAccountID = last
            syncAccountFieldErrorForCurrentSelection()
            Self.lastAccountID = last
            return
        }

        if let firstVisible = pickerRows.first {
            selectedAccountID = firstVisible.id
            Self.lastAccountID = firstVisible.id
            fieldErrors[.account] = nil
        } else {
            clearAccountSelection()
        }
    }

    private func syncAccountFieldErrorForCurrentSelection() {
        if let group = selectedCopyGroup {
            syncAccountFieldErrorForCopyGroup(resolvedCopyGroupAccounts(group))
            return
        }
        guard selectedAccount != nil, viewerID != nil else {
            fieldErrors[.account] = nil
            return
        }
        fieldErrors[.account] = nil
    }

    private func syncAccountFieldErrorForCopyGroup(_ members: [TradingAccount]) {
        guard let viewerID else {
            fieldErrors[.account] = nil
            return
        }
        if let message = TradeEntryEntitlementGate.validateAccountsForNewTrades(members, profileID: viewerID) {
            fieldErrors[.account] = message
        } else {
            fieldErrors[.account] = nil
        }
    }

    private func validateCopyGroupBeforeSave(_ group: CopyTradingGroup) -> String? {
        let members = resolvedCopyGroupAccounts(group)
        guard members.count >= CopyTradingGroupRules.minimumAccounts else {
            return "This copy trading group has no linked accounts."
        }
        guard let viewerID else { return "Sign in to add trades." }
        return TradeEntryEntitlementGate.validateAccountsForNewTrades(members, profileID: viewerID)
    }

    #if DEBUG
    func applyClipDraftFixture() {
        reelDraft = CreateReelFixtures.screenshotDraft()
        linkedReel = nil
    }
    #endif

    func save() {
        guard canSave, saveTask == nil, !isEnqueueingTradeSave else { return }
        isEnqueueingTradeSave = true
        phase = .saving
        saveTask = Task {
            await enqueueSave()
            isEnqueueingTradeSave = false
        }
    }

    static func rememberLastAccountID(_ id: TradingAccountID) {
        lastAccountID = id
    }

    #if DEBUG
    static func resetSessionDefaultsForTesting() {
        lastAccountID = nil
    }
    #endif

    static func devFixtureTrade(from draft: TradeDraft, owner: ProfileID) -> Trade {
        fixtureTrade(from: draft, owner: owner)
    }

    static func devFixtureUpdatedTrade(from draft: TradeDraft, previous: Trade) -> Trade {
        fixtureUpdatedTrade(from: draft, previous: previous)
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
            guard await hydrateEditTradeIfNeeded() else { return }
            reconcileAccountSelection()
            await restorePendingDraftMediaIfNeeded()
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
            let sessionKind = SessionAccountsStore.shared.snapshotKind(for: viewerID)
            let needsFullOwnerSnapshot = sessionKind == .dashboard
            let needsRefresh = needsFullOwnerSnapshot
                || (sessionKind == .rest && !SessionAccountsStore.shared.isFresh(for: viewerID))
            if needsRefresh {
                await refreshAccountsFromNetwork(
                    viewerID: viewerID,
                    forceNetwork: needsFullOwnerSnapshot
                )
            }
            guard await hydrateEditTradeIfNeeded() else { return }
            reconcileAccountSelection()
            await restorePendingDraftMediaIfNeeded()
            phase = .ready
            #if DEBUG
            AddTradeLoadProbe.noteRequest(needsRefresh ? "accountsCache+rest" : "accountsCache", blocking: needsRefresh)
            lastProbe = AddTradeLoadProbe.usableForm(loaded: ["accountsCache"])
            #endif
            return
        }

        await refreshAccountsFromNetwork(viewerID: viewerID, forceNetwork: false)
        guard await hydrateEditTradeIfNeeded() else { return }
        reconcileAccountSelection()
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
                forceNetwork: forceNetwork,
                requiresFullOwnerSnapshot: true
            )
            accounts = loaded
            reconcileAccountSelection()
            await restorePendingDraftMediaIfNeeded()
            phase = .ready
        } catch {
            if accounts.isEmpty {
                phase = .failed("Couldn't load trading accounts.")
            } else {
                reconcileAccountSelection()
                await restorePendingDraftMediaIfNeeded()
                phase = .ready
            }
        }
    }

    @discardableResult
    private func hydrateEditTradeIfNeeded() async -> Bool {
        guard case .edit(let tradeID) = mode else { return true }
        do {
            let trade: Trade
            if let cached = detailCache.authoritativeDetail(id: tradeID) {
                trade = cached
            } else if let viewerID, viewerID.rawValue.hasPrefix("dev.") {
                if let seeded = detailCache.trade(id: tradeID) {
                    trade = seeded
                } else {
                    throw AppError.unknown(message: "Trade not found")
                }
            } else {
                trade = try await tradeDetailRepository.load(
                    tradeID: tradeID,
                    policy: .default
                )
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
        entryPriceText = Self.decimalFieldText(trade.entryPrice, style: .tradePrice)
        exitPriceText = Self.decimalFieldText(trade.exitPrice, style: .tradePrice)
        contractsText = Self.decimalFieldText(trade.quantity, style: .tradeQuantity)
        pnlText = Self.decimalFieldText(trade.realizedPnL?.amount, style: .signedPnL)
        pointsText = Self.decimalFieldText(trade.points, style: .tradeQuantity)
        rrText = Self.decimalFieldText(trade.riskReward, style: .riskReward)
        entryAt = trade.entryAt
        if let exit = trade.exitAt {
            exitAt = exit
            includeExitTime = true
        } else {
            exitAt = trade.entryAt
            includeExitTime = false
        }
        strategyText = trade.strategy ?? ""
        notesText = trade.notes ?? trade.notePreview ?? ""
        let timeframeParts = TradeReviewCatalog.timeframeSelection(for: trade.timeframe)
        timeframeSelection = timeframeParts.selection
        customTimeframeText = timeframeParts.custom
        newsEvent = trade.newsEvent ?? false
        confidenceLevel = trade.confidence ?? 0
        emotionSelection = trade.emotion ?? ""
        followedPlan = trade.followedPlan ?? false
        marketConditionSelection = trade.marketCondition ?? ""
        psychologyNotesText = trade.psychologyNotes ?? ""
        screenshotDisplayMode = trade.imageDisplayMode
        publicCaptionText = trade.publicCaption ?? ""
        shareToProfile = trade.visibility == .public
        existingImageURL = trade.thumbnail?.id
        removeExistingScreenshot = false
        screenshotData = nil
        hydratedFingerprint = formFingerprint
    }

    #if DEBUG
    func applyTradeForTesting(_ trade: Trade) {
        apply(trade: trade)
    }
    #endif

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
            timeframeSelection,
            customTimeframeText,
            newsEvent ? "1" : "0",
            String(confidenceLevel),
            emotionSelection,
            followedPlan ? "1" : "0",
            marketConditionSelection,
            psychologyNotesText,
            screenshotDisplayMode.rawValue,
            publicCaptionText,
            shareToProfile ? "1" : "0",
        ].joined(separator: "|")
    }

    private static func decimalFieldText(_ value: Decimal?, style: NumericInputStyle) -> String {
        guard let value else { return "" }
        return decimalFieldText(value, style: style)
    }

    private static func decimalFieldText(_ value: Decimal, style: NumericInputStyle) -> String {
        NumericInputFieldSupport.seedEditingText(from: value, style: style)
    }

    private func enqueueSave() async {
        formError = nil
        fieldErrors = [:]

        guard validate() else {
            phase = .ready
            saveTask = nil
            return
        }
        let accountForSave: TradingAccount?
        if let group = selectedCopyGroup {
            if let block = validateCopyGroupBeforeSave(group) {
                fieldErrors[.account] = block
                phase = .ready
                saveTask = nil
                return
            }
            accountForSave = resolvedCopyGroupAccounts(group).first
        } else {
            accountForSave = selectedAccount
        }
        guard let account = accountForSave else {
            fieldErrors[.account] = selectedCopyGroup == nil
                ? "Choose Account."
                : "This copy trading group has no linked accounts."
            phase = .ready
            saveTask = nil
            return
        }
        guard let viewerID else {
            formError = isEditing ? "Sign in to edit trades." : "Sign in to add trades."
            phase = .ready
            saveTask = nil
            return
        }
        guard let spec = makeTradeSaveUploadSpec(viewerID: viewerID, account: account) else {
            phase = .ready
            saveTask = nil
            return
        }

        if spec.draft.copyTradingPlan != nil,
           ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: viewerID)
        {
            phase = .ready
            saveTask = nil
            return
        }

        var checkpoint = TradeSaveUploadCheckpoint(
            uploadedScreenshotPublicURL: nil,
            uploadedScreenshotStoragePath: nil,
            savedTradeID: tradeAwaitingClip,
            clipAttached: false,
            reelLinked: false,
            publicFeedPostCompleted: false,
            reelVideoPublicURL: nil,
            reelVideoStoragePath: nil,
            reelThumbnailPublicURL: nil,
            reelThumbnailStoragePath: nil,
            linkedExistingReelID: nil
        )
        if tradeAwaitingClip != nil {
            checkpoint.clipAttached = false
        }

        if let screenshotData, let screenshotPreview {
            PostImageUploadProbe.log(finalImage: screenshotPreview, uploadData: screenshotData)
        }

        let jobID = GlobalUploadCoordinator.shared.enqueueTrade(
            spec: spec,
            services: uploadServices,
            checkpoint: checkpoint
        )
        if let activeDraftID, let contentDrafts {
            ContentDraftPublicationCleanup.shared.track(
                jobID: jobID,
                draftID: activeDraftID,
                repository: contentDrafts
            )
        }

        tradeAwaitingClip = nil
        reelDraft = nil
        linkedReel = nil
        screenshotData = nil
        screenshotPreview = nil
        phase = .ready
        saveTask = nil
        onDismiss()
        GlobalUploadJobDiagnostics.log(
            id: jobID,
            kind: .trade,
            event: .composerDismissed,
            taskCancelled: Task.isCancelled
        )
    }

    private func makeTradeSaveUploadSpec(
        viewerID: ProfileID,
        account: TradingAccount
    ) -> TradeSaveUploadSpec? {
        let ticker = symbolText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let quantity = Self.parseDecimal(contractsText, style: .tradeQuantity) else { return nil }
        let pnl = Self.parseDecimal(pnlText, style: .signedPnL) ?? 0
        let sessionLabel = TradingSessionLabel.session(from: entryAt) ?? "NY"
        let resolvedTimeframe = TradeReviewCatalog.resolvedTimeframe(
            selection: timeframeSelection,
            custom: customTimeframeText
        )
        let holdDuration = includeExitTime
            ? TradeHoldDuration.compute(entryAt: entryAt, exitAt: exitAt)
            : nil
        var draft = TradeDraft(
            accountID: account.id,
            accountName: account.name,
            accountSizeLabel: account.size.map { "\($0.amount)" },
            accountModeLabel: account.mode.rawValue,
            accountCategoryLabel: account.category.rawValue,
            ownerAccountNumber: account.accountNumber,
            ownerAccountCategory: account.category,
            ownerAccountMode: account.mode,
            symbol: Symbol(ticker: ticker),
            side: side,
            mode: mapTradeMode(from: account),
            quantity: quantity,
            entryPrice: Self.parseDecimal(entryPriceText, style: .tradePrice),
            exitPrice: Self.parseDecimal(exitPriceText, style: .tradePrice),
            entryAt: entryAt,
            exitAt: includeExitTime ? exitAt : nil,
            realizedPnL: Money(amount: pnl),
            riskReward: Self.parseOptionalRiskReward(rrText),
            points: Self.parseDecimal(pointsText, style: .tradeQuantity) ?? 0,
            sessionLabel: sessionLabel,
            strategy: Self.nilIfEmpty(strategyText),
            visibility: shareToProfile ? .public : .private,
            publicCaption: Self.nilIfEmpty(publicCaptionText),
            noteBody: Self.nilIfEmpty(notesText),
            timeframe: resolvedTimeframe,
            newsEvent: newsEvent,
            confidence: confidenceLevel > 0 ? confidenceLevel : nil,
            emotion: Self.nilIfEmpty(emotionSelection),
            followedPlan: followedPlan,
            marketCondition: Self.nilIfEmpty(marketConditionSelection),
            psychologyNotes: Self.nilIfEmpty(psychologyNotesText),
            imageDisplayMode: screenshotDisplayMode,
            durationSeconds: holdDuration?.seconds,
            durationText: holdDuration?.text,
            imageURL: nil,
            imageCrop: nil
        )
        if let group = selectedCopyGroup {
            let members = resolvedCopyAccounts(group)
            if !members.isEmpty {
                draft.copyTradingPlan = CopyTradingSavePlan(
                    groupID: group.id,
                    accounts: members.map(copyStamp(for:))
                )
                draft.mode = .copyTraded
            }
        }

        let uploadMode: TradeSaveUploadMode = {
            if case .edit(let tradeID) = mode { return .edit(tradeID: tradeID) }
            return .create
        }()

        let jobID = UUID().uuidString
        let reelSnapshot: ReelDraftSnapshot? = {
            guard let reelDraft = reelDraft else { return nil }
            if reelDraft.videoAssetState == .preparedDelivery,
               let captured = try? ReelEncodingPipeline.captureUploadSnapshot(
                   from: reelDraft,
                   publishID: jobID,
                   captionOverride: nil
               )
            {
                return captured
            }
            return ReelDraftSnapshot(draft: reelDraft, captionOverride: nil)
        }()

        return TradeSaveUploadSpec(
            jobID: jobID,
            authorID: viewerID,
            mode: uploadMode,
            draft: draft,
            screenshotData: screenshotData,
            removeExistingScreenshot: removeExistingScreenshot,
            existingImageURL: existingImageURL,
            reelSnapshot: reelSnapshot,
            linkedReelID: linkedReel?.id,
            tradeIsPublic: shareToProfile,
            lastAccountID: account.id
        )
    }

    func skipPostTradeReflection() {
        pendingPostTradeReflection = nil
        onDismiss()
    }

    func savePostTradeReflection(exitEmotion: String?, executionRating: Int?) async {
        guard let trade = pendingPostTradeReflection else {
            onDismiss()
            return
        }
        guard exitEmotion != nil || executionRating != nil else {
            skipPostTradeReflection()
            return
        }

        var draft = tradeDraft(from: trade)
        draft.exitEmotion = exitEmotion
        draft.executionRating = executionRating

        do {
            let updated = try await trades.update(id: trade.id, draft: draft, previous: trade)
            detailCache.seedAuthoritativeDetail(updated, authority: .authoritativeMutation)
            Task { await tradeDetailRepository.replaceCachedDetail(updated, authority: .authoritativeMutation) }
            TradeJournalMutationStore.shared.noteUpdated(updated)
        } catch {
            formError = "Reflection didn't save. Your trade was still recorded."
        }
        pendingPostTradeReflection = nil
        onDismiss()
    }

    private func tradeDraft(from trade: Trade) -> TradeDraft {
        TradeDraft(
            accountID: trade.accountID,
            symbol: trade.symbol,
            side: trade.side,
            mode: trade.mode,
            quantity: trade.quantity,
            entryPrice: trade.entryPrice,
            exitPrice: trade.exitPrice,
            entryAt: trade.entryAt,
            exitAt: trade.exitAt,
            realizedPnL: trade.realizedPnL,
            riskReward: trade.riskReward,
            points: trade.points,
            sessionLabel: trade.sessionLabel,
            strategy: trade.strategy,
            visibility: trade.visibility,
            publicCaption: trade.publicCaption,
            noteBody: trade.notes,
            timeframe: trade.timeframe,
            newsEvent: trade.newsEvent ?? false,
            confidence: trade.confidence,
            emotion: trade.emotion,
            followedPlan: trade.followedPlan ?? false,
            marketCondition: trade.marketCondition,
            psychologyNotes: trade.psychologyNotes,
            exitEmotion: trade.exitEmotion,
            executionRating: trade.executionRating,
            imageDisplayMode: trade.imageDisplayMode,
            durationSeconds: trade.durationSeconds,
            durationText: trade.durationText,
            imageURL: trade.thumbnail?.id
        )
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

        if try await feed.tradeHasAttachedReel(tradeID) {
            throw AppError.domain(.conflict(message: "This trade already has a clip attached."))
        }

        let publishID = UUID().uuidString
        let reel = try await ReelPublishPipeline.publish(
            publishID: publishID,
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
        if prioritizesStrategySetupField,
           strategyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            errors[.strategy] = "Strategy / setup is required for backtest trades"
        }
        if let group = selectedCopyGroup {
            if let block = validateCopyGroupBeforeSave(group) {
                errors[.account] = block
            } else if resolvedCopyGroupAccounts(group).first(where: { $0.id == selectedAccountID }) == nil {
                errors[.account] = "Choose Account."
            }
        } else if selectedAccountID == nil {
            errors[.account] = "Choose Account."
        }
        if Self.parseDecimal(contractsText, style: .tradeQuantity) == nil {
            errors[.contracts] = "Enter a valid contract count"
        }
        if !pnlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseDecimal(pnlText, style: .signedPnL) == nil
        {
            errors[.pnl] = "Enter a valid P&L"
        }
        if !rrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Self.parseOptionalRiskReward(rrText) == nil
        {
            errors[.rr] = "Enter a valid R:R"
        }
        if !entryPriceText.isEmpty, Self.parseDecimal(entryPriceText, style: .tradePrice) == nil {
            errors[.entry] = "Invalid entry price"
        }
        if !exitPriceText.isEmpty, Self.parseDecimal(exitPriceText, style: .tradePrice) == nil {
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
        let path = StorageOptimizedMedia.objectPath(prefix: viewerID.rawValue, fileExtension: "jpg")
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

    private func copyStamp(for account: TradingAccount) -> CopyTradingAccountStamp {
        CopyTradingAccountStamp(
            accountID: account.id,
            name: account.name,
            sizeLabel: account.size.map { "\($0.amount)" },
            modeLabel: account.mode.rawValue,
            categoryLabel: account.category.rawValue,
            accountNumber: account.accountNumber,
            category: account.category,
            mode: account.mode
        )
    }

    private static func nilIfEmpty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDecimal(_ raw: String, style: NumericInputStyle = .signedPnL) -> Decimal? {
        NumericInputFieldSupport.parse(raw, style: style)
    }

    private static func prepareScreenshotJPEG(_ image: UIImage, logUpload: Bool = false) -> Data? {
        MediaImagePreparation.jpegData(from: image, logUpload: logUpload)
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
            imageDisplayMode: draft.imageDisplayMode,
            notePreview: draft.noteBody.map { String($0.prefix(140)) },
            notes: draft.noteBody,
            strategy: draft.strategy,
            timeframe: draft.timeframe,
            newsEvent: draft.newsEvent,
            confidence: draft.confidence,
            emotion: draft.emotion,
            followedPlan: draft.followedPlan,
            marketCondition: draft.marketCondition,
            psychologyNotes: draft.psychologyNotes,
            durationText: draft.durationText,
            durationSeconds: draft.durationSeconds,
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
        trade.notes = draft.noteBody
        trade.strategy = draft.strategy
        trade.timeframe = draft.timeframe
        trade.newsEvent = draft.newsEvent
        trade.confidence = draft.confidence
        trade.emotion = draft.emotion
        trade.followedPlan = draft.followedPlan
        trade.marketCondition = draft.marketCondition
        trade.psychologyNotes = draft.psychologyNotes
        trade.durationText = draft.durationText
        trade.durationSeconds = draft.durationSeconds
        trade.imageDisplayMode = draft.imageDisplayMode
        if previous.isInitialImport == true, previous.reviewed != true {
            trade.reviewed = true
        }
        trade.updatedAt = .now
        return trade
    }

    var showsSaveDraft: Bool {
        !isEditing && contentDrafts != nil && ExploreModeSupport.canWriteContent
    }

    var canSaveDraft: Bool {
        guard showsSaveDraft, !isSavingDraft, phase != .saving else { return false }
        let hasRetainedImage = retainedDraftImagePath != nil && !didClearDraftImage
        return screenshotData != nil || hasRetainedImage || !makeTradeDraftState(imagePath: nil).isMeaningfullyEmpty
    }

    func saveDraft() {
        guard canSaveDraft, let contentDrafts, !isSavingDraft else {
            if showsSaveDraft, !isSavingDraft, phase != .saving {
                formError = "Nothing to save yet."
            }
            return
        }
        isSavingDraft = true
        formError = nil
        let draftID = activeDraftID ?? UUID()
        let imageData = screenshotData
        let previousPath = retainedDraftImagePath
        let clearedImage = didClearDraftImage
        let state = makeTradeDraftState(imagePath: nil)
        Task {
            do {
                var payloadState = state
                if let imageData {
                    payloadState.imageStoragePath = try await contentDrafts.uploadDraftImage(
                        draftID: draftID,
                        data: imageData
                    )
                    if let previousPath, previousPath != payloadState.imageStoragePath {
                        await contentDrafts.deleteDraftMedia(paths: [previousPath])
                    }
                } else if clearedImage {
                    if let previousPath {
                        await contentDrafts.deleteDraftMedia(paths: [previousPath])
                    }
                    payloadState.imageStoragePath = nil
                } else {
                    payloadState.imageStoragePath = previousPath
                }
                var payload = ContentDraftPayload()
                payload.trade = payloadState
                guard !payload.isMeaningfullyEmpty else {
                    isSavingDraft = false
                    formError = "Nothing to save yet."
                    return
                }
                let userID = await session.currentUserID ?? UserID("")
                let saved = try await contentDrafts.saveDraft(
                    ContentDraft(
                        id: draftID,
                        userID: userID,
                        type: .trade,
                        payload: payload,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
                activeDraftID = saved.id
                isSavingDraft = false
                SaveSuccessConfirmationCenter.shared.present("Draft saved")
                onDismiss()
            } catch {
                isSavingDraft = false
                formError = UserFacingError.message(for: error)
            }
        }
    }

    private func applyTradeDraft(_ draft: ContentDraft) {
        guard let state = draft.payload.trade else { return }
        activeDraftID = draft.id
        retainedDraftImagePath = state.imageStoragePath
        if let accountID = state.accountID, !accountID.isEmpty {
            selectedAccountID = TradingAccountID(accountID)
        }
        selectedCopyGroupID = state.copyGroupID
        symbolText = state.symbol
        side = TradeSide(rawValue: state.side) ?? .long
        entryPriceText = state.entryPrice
        exitPriceText = state.exitPrice
        contractsText = state.contracts
        pnlText = state.pnl
        pointsText = state.points
        rrText = state.rr
        if let entryAt = state.entryAt.flatMap(ContentDraftDateCodec.date(from:)) {
            self.entryAt = entryAt
        }
        if let exitAt = state.exitAt.flatMap(ContentDraftDateCodec.date(from:)) {
            self.exitAt = exitAt
        }
        includeExitTime = state.includeExitTime
        strategyText = state.strategy
        notesText = state.notes
        timeframeSelection = state.timeframe
        customTimeframeText = state.customTimeframe
        newsEvent = state.newsEvent
        confidenceLevel = state.confidence
        emotionSelection = state.emotion
        followedPlan = state.followedPlan
        marketConditionSelection = state.marketCondition
        psychologyNotesText = state.psychologyNotes
        screenshotDisplayMode = TradeScreenshotDisplayMode(rawValue: state.screenshotDisplayMode) ?? .fit
        publicCaptionText = state.publicCaption
        shareToProfile = state.shareToProfile
    }

    private func makeTradeDraftState(imagePath: String?) -> TradeComposerDraftState {
        var state = TradeComposerDraftState()
        state.accountID = selectedAccountID?.rawValue
        state.copyGroupID = selectedCopyGroupID
        state.symbol = symbolText
        state.side = side.rawValue
        state.entryPrice = entryPriceText
        state.exitPrice = exitPriceText
        state.contracts = contractsText
        state.pnl = pnlText
        state.points = pointsText
        state.rr = rrText
        state.entryAt = ContentDraftDateCodec.string(from: entryAt)
        state.exitAt = includeExitTime ? ContentDraftDateCodec.string(from: exitAt) : nil
        state.includeExitTime = includeExitTime
        state.strategy = strategyText
        state.notes = notesText
        state.timeframe = timeframeSelection
        state.customTimeframe = customTimeframeText
        state.newsEvent = newsEvent
        state.confidence = confidenceLevel
        state.emotion = emotionSelection
        state.followedPlan = followedPlan
        state.marketCondition = marketConditionSelection
        state.psychologyNotes = psychologyNotesText
        state.screenshotDisplayMode = screenshotDisplayMode.rawValue
        state.publicCaption = publicCaptionText
        state.shareToProfile = shareToProfile
        state.imageStoragePath = imagePath
        return state
    }

    private func restorePendingDraftMediaIfNeeded() async {
        guard !didRestoreDraftMedia else { return }
        didRestoreDraftMedia = true
        guard let path = retainedDraftImagePath else { return }
        do {
            let data = try await ContentDraftMediaDownload.imageData(
                path: path,
                session: session,
                objectStorage: objectStorage
            )
            guard let image = UIImage(data: data) else { return }
            let displayMode = screenshotDisplayMode
            setScreenshot(image)
            screenshotDisplayMode = displayMode
        } catch {
            formError = "Couldn't restore the draft screenshot."
        }
    }

    private static func userMessage(for error: Error) -> String {
        if ProLimitPresentation.presentUpgradeIfProLimit(error) {
            return ""
        }
        if let domain = error as? DomainError {
            switch domain {
            case .tradeValidation(let v):
                switch v {
                case .missingSymbol: return "Symbol is required."
                case .accountRequired: return "Choose a trading account."
                case .accountReadOnly: return "Choose a different trading account."
                case .exitBeforeEntry: return "Exit time must be after entry."
                case .invalidQuantity: return "Invalid contracts."
                case .invalidPrice: return "Invalid price."
                case .unsupportedMode: return "Unsupported account mode."
                case .message(let m): return m
                }
            case .businessRule(.dailyLimitExceeded):
                return "Couldn't save trade. Please try again."
            case .permission(.notAuthenticated):
                return "Sign in to add trades."
            default:
                break
            }
        }
        let text = String(describing: error).lowercased()
        if text.contains("free_plan_account_limit") {
            return "Free plan allows up to \(FreeTierPolicy.maxTradeEntryAccounts) trading accounts total. TraxPro unlocks unlimited accounts."
        }
        if text.contains("can_add_trades") || text.contains("read_only") || text.contains("accountreadonly") {
            return "This account can't accept new trades."
        }
        return "Couldn't save trade. Check your connection and try again."
    }
}
