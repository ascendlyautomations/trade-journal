import Foundation
import Observation

@Observable
@MainActor
final class RecordPayoutFlowViewModel {
    enum Step: Equatable {
        case setup
        case confirm
        case sharePrompt
    }

    enum Phase: Equatable {
        case loading
        case ready
        case recording
        case failed(String)
    }

    let accountID: TradingAccountID

    private(set) var phase: Phase = .loading
    private(set) var step: Step = .setup
    private(set) var setupContext: PropFirmPayoutSetupContext?
    private(set) var lastRecordedAmount: Decimal?
    private(set) var lastRecordedDate: Date = .now

    var payoutAmountDigits = ""
    var balanceAfterDigits = ""
    var payoutDate: Date = .now
    var drawdownBehavior: PayoutDrawdownBehavior = .resetToAccount
    var rememberDrawdownBehavior = false
    var formError: String?

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator

    init(
        accountID: TradingAccountID,
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.accountID = accountID
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
    }

    var accountName: String {
        setupContext?.account.name ?? "Account"
    }

    var balanceBeforeDisplay: String {
        guard let value = setupContext?.balanceBeforePayout else { return "—" }
        return CurrencyAmountFieldSupport.formatDisplay(value)
    }

    var canAdvanceFromSetup: Bool {
        parsedPayoutAmount != nil
            && parsedBalanceAfter != nil
            && (parsedPayoutAmount ?? 0) > 0
    }

    func loadIfNeeded() async {
        guard setupContext == nil else {
            phase = .ready
            return
        }
        phase = .loading
        formError = nil
        do {
            guard let viewerID = await session.currentUserID.map({ ProfileID($0.rawValue) }) else {
                throw AppError.domain(.permission(.notAuthenticated))
            }
            let accounts = try await SessionAccountsStore.shared.accounts(
                for: viewerID,
                detailCache: detailCache,
                repository: trades
            )
            guard let account = accounts.first(where: { $0.id == accountID }),
                  PropFirmPayoutPolicy.supportsRecordPayout(for: account)
            else {
                throw AppError.unknown(message: "Record Payout is only available for funded prop-firm accounts.")
            }
            let tradePage = try await trades.trades(
                ownedBy: viewerID,
                accountID: accountID,
                page: PageRequest(limit: 500),
                publicOnly: false
            )
            let payoutCycles = try await trades.payoutCycleHistory(for: accountID)
            let context = PropFirmPayoutCycleSupport.buildSetupContext(
                account: account,
                trades: tradePage.items,
                payoutCycles: payoutCycles
            )
            setupContext = context
            drawdownBehavior = context.defaultDrawdownBehavior
            rememberDrawdownBehavior = context.defaultRememberDrawdownBehavior
            balanceAfterDigits = CurrencyAmountFieldSupport.seedEditingText(from: context.balanceBeforePayout)
            payoutDate = .now
            phase = .ready
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    func advanceToConfirm() {
        guard canAdvanceFromSetup else {
            formError = "Enter a payout amount and balance after payout."
            return
        }
        formError = nil
        step = .confirm
    }

    func backToSetup() {
        step = .setup
    }

    func recordPayout() async -> Bool {
        guard let context = setupContext,
              let payoutAmount = parsedPayoutAmount,
              let balanceAfter = parsedBalanceAfter,
              payoutAmount > 0
        else {
            formError = "Enter a valid payout amount."
            return false
        }
        phase = .recording
        formError = nil
        let maxDrawdown = context.account.propFirmRules?.maxDrawdown ?? 0
        let drawdownFloor = PropFirmMetrics.computePayoutDrawdownFloor(
            behavior: drawdownBehavior,
            accountBaseBalance: context.startingBalance,
            trailingMetricsBeforePayout: context.cycleTrailingMetrics,
            maxDrawdown: maxDrawdown
        )
        let input = RecordAccountPayoutInput(
            balanceAfterPayout: balanceAfter,
            payoutAmount: payoutAmount,
            drawdownBehavior: drawdownBehavior,
            drawdownFloorAfterPayout: drawdownFloor,
            balanceBeforePayout: context.balanceBeforePayout,
            rememberDrawdownBehavior: rememberDrawdownBehavior
        )
        do {
            let result = try await trades.recordAccountPayout(accountID: accountID, input: input)
            lastRecordedAmount = payoutAmount
            lastRecordedDate = payoutDate
            if let profileID = await session.currentUserID.map({ ProfileID($0.rawValue) }) {
                SessionPayoutCyclesStore.shared.invalidate(accountID: accountID, profileID: profileID)
            }
            AccountMutationStore.shared.notePayoutRecorded(accountID: accountID)
            #if DEBUG
            PayoutCycleRefreshProbe.logAfterPayoutRecorded(
                accountID: accountID,
                cycleID: result.cycleID,
                balanceAfterPayout: balanceAfter,
                dashboardCacheInvalidated: true
            )
            #endif
            ExperienceHaptics.play(.success)
            phase = .ready
            step = .sharePrompt
            return true
        } catch {
            phase = .ready
            step = .confirm
            formError = UserFacingError.message(for: error)
            return false
        }
    }

    func openShareAchievementFlow(onDismissSheet: () -> Void) {
        guard let context = setupContext, let amount = lastRecordedAmount else { return }
        let prefill = PropFirmPayoutCycleSupport.milestoneAchievementPrefill(
            account: context.account,
            payoutAmount: amount,
            payoutDate: lastRecordedDate
        )
        CreateAchievementPrefillStore.shared.stage(prefill)
        onDismissSheet()
        navigationCoordinator.openComposeAchievement()
    }

    func syncBalanceAfterFromPayoutAmount() {
        guard let before = setupContext?.balanceBeforePayout,
              let payout = parsedPayoutAmount,
              payout > 0
        else { return }
        let suggested = max(0, before - payout)
        balanceAfterDigits = CurrencyAmountFieldSupport.seedEditingText(from: suggested)
    }

    private var parsedPayoutAmount: Decimal? {
        CurrencyAmountFieldSupport.parse(payoutAmountDigits)
    }

    private var parsedBalanceAfter: Decimal? {
        CurrencyAmountFieldSupport.parse(balanceAfterDigits)
    }
}
