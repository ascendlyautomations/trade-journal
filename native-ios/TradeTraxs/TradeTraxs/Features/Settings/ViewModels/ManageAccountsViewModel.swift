import Foundation
import Observation

@Observable
@MainActor
final class ManageAccountsViewModel {
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache

    private(set) var accounts: [TradingAccount] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var formError: String?
    private var hasLoaded = false
    private var viewerID: ProfileID?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
    }

    var propAccounts: [TradingAccount] {
        accounts.filter(\.isPropFirmAccount)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await loadAccounts(forceNetwork: false) }
    }

    func refresh() async {
        await loadAccounts(forceNetwork: true)
    }

    /// Cache-first initial open; pull-to-refresh uses ``refresh``.
    func loadAccounts(forceNetwork: Bool = false) async {
        isLoading = accounts.isEmpty
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Sign in to continue."
                isLoading = false
                return
            }
            viewerID = ProfileID(userID.rawValue)
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: ProfileID(userID.rawValue),
                detailCache: detailCache,
                repository: trades,
                forceNetwork: forceNetwork
            )
            accounts = Self.sorted(loaded)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func emptyDraft() -> TradingAccountDraft {
        TradingAccountDraft(
            name: "",
            sizeDigits: "",
            accountNumber: "",
            category: .personal,
            mode: .live,
            note: "",
            propFirmRules: nil
        )
    }

    func draft(from account: TradingAccount) -> TradingAccountDraft {
        TradingAccountDraft(
            name: account.name,
            sizeDigits: account.size.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "",
            accountNumber: account.accountNumber ?? "",
            category: account.category,
            mode: account.mode,
            note: account.note ?? "",
            propFirmRules: account.propFirmRules
        )
    }

    func create(_ draft: TradingAccountDraft) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let created = try await trades.createAccount(ownerID: viewerID, draft: draft)
            accounts = Self.sorted(accounts + [created])
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountCreated(created.id)
            ExperienceHaptics.play(.success)
        }
    }

    func update(id: TradingAccountID, draft: TradingAccountDraft) async -> Bool {
        await mutate {
            guard let viewerID else { throw AppError.domain(.permission(.notAuthenticated)) }
            let updated = try await trades.updateAccount(id: id, ownerID: viewerID, draft: draft)
            accounts = Self.sorted(accounts.map { $0.id == id ? updated : $0 })
            SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            AccountMutationStore.shared.noteAccountUpdated(id)
            ExperienceHaptics.play(.success)
        }
    }

    func setActive(id: TradingAccountID, isActive: Bool) async {
        _ = await mutate {
            try await trades.setAccountActive(id: id, isActive: isActive)
            accounts = Self.sorted(accounts.map { account in
                guard account.id == id else { return account }
                var copy = account
                copy.isActive = isActive
                return copy
            })
            if let viewerID {
                SessionAccountsStore.shared.seed(accounts, for: viewerID, detailCache: detailCache)
            }
            AccountMutationStore.shared.noteAccountUpdated(id)
            ExperienceHaptics.play(.selection)
        }
    }

    func subtitle(for account: TradingAccount) -> String {
        var parts: [String] = []
        parts.append(account.category == .propFirm ? "Prop Firm" : account.category.rawValue.capitalized)
        parts.append(Self.modeLabel(account.mode, category: account.category))
        if let size = account.size {
            parts.append(size.amount.formatted(.number.precision(.fractionLength(0))))
        }
        if !account.canAddTrades {
            parts.append("Read Only")
        }
        if !account.isActive {
            parts.append("Inactive")
        }
        return parts.joined(separator: " · ")
    }

    static func modeLabel(_ mode: TradingAccountMode, category: TradingAccountCategory) -> String {
        switch category {
        case .propFirm:
            return mode == .funded ? "Funded" : "Eval"
        case .backtest:
            return "Backtest"
        case .personal, .broker:
            return mode == .sim ? "Sim" : "Live"
        }
    }

    static func modes(for category: TradingAccountCategory) -> [TradingAccountMode] {
        switch category {
        case .propFirm: return [.evaluation, .funded]
        case .backtest: return [.backtest]
        case .personal, .broker: return [.live, .sim]
        }
    }

    static func defaultMode(for category: TradingAccountCategory) -> TradingAccountMode {
        switch category {
        case .propFirm: return .evaluation
        case .backtest: return .backtest
        case .personal, .broker: return .live
        }
    }

    // MARK: - Private

    private func mutate(_ work: () async throws -> Void) async -> Bool {
        formError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await work()
            return true
        } catch {
            if let app = error as? AppError, case .unknown(let message) = app {
                formError = message
            } else {
                formError = UserFacingError.message(for: error)
            }
            return false
        }
    }

    private static func sorted(_ accounts: [TradingAccount]) -> [TradingAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
