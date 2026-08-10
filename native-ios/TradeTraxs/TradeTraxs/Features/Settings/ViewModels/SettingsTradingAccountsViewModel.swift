import Foundation
import Observation

@Observable
@MainActor
final class SettingsTradingAccountsViewModel {
    private let trades: any TradeRepository
    private let session: any SessionProviding

    private(set) var accounts: [TradingAccount] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var hasLoaded = false

    init(trades: any TradeRepository, session: any SessionProviding) {
        self.trades = trades
        self.session = session
    }

    var propAccounts: [TradingAccount] {
        accounts.filter(\.isPropFirmAccount)
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = accounts.isEmpty
        do {
            guard let userID = await session.currentUserID else {
                errorMessage = "Not signed in"
                isLoading = false
                return
            }
            accounts = try await trades.accounts(for: ProfileID(userID.rawValue))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
