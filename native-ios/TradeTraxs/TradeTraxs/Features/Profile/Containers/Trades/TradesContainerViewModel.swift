import Foundation
import Observation

@Observable
@MainActor
final class TradesContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Trade] = []
    private(set) var nextCursor: String?
    private(set) var accountNames: [TradingAccountID: String] = [:]
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
    private let isOwner: Bool

    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isLoadingMore = false

    struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        isOwner: Bool = true
    ) {
        self.profileID = profileID
        self.trades = trades
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.isOwner = isOwner
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
        case .all: return ProfileSection.trades.emptyMessage
        case .wins: return "Winning trades will show up here."
        case .losses: return "Losing trades will show up here."
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
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
                detailCache.seedAccountName(name, for: accountID)
            }
            if let mode = accountModes[accountID] {
                detailCache.seed(accountModes: [accountID: mode])
            }
            if let size = accountSizes[accountID] {
                detailCache.seed(accountSizes: [accountID: size])
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
        openTrade(trade)
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
            ExperienceHaptics.play(.success)
            updateStateForVisibleItems()
        } catch {
            paginationErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func accountName(for trade: Trade) -> String? {
        guard let accountID = trade.accountID else { return nil }
        return accountNames[accountID]
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
            accountModes = ProfileTradeFixtures.accountModes()
            accountSizes = ProfileTradeFixtures.accountSizes()
            detailCache.seed(publicTrades: items, for: profileID)
            detailCache.seed(accountNames: accountNames)
            detailCache.seed(accountModes: accountModes)
            detailCache.seed(accountSizes: accountSizes)
            nextCursor = nil
            updateStateForVisibleItems()
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

            // Account metadata is secondary — never fail the trades list on account mapping.
            // Session cache: skip network when Profile already resolved accounts once.
            if let cached = detailCache.accounts(for: profileID) {
                applyAccounts(cached)
            } else if let accounts = try? await trades.accounts(for: profileID) {
                applyAccounts(accounts)
                detailCache.seed(accounts: accounts, for: profileID)
            }
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

    private func applyAccounts(_ accounts: [TradingAccount]) {
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        accountModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        accountSizes = Dictionary(
            uniqueKeysWithValues: accounts.compactMap { account in
                guard let amount = account.size?.amount else { return nil }
                return (account.id, amount)
            }
        )
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

enum TradeDisplay {
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

    /// Web `formatAccountNameWithSizeDisplay` + compact mode — `Alpha Futures 50K Eval`.
    static func accountIdentityLine(
        name: String?,
        size: Decimal?,
        mode: TradingAccountMode?
    ) -> String? {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sizePart = accountSizeText(size)
        let nameSize: String
        if !trimmedName.isEmpty, !sizePart.isEmpty {
            // Avoid "Apex 50K 50K" when size is already embedded in the name.
            if trimmedName.localizedCaseInsensitiveContains(sizePart)
                || trimmedName.range(of: #"\b\d+(\.\d+)?[kK]\b"#, options: .regularExpression) != nil
            {
                nameSize = trimmedName
            } else {
                nameSize = "\(trimmedName) \(sizePart)"
            }
        } else if !trimmedName.isEmpty {
            nameSize = trimmedName
        } else if !sizePart.isEmpty {
            nameSize = sizePart
        } else {
            nameSize = ""
        }

        let status = mode.map(accountModeCompactTitle)
        switch (nameSize.isEmpty, status) {
        case (true, .none):
            return nil
        case (true, .some(let status)):
            return status
        case (false, .none):
            return nameSize
        case (false, .some(let status)):
            return "\(nameSize) \(status)"
        }
    }
}
