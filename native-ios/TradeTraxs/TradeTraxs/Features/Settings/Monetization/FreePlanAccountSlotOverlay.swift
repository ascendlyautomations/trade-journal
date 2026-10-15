import Observation
import SwiftUI

@Observable
@MainActor
final class FreePlanAccountSlotRequestStore {
    static let shared = FreePlanAccountSlotRequestStore()
    var manualOpenRequested = false

    func requestManualOpen() {
        manualOpenRequested = true
    }
}

@Observable
@MainActor
final class FreePlanAccountSlotViewModel {
    private let trades: any TradeRepository
    private let session: any SessionProviding

    private(set) var accounts: [TradingAccount] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    var manualPresentationRequested = false

    /// Bumped around a save so an in-flight reload cannot overwrite the verified result.
    private var loadGeneration: UInt64 = 0
    private var reloadTicket: UInt64 = 0
    private var settledReloadTicket: UInt64 = 0
    private var reloadFlight: Task<Void, Never>?
    private var isConfirmingSelection = false

    init(trades: any TradeRepository, session: any SessionProviding) {
        self.trades = trades
        self.session = session
    }

    func reload() async {
        let previous = reloadFlight
        reloadTicket &+= 1
        let ticket = reloadTicket
        let flight = Task { @MainActor in
            await previous?.value
            await self.performReload()
            if self.reloadTicket == ticket {
                self.settledReloadTicket = ticket
            }
        }
        reloadFlight = flight
        await flight.value
    }

    var needsAutomaticPresentation: Bool {
        guard let profileID = accounts.first?.ownerProfileID else { return false }
        guard confirmedFreeTier(profileID: profileID) else { return false }
        return FreePlanTradeAccountPolicy.needsSlotSelection(accounts: accounts, viewerTier: .free)
    }

    var canReconfigure: Bool {
        guard let profileID = accounts.first?.ownerProfileID else { return false }
        if TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID) { return false }
        return accounts.count > FreeTierPolicy.maxTradeEntryAccounts
    }

    var isPresented: Bool {
        !accounts.isEmpty
            && (needsAutomaticPresentation
                || manualPresentationRequested
                || FreePlanAccountSlotRequestStore.shared.manualOpenRequested)
    }

    func confirmSelection(ids: [TradingAccountID]) async -> Bool {
        let uniqueIDs = Array(Set(ids))
        if uniqueIDs.count > FreeTierPolicy.maxTradeEntryAccounts {
            errorMessage = "Maximum 3 accounts reached"
            return false
        }
        if uniqueIDs.isEmpty {
            errorMessage = "Select at least one account."
            return false
        }
        guard let profileID = accounts.first?.ownerProfileID else {
            errorMessage = "Couldn't save your account selection. Try again."
            return false
        }
        isSaving = true
        isConfirmingSelection = true
        errorMessage = nil
        defer {
            isSaving = false
            isConfirmingSelection = false
        }
        await drainAccountLoads()
        loadGeneration &+= 1
        do {
            try await trades.selectFreePlanTradeAccounts(ownerID: profileID, accountIDs: uniqueIDs)
            loadGeneration &+= 1
            let expected = Set(uniqueIDs)
            guard let loaded = try await accountsMatchingSelection(profileID: profileID, expected: expected) else {
                errorMessage = "Couldn't save your account selection. Try again."
                return false
            }
            accounts = loaded
            SessionAccountsStore.shared.seed(loaded, for: profileID, detailCache: nil)
            AccountMutationStore.shared.noteAccountsChanged(allAccounts: loaded, viewerID: profileID)
            manualPresentationRequested = false
            FreePlanAccountSlotRequestStore.shared.manualOpenRequested = false
            return true
        } catch {
            if !ProLimitPresentation.presentUpgradeIfProLimit(error) {
                errorMessage = UserFacingError.message(for: error)
            }
            return false
        }
    }

    private func performReload() async {
        let generation = loadGeneration
        guard let userID = await session.currentUserID else {
            guard generation == loadGeneration, !isConfirmingSelection else { return }
            accounts = []
            return
        }
        let profileID = ProfileID(userID.rawValue)
        if TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID) {
            guard generation == loadGeneration, !isConfirmingSelection else { return }
            accounts = []
            manualPresentationRequested = false
            FreePlanAccountSlotRequestStore.shared.manualOpenRequested = false
            return
        }
        if generation == loadGeneration, !isConfirmingSelection,
           let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            accounts = cached
        }
        do {
            let loaded = try await trades.accounts(for: profileID)
            guard generation == loadGeneration, !isConfirmingSelection else { return }
            accounts = loaded
            SessionAccountsStore.shared.seed(loaded, for: profileID, detailCache: nil)
        } catch {
            guard generation == loadGeneration, !isConfirmingSelection else { return }
            if accounts.isEmpty {
                accounts = []
            }
        }
    }

    /// Waits until the latest reload's account request has finished.
    private func drainAccountLoads() async {
        while settledReloadTicket != reloadTicket {
            await reloadFlight?.value
            if settledReloadTicket == reloadTicket {
                return
            }
        }
    }

    /// Reads accounts after the RPC. A mismatch is read once more so a request that
    /// started before the save cannot confirm the selection.
    private func accountsMatchingSelection(
        profileID: ProfileID,
        expected: Set<TradingAccountID>
    ) async throws -> [TradingAccount]? {
        let first = try await trades.accounts(for: profileID)
        if Self.tradeEntryEnabledIDs(first) == expected {
            return first
        }
        let second = try await trades.accounts(for: profileID)
        if Self.tradeEntryEnabledIDs(second) == expected {
            return second
        }
        return nil
    }

    private static func tradeEntryEnabledIDs(_ accounts: [TradingAccount]) -> Set<TradingAccountID> {
        Set(accounts.filter(\.canAddTrades).map(\.id))
    }

    /// Automatic presentation waits for a resolved Free snapshot. A missing or
    /// still-loading entitlement is not treated as Free.
    private func confirmedFreeTier(profileID: ProfileID) -> Bool {
        if TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID) {
            return false
        }
        guard let record = PersistedEntitlementSnapshotStore.load(userID: profileID.rawValue) else {
            return false
        }
        return EntitlementSnapshotPolicy.decision(record) == .deny
    }
}

