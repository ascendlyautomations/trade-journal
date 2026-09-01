import Foundation
import Observation

@Observable
@MainActor
final class TradesContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Trade] = []
    private(set) var nextCursor: String?
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var accountNumbers: [TradingAccountID: String] = [:]
    private(set) var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    private(set) var accountSizes: [TradingAccountID: Decimal] = [:]
    private(set) var isRefreshing = false
    private(set) var paginationErrorMessage: String?

    var filter: ProfileTradesFilter = .all
    var sort: ProfileTradesSort = .newest
    var sharePayload: SharePayload?
    var pendingDelete: Trade?

    private let profileID: ProfileID
    private let trades: any TradeRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private let isOwner: Bool

    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isLoadingMore = false
    private var canViewContent = true
    /// When true, initial data comes from ``ProfileScreenViewModel`` bootstrap.
    private var isScreenOwned = false

    struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileID = profileID
        self.trades = trades
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.isOwner = isOwner
    }

    /// Screen-owned engagement prefetch — views must not call the repository path.
    func prefetchEngagement(for tradeIDs: [TradeID]) {
        guard !tradeIDs.isEmpty else { return }
        engagementStore?.prefetch(tradeIDs.map { .trade($0) })
    }

    var visibleItems: [Trade] {
        let filtered = items.filter { filter.matches($0) }
        return sort.sorted(filtered)
    }

    var showsOwnerActions: Bool { isOwner }

    var emptyTitle: String {
        switch filter {
        case .all: return ProfileSection.trades.emptyTitle
        case .wins: return "No winning trades"
        case .losses: return "No losing trades"
        }
    }

    var emptyMessage: String {
        switch filter {
        case .all:
            return isOwner
                ? "Log a trade to start building your journal."
                : "Trades will show up here when they’re shared."
        case .wins: return "Winning trades will show up here."
        case .losses: return "Losing trades will show up here."
        }
    }

    /// Applies screen bootstrap — uses section data when Stage 2 already filled it.
    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        if snapshot.isContentLocked {
            canViewContent = false
            hasLoaded = true
            items = []
            state = .empty
            return
        }
        canViewContent = true
        guard snapshot.didLoadTrades || !snapshot.trades.isEmpty else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), items.isEmpty {
                state = .loading
            }
            return
        }
        hasLoaded = true
        items = snapshot.trades
        nextCursor = snapshot.tradesNextCursor
        accountNames = snapshot.accountNames
        accountNumbers = [:]
        accountModes = snapshot.accountModes
        accountSizes = snapshot.accountSizes
        detailCache.seed(publicTrades: items, for: profileID)
        detailCache.seedPublicAccountMetadata(
            names: sanitizedPublicAccountNames(from: accountNames),
            modes: accountModes,
            sizes: accountSizes,
            for: profileID
        )
        paginationErrorMessage = nil
        updateStateForVisibleItems()
        prefetchEngagement(for: visibleItems.map(\.id))
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        guard canViewContent else {
            hasLoaded = true
            state = .empty
            return
        }
        loadTask = Task { await performLoad(reset: true) }
    }

    func refresh() async {
        await refresh(background: false)
    }

    func setFilter(_ value: ProfileTradesFilter) {
        guard filter != value else { return }
        ExperienceHaptics.play(.selection)
        filter = value
        updateStateForVisibleItems()
    }

    func setSort(_ value: ProfileTradesSort) {
        guard sort != value else { return }
        ExperienceHaptics.play(.selection)
        sort = value
    }

    func loadMoreIfNeeded(currentTradeID: TradeID?) async {
        guard hasLoaded, !isLoadingMore, nextCursor != nil else { return }
        guard let currentTradeID else { return }
        guard let last = visibleItems.last, last.id == currentTradeID else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(cursor: nextCursor),
                publicOnly: true
            )
            appendUnique(page.items)
            nextCursor = page.nextCursor
            paginationErrorMessage = nil
            updateStateForVisibleItems()
        } catch {
            paginationErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    func openTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        if let accountID = trade.accountID {
            if let name = accountNames[accountID] {
                detailCache.seedAccountName(
                    PublicAccountPrivacy.publicSafeAccountName(
                        rawName: name,
                        accountNumber: nil,
                        category: nil,
                        mode: accountModes[accountID]
                    ),
                    for: accountID
                )
            }
            if let mode = accountModes[accountID] {
                detailCache.seed(accountModes: [accountID: mode])
            }
        }
        navigationCoordinator.open(.profile(.trade(trade.id)))
    }

    func addTrade() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.openCompose(.trade)
    }

    func editTrade(_ trade: Trade) {
        guard isOwner else { return }
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        navigationCoordinator.editTrade(trade.id)
    }

    func shareTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        let pnl = TradeDisplay.pnlText(trade.realizedPnL)
        let side = trade.side == .long ? "Long" : "Short"
        sharePayload = SharePayload(
            text: "\(trade.symbol.ticker) \(side) \(pnl) on TradeTraxs"
        )
    }

    func requestDelete(_ trade: Trade) {
        guard isOwner else { return }
        ExperienceHaptics.play(.warning)
        pendingDelete = trade
    }

    func confirmDelete() async {
        guard let trade = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await trades.delete(id: trade.id)
            items.removeAll { $0.id == trade.id }
            detailCache.removeTrade(id: trade.id)
            TradeJournalMutationStore.shared.noteDeleted(id: trade.id, owner: trade.ownerProfileID)
            ExperienceHaptics.play(.success)
            updateStateForVisibleItems()
        } catch {
            paginationErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .created(let trade) where trade.visibility == .public && trade.ownerProfileID == profileID:
            items.removeAll { $0.id == trade.id }
            items.insert(trade, at: 0)
            detailCache.seed(trade)
            updateStateForVisibleItems()
        case .updated(let trade) where trade.ownerProfileID == profileID:
            if trade.visibility == .public {
                if let index = items.firstIndex(where: { $0.id == trade.id }) {
                    items[index] = trade
                } else {
                    items.insert(trade, at: 0)
                }
                detailCache.seed(trade)
            } else {
                items.removeAll { $0.id == trade.id }
                detailCache.removeTrade(id: trade.id)
            }
            updateStateForVisibleItems()
        case .deleted(let id, let owner) where owner == profileID:
            items.removeAll { $0.id == id }
            detailCache.removeTrade(id: id)
            updateStateForVisibleItems()
        case .bulkImport:
            Task { await refresh() }
        default:
            break
        }
    }

    func accountName(for trade: Trade) -> String? {
        guard let accountID = trade.accountID else {
            return PublicAccountPrivacy.publicTradeAccountLabel(mode: trade.mode)
        }
        if let name = accountNames[accountID] {
            return TradingAccountDisplay.optionalTitle(
                name: name,
                accountNumber: nil,
                audience: .public,
                category: nil,
                mode: accountModes[accountID]
            )
        }
        return PublicAccountPrivacy.publicTradeAccountLabel(mode: trade.mode)
    }

    // MARK: - Private

    private func refresh(background: Bool) async {
        loadTask?.cancel()
        if !background {
            isRefreshing = true
        }
        await performLoad(reset: true)
        isRefreshing = false
    }

    private func performLoad(reset: Bool) async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            hasLoaded = true
            items = ProfileTradeFixtures.samples(owner: profileID)
            accountNames = ProfileTradeFixtures.accountNames()
            accountNumbers = [:]
            accountModes = ProfileTradeFixtures.accountModes()
            accountSizes = ProfileTradeFixtures.accountSizes()
            detailCache.seed(publicTrades: items, for: profileID)
            detailCache.seedPublicAccountMetadata(
                names: sanitizedPublicAccountNames(from: accountNames),
                modes: accountModes,
                sizes: accountSizes,
                for: profileID
            )
            nextCursor = nil
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))
            loadTask = nil
            return
        }

        if reset, items.isEmpty {
            state = .loading
        }

        do {
            // Mirror web Profile list: public trades only (`is_public = true`).
            let page = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(),
                publicOnly: true
            )

            guard !Task.isCancelled else { return }

            items = page.items
            detailCache.seed(publicTrades: items, for: profileID)
            nextCursor = page.nextCursor
            hasLoaded = true
            paginationErrorMessage = nil
            updateStateForVisibleItems()

            prefetchEngagement(for: visibleItems.map(\.id))
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            } else {
                paginationErrorMessage = ProfileSectionSupport.message(for: error)
            }
        }
        loadTask = nil
    }

    private func sanitizedPublicAccountNames(
        from names: [TradingAccountID: String]
    ) -> [TradingAccountID: String] {
        Dictionary(uniqueKeysWithValues: names.map { id, name in
            (
                id,
                PublicAccountPrivacy.publicSafeAccountName(
                    rawName: name,
                    accountNumber: nil,
                    category: nil,
                    mode: accountModes[id]
                )
            )
        })
    }

    private func appendUnique(_ pageItems: [Trade]) {
        let existing = Set(items.map(\.id))
        let fresh = pageItems.filter { !existing.contains($0.id) }
        items.append(contentsOf: fresh)
        if !fresh.isEmpty {
            detailCache.seed(publicTrades: items, for: profileID)
        }
    }

    private func updateStateForVisibleItems() {
        if !hasLoaded {
            state = .loading
            return
        }
        if items.isEmpty {
            state = .empty
            return
        }
        if visibleItems.isEmpty {
            state = .empty
            return
        }
        state = .loaded(itemCount: visibleItems.count)
    }
}

