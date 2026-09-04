import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class TradeDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var trade: Trade?
    private(set) var images: [TradeImage] = []
    private(set) var notes: [TradeNote] = []
    private(set) var accountName: String?
    /// Owner-only — never used for public Trade Detail titles.
    private(set) var accountNumber: String?
    /// Account status — Funded / Eval / Live (web account `mode`).
    private(set) var accountMode: TradingAccountMode?
    /// Account size from `accounts.account_size`.
    private(set) var accountSize: Decimal?
    private(set) var author: Profile?
    private(set) var authorAvatar: Image?
    private(set) var isOwner = false
    private(set) var isDeleting = false
    var deleteErrorMessage: String?
    private(set) var ownerAnalytics: TradeDetailAnalytics.Result?

    let tradeID: TradeID

    private let trades: any TradeRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline
    private let cache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let rpc: any RPCClient
    private var loadTask: Task<Void, Never>?
    /// Prevents repeat account fetches when size is legitimately absent.
    private let experience: TradeDetailExperience
    private var didResolveAccountMetadata = false

    init(
        tradeID: TradeID,
        trades: any TradeRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        imagePipeline: any ImagePipeline,
        cache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        rpc: any RPCClient,
        experience: TradeDetailExperience = .social
    ) {
        self.tradeID = tradeID
        self.trades = trades
        self.profiles = profiles
        self.session = session
        self.imagePipeline = imagePipeline
        self.cache = cache
        self.navigationCoordinator = navigationCoordinator
        self.rpc = rpc
        self.experience = experience
    }

    var mediaReference: MediaReference? {
        images.first?.media ?? trade?.thumbnail
    }

    var authorDisplayName: String { DetailAuthorPresentation.displayName(for: author) }
    var authorUsername: String { DetailAuthorPresentation.username(for: author) }
    var authorInitials: String { DetailAuthorPresentation.initials(for: author) }

    /// Header identity — journal+owner: `Name • Number`; all public/social paths: sanitized name only.
    var accountIdentityLine: String? {
        TradeDisplay.accountIdentityLine(
            name: accountName,
            size: accountSize,
            mode: accountMode,
            accountNumber: accountDisplayAudience == .owner ? accountNumber : nil,
            audience: accountDisplayAudience,
            category: nil
        )
    }

    /// Owner journal summary line — account name + compact mode.
    var accountSummaryLine: String? {
        guard experience == .journal, isOwner else { return accountIdentityLine }
        var parts: [String] = []
        if let accountName, !accountName.isEmpty {
            parts.append(accountName)
        }
        if let accountMode {
            parts.append(TradeDisplay.accountModeCompactTitle(accountMode))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accountDisplayAudience: TradingAccountDisplay.Audience {
        switch experience {
        case .journal where isOwner:
            return .owner
        default:
            return .public
        }
    }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded || trade == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        didResolveAccountMetadata = false
        await performLoad(forceNetwork: true)
    }

    func editTrade() {
        guard isOwner else { return }
        ExperienceHaptics.play(.selection)
        if let trade {
            cache.seed(trade)
        }
        navigationCoordinator.editTrade(tradeID)
    }

    func deleteTrade() async -> Bool {
        guard isOwner, !isDeleting else { return false }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }
        do {
            if let viewer = await session.currentUserID,
               viewer.rawValue.hasPrefix("dev.")
            {
                // Local development — mutate caches only.
            } else {
                try await trades.delete(id: tradeID)
            }
            let owner: ProfileID
            if let trade {
                owner = trade.ownerProfileID
            } else if let userID = await session.currentUserID {
                owner = ProfileID(userID.rawValue)
            } else {
                throw AppError.domain(.permission(.notAuthenticated))
            }
            cache.removeTrade(id: tradeID)
            TradeJournalMutationStore.shared.noteDeleted(id: tradeID, owner: owner)
            ExperienceHaptics.play(.success)
            navigationCoordinator.pop()
            return true
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    /// Apply an in-session edit without a full detail bootstrap.
    func applyUpdated(_ trade: Trade) {
        guard trade.id == tradeID else { return }
        cache.seed(trade)
        images = []
        notes = []
        applySeed(trade)
        if let preview = trade.notePreview, !preview.isEmpty {
            notes = [
                TradeNote(
                    id: TradeNoteID(trade.id.rawValue),
                    tradeID: trade.id,
                    body: preview,
                    createdAt: trade.createdAt,
                    updatedAt: trade.updatedAt
                ),
            ]
        }
        Task { await resolveAccountMetadata(for: trade) }
        Task { await loadOwnerAnalytics(for: trade) }
    }

    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .updated(let trade) where trade.id == tradeID:
            applyUpdated(trade)
        case .deleted(let id, _) where id == tradeID:
            navigationCoordinator.pop()
        default:
            break
        }
    }

    // MARK: - Private

    private func performLoad(forceNetwork: Bool = false) async {
        if !forceNetwork, let seed = cache.trade(id: tradeID) {
            applySeed(seed)
            phase = .loaded
            await loadSupplementaries(for: seed)
            loadTask = nil
            return
        }

        if trade == nil {
            phase = .loading
        }

        do {
            let loaded = try await trades.trade(id: tradeID)
            guard !Task.isCancelled else { return }
            cache.seed(loaded)
            applySeed(loaded)
            phase = .loaded
            await loadSupplementaries(for: loaded)
        } catch {
            guard !Task.isCancelled else { return }
            if trade == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func applySeed(_ seed: Trade) {
        trade = seed
        if let accountID = seed.accountID {
            let cachedName = cache.accountName(for: accountID)
            accountMode = cache.accountMode(for: accountID)
            accountSize = cache.accountSize(for: accountID)
            switch experience {
            case .journal:
                accountName = cachedName
                accountNumber = cache.accountNumber(for: accountID)
            case .social:
                accountName = cachedName.map {
                    PublicAccountPrivacy.publicSafeAccountName(
                        rawName: $0,
                        accountNumber: nil,
                        category: nil,
                        mode: accountMode
                    )
                }
                accountNumber = nil
            }
        }
        if images.isEmpty, let thumb = seed.thumbnail {
            images = [
                TradeImage(
                    id: TradeImageID(thumb.id),
                    tradeID: seed.id,
                    media: thumb,
                    sortOrder: 0
                ),
            ]
        }
        if notes.isEmpty, let preview = seed.notePreview, !preview.isEmpty {
            notes = [
                TradeNote(
                    id: TradeNoteID(seed.id.rawValue),
                    tradeID: seed.id,
                    body: preview,
                    createdAt: seed.createdAt,
                    updatedAt: seed.updatedAt
                ),
            ]
        }
    }

    private func loadSupplementaries(for trade: Trade) async {
        let userID = await session.currentUserID
        isOwner = userID?.rawValue == trade.ownerProfileID.rawValue

        if ProfileSectionSupport.isLocalDevelopmentProfile(trade.ownerProfileID) {
            if let accountID = trade.accountID {
                if accountName == nil {
                    let raw = ProfileTradeFixtures.accountNames()[accountID]
                        ?? cache.accountName(for: accountID)
                    accountName = experience == .social
                        ? raw.map {
                            PublicAccountPrivacy.publicSafeAccountName(
                                rawName: $0,
                                accountNumber: nil,
                                category: nil,
                                mode: accountMode
                            )
                        }
                        : raw
                }
                if accountMode == nil {
                    accountMode = ProfileTradeFixtures.accountModes()[accountID]
                        ?? cache.accountMode(for: accountID)
                }
                if accountSize == nil, experience == .journal, isOwner {
                    accountSize = ProfileTradeFixtures.accountSizes()[accountID]
                        ?? cache.accountSize(for: accountID)
                }
                if experience == .journal, isOwner {
                    accountNumber = ProfileTradeFixtures.accountNumbers()[accountID]
                        ?? cache.accountNumber(for: accountID)
                } else {
                    accountNumber = nil
                }
            }
            if let cached = cache.profile(id: trade.ownerProfileID) {
                author = cached
            } else {
                author = try? await SessionProfileStore.shared.profiles(
                    ids: [trade.ownerProfileID],
                    detailCache: cache,
                    repository: profiles
                ).first
            }
            await loadAuthorAvatar()
            await loadOwnerAnalytics(for: trade)
            return
        }

        // List seed already carries thumbnail / notePreview — avoid redundant `trades` GETs.
        let needsImages = images.isEmpty
        let needsNotes = notes.isEmpty
        async let imagesTask: [TradeImage] = {
            guard needsImages else { return [] }
            return (try? await trades.images(for: trade.id)) ?? []
        }()
        async let notesTask: [TradeNote] = {
            guard needsNotes else { return [] }
            return (try? await trades.notes(for: trade.id)) ?? []
        }()
        async let authorTask: Profile? = {
            try? await SessionProfileStore.shared.profiles(
                ids: [trade.ownerProfileID],
                detailCache: cache,
                repository: profiles
            ).first
        }()

        let fetchedImages = await imagesTask
        let fetchedNotes = await notesTask
        let fetchedAuthor = await authorTask

        if !fetchedImages.isEmpty {
            images = fetchedImages
        }
        if !fetchedNotes.isEmpty {
            notes = fetchedNotes
        }
        author = cache.profile(id: trade.ownerProfileID) ?? fetchedAuthor
        await loadAuthorAvatar()
        await resolveAccountMetadata(for: trade)
        await loadOwnerAnalytics(for: trade)
    }

    private func loadOwnerAnalytics(for trade: Trade) async {
        guard isOwner, experience == .journal else {
            ownerAnalytics = nil
            return
        }
        guard let userID = await session.currentUserID else { return }
        let profileID = ProfileID(userID.rawValue)
        guard profileID == trade.ownerProfileID else {
            ownerAnalytics = nil
            return
        }

        let accountModes = Dictionary(
            uniqueKeysWithValues: (cache.accounts(for: profileID) ?? []).map { ($0.id, $0.mode) }
        )

        var dataSource = "client_fallback(\(SessionOwnerTradesStore.shared.cached(for: profileID) != nil ? "SessionOwnerTradesStore.cache" : "TradeRepository.trades"))"
        var rpcPayload: TradeDetailOwnerComparisonBootstrapV1.DataPayload?
        var rpcError: String?

        do {
            let bootstrap = try await TradeDetailComparisonLoader.loadBootstrap(trade: trade, rpc: rpc)
            rpcPayload = bootstrap.data
            ownerAnalytics = TradeDetailAnalytics.map(from: bootstrap.data, trade: trade)
            dataSource = BackendV2Versioning.RPCName.tradeDetailOwnerComparison.rawValue
        } catch {
            rpcError = String(describing: error)
            let history: [Trade]
            if let cached = SessionOwnerTradesStore.shared.cached(for: profileID) {
                history = cached
            } else {
                history = (try? await SessionOwnerTradesStore.shared.trades(
                    for: profileID,
                    detailCache: cache,
                    repository: trades
                )) ?? []
            }

            ownerAnalytics = TradeDetailAnalytics.analyze(
                trade: trade,
                history: history,
                accountModes: accountModes
            )
        }

        #if DEBUG
        let debugHistory: [Trade]
        if let cached = SessionOwnerTradesStore.shared.cached(for: profileID) {
            debugHistory = cached
        } else {
            debugHistory = (try? await SessionOwnerTradesStore.shared.trades(
                for: profileID,
                detailCache: cache,
                repository: trades
            )) ?? []
        }
        TradeDetailTickerHistoryDiagnostics.log(
            TradeDetailTickerHistoryDiagnostics.Context(
                trade: trade,
                profileID: profileID,
                dataSource: dataSource,
                rpcPayload: rpcPayload,
                rpcError: rpcError,
                rawHistory: debugHistory,
                accountModes: accountModes,
                displayedHistory: ownerAnalytics?.tickerHistory
            )
        )
        #endif
    }

    private func resolveAccountMetadata(for trade: Trade) async {
        guard let accountID = trade.accountID else { return }

        if accountName == nil, let cached = cache.accountName(for: accountID) {
            accountName = experience == .social
                ? PublicAccountPrivacy.publicSafeAccountName(
                    rawName: cached,
                    accountNumber: nil,
                    category: nil,
                    mode: accountMode
                )
                : cached
        }
        if experience == .journal, isOwner, accountNumber == nil {
            accountNumber = cache.accountNumber(for: accountID)
        }
        if accountMode == nil, let cached = cache.accountMode(for: accountID) {
            accountMode = cached
        }
        if accountSize == nil, let cached = cache.accountSize(for: accountID) {
            accountSize = cached
        }

        guard isOwner, experience == .journal else {
            accountNumber = nil
            didResolveAccountMetadata = true
            return
        }

        // Session accounts already resolved for this profile — never refetch.
        if cache.hasAccounts(for: trade.ownerProfileID) {
            if accountNumber == nil {
                accountNumber = cache.accountNumber(for: accountID)
            }
            didResolveAccountMetadata = true
            return
        }

        // Identity complete from list seeding — skip network.
        if accountName != nil, accountMode != nil {
            didResolveAccountMetadata = true
            return
        }
        guard !didResolveAccountMetadata else { return }

        guard let viewerID = await session.currentUserID,
              ProfileID(viewerID.rawValue) == trade.ownerProfileID,
              let _ = try? await SessionAccountsStore.shared.accounts(
                  for: trade.ownerProfileID,
                  detailCache: cache,
                  repository: trades,
                  viewerProfileID: ProfileID(viewerID.rawValue)
              )
        else {
            didResolveAccountMetadata = true
            return
        }
        didResolveAccountMetadata = true
        if accountName == nil {
            accountName = cache.accountName(for: accountID)
        }
        if accountNumber == nil {
            accountNumber = cache.accountNumber(for: accountID)
        }
        if accountMode == nil {
            accountMode = cache.accountMode(for: accountID)
        }
        if accountSize == nil {
            accountSize = cache.accountSize(for: accountID)
        }
    }

    private func loadAuthorAvatar() async {
        authorAvatar = await DetailAuthorPresentation.loadAvatar(
            for: author,
            imagePipeline: imagePipeline
        )
    }
}