struct FreePlanAccountSlotOverlay: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var viewModel: FreePlanAccountSlotViewModel?
    @State private var selectedIDs: Set<String> = []
    @State private var userDidEditSelection = false

    func body(content: Content) -> some View {
        content
            .task {
                if viewModel == nil {
                    viewModel = FreePlanAccountSlotViewModel(
                        trades: appEnvironment.data.trades,
                        session: appEnvironment.data.session
                    )
                }
                await viewModel?.reload()
            }
            .onChange(of: AccountMutationStore.shared.revision) { _, _ in
                Task { await viewModel?.reload() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .billingEntitlementsDidRefresh)) { _ in
                Task { await viewModel?.reload() }
            }
            .onChange(of: FreePlanAccountSlotRequestStore.shared.manualOpenRequested) { _, requested in
                if requested {
                    viewModel?.manualPresentationRequested = true
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isPresented ?? false },
                set: { presented in
                    if !presented {
                        viewModel?.manualPresentationRequested = false
                        selectedIDs = []
                        userDidEditSelection = false
                    }
                }
            )) {
                if let viewModel {
                    FreePlanAccountSlotSheet(
                        accounts: viewModel.accounts,
                        selectedIDs: $selectedIDs,
                        userDidEditSelection: $userDidEditSelection,
                        isSaving: viewModel.isSaving,
                        errorMessage: viewModel.errorMessage,
                        onConfirm: {
                            let ids = selectedIDs.map { TradingAccountID($0) }
                            return await viewModel.confirmSelection(ids: ids)
                        }
                    )
                }
            }
    }
}

extension View {
    func freePlanAccountSlotOverlay() -> some View {
        modifier(FreePlanAccountSlotOverlay())
    }
}

private struct FreePlanAccountSlotSheet: View {
    let accounts: [TradingAccount]
    @Binding var selectedIDs: Set<String>
    @Binding var userDidEditSelection: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onConfirm: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Choose up to \(FreeTierPolicy.maxTradeEntryAccounts) accounts to keep active for new trades. Other accounts stay read-only with full history."
                    )
                    .font(.footnote)
                    .foregroundStyle(colors.secondaryText)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(colors.error)
                    }
                }

                Section {
                    ForEach(accounts, id: \.id.rawValue) { account in
                        let id = account.id.rawValue
                        let selected = selectedIDs.contains(id)
                        let disabled = !selected && selectedIDs.count >= FreeTierPolicy.maxTradeEntryAccounts
                        Button {
                            userDidEditSelection = true
                            if selected {
                                selectedIDs.remove(id)
                            } else if !disabled {
                                selectedIDs.insert(id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name)
                                        .foregroundStyle(colors.primaryText)
                                    Text(selectionSubtitle(for: account))
                                        .font(.caption)
                                        .foregroundStyle(colors.secondaryText)
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                        .disabled(disabled || isSaving)
                    }
                }
            }
            .experienceInsetGroupedListStyle(pageBackground: true)
            .toolbarBackground(colors.groupedBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Choose Active Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { restorePersistedSelectionIfNeeded() }
            .onChange(of: persistedSelectionSignature) { _, _ in
                restorePersistedSelectionIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task {
                            let ok = await onConfirm()
                            if ok { dismiss() }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationBackground(colors.groupedBackground)
        .presentationDetents([.large])
    }

    private var persistedSelectionSignature: String {
        accounts.map { "\($0.id.rawValue):\($0.canAddTrades)" }.joined(separator: "|")
    }

    private func restorePersistedSelectionIfNeeded() {
        guard !userDidEditSelection else { return }
        let activeIDs = accounts.filter(\.canAddTrades).map(\.id.rawValue)
        if activeIDs.count > FreeTierPolicy.maxTradeEntryAccounts {
            selectedIDs = []
        } else {
            selectedIDs = Set(activeIDs)
        }
    }

    private func selectionSubtitle(for account: TradingAccount) -> String {
        var parts = [TradingAccountDisplay.ownerDropdownModeLabel(account.mode)]
        if let number = TradingAccountDisplay.maskedAccountNumberSuffix(account.accountNumber) {
            parts.append(number)
        }
        return parts.joined(separator: " · ")
    }
}