nonisolated enum TradeDisplay {
    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Trading-platform price — `$20,153.25` (USD grouping, preserved decimals).
    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Compact trade timestamp — `9:37AM 7/31/26`.
    private static let compactDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma M/d/yy"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    static func pnlText(_ money: Money?) -> String {
        guard let amount = money?.amount else { return "—" }
        let number = NSDecimalNumber(decimal: amount)
        let formatted = currency.string(from: number) ?? "\(amount)"
        if amount > 0 { return "+\(formatted)" }
        return formatted
    }

    /// Web parity — null/empty tickers render as em dash (`ProfileTradeCard`).
    static func tickerText(_ ticker: String) -> String {
        let trimmed = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    static func tickerText(_ symbol: Symbol) -> String {
        tickerText(symbol.ticker)
    }

    static func priceText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return priceFormatter.string(from: NSDecimalNumber(decimal: value))
            ?? "$\(value)"
    }

    static func rrText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let number = NSDecimalNumber(decimal: value)
        return String(format: "RR %.1f", number.doubleValue)
    }

    /// Journal-style R:R — `1:2.9` when value is the reward multiple.
    static func journalRRText(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let number = NSDecimalNumber(decimal: value)
        return String(format: "1:%.1f", number.doubleValue)
    }

    static func pointsText(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let number = NSDecimalNumber(decimal: value)
        let formatted = String(format: "%g", abs(number.doubleValue))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    static func contractsText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if number == number.rounding(accordingToBehavior: nil) {
            return "\(number.intValue)"
        }
        return number.stringValue
    }

    static func durationText(entryAt: Date, exitAt: Date?) -> String? {
        guard let exitAt, exitAt >= entryAt else { return nil }
        let seconds = Int(exitAt.timeIntervalSince(entryAt))
        return durationTextFromSeconds(seconds)
    }

    /// Prefer authoritative DB duration fields, then entry/exit timestamps.
    static func holdDuration(for trade: Trade) -> String? {
        if let text = trade.durationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return text
        }
        if let seconds = trade.durationSeconds, seconds > 0 {
            return durationTextFromSeconds(seconds)
        }
        return durationText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    private static func durationTextFromSeconds(_ seconds: Int) -> String? {
        guard seconds >= 0 else { return nil }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        if secs > 0 {
            return "\(secs)s"
        }
        return nil
    }

    /// Account · date · time line for journal cards.
    static func journalContextLine(accountName: String?, at date: Date) -> String {
        let stamp = journalDateTimeFormatter.string(from: date)
        if let accountName, !accountName.isEmpty {
            return "\(accountName) · \(stamp)"
        }
        return stamp
    }

    private static let journalDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter
    }()

    static func quantityBadgeText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if number == number.rounding(accordingToBehavior: nil) {
            return "Qty \(number.intValue)"
        }
        return "Qty \(number.stringValue)"
    }

    static func dateText(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func sideTitle(_ side: TradeSide) -> String {
        side == .long ? "Long" : "Short"
    }

    static func dateTimeText(_ date: Date) -> String {
        compactDateTimeFormatter.string(from: date)
    }

    /// Web `resolveTradeModeBadgeLabel` account-status titles.
    static func accountStatusTitle(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .funded: return "Funded"
        case .evaluation: return "Evaluation"
        case .live: return "Live"
        case .sim: return "SIM"
        case .backtest: return "Backtest"
        }
    }

    static func tradeModeFallbackTitle(_ mode: TradeMode?) -> String? {
        guard let mode else { return nil }
        switch mode {
        case .live: return "Live"
        case .sim: return "SIM"
        case .replay: return "Replay"
        case .backtest: return "Backtest"
        case .copyTraded: return "Copy Traded"
        }
    }

    /// Web `formatTradingAccountModeLabel` — short header status (`Eval`, not `Evaluation`).
    static func accountModeCompactTitle(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .evaluation: return "Eval"
        case .funded: return "Funded"
        case .live: return "Live"
        case .sim: return "Sim"
        case .backtest: return "Backtest"
        }
    }

    /// Web `formatAccountBalanceForDisplay` — `50000` → `50K`.
    static func accountSizeText(_ size: Decimal?) -> String {
        guard let size else { return "" }
        let number = NSDecimalNumber(decimal: size).doubleValue
        guard number.isFinite else { return "" }
        if abs(number) >= 1_000 {
            let thousands = number / 1_000
            if thousands.rounded() == thousands {
                return "\(Int(thousands))K"
            }
            let rounded = (thousands * 10).rounded() / 10
            if rounded.rounded() == rounded {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        let intValue = NSDecimalNumber(decimal: size)
        if intValue == intValue.rounding(accordingToBehavior: nil) {
            return "\(intValue.intValue)"
        }
        return intValue.stringValue
    }

    /// Account identity line — journal+owner: `Name • Number`; public/social: sanitized name only.
    static func accountIdentityLine(
        name: String?,
        size: Decimal? = nil,
        mode: TradingAccountMode? = nil,
        accountNumber: String? = nil,
        audience: TradingAccountDisplay.Audience = .public,
        category: TradingAccountCategory? = nil
    ) -> String? {
        _ = size
        return TradingAccountDisplay.optionalTitle(
            name: name,
            accountNumber: accountNumber,
            audience: audience,
            category: category,
            mode: mode
        )
    }
}
