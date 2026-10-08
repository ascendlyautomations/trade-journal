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

    init(trades: any TradeRepository, session: any SessionProviding) {
        self.trades = trades
        self.session = session
    }

    func reload() async {
        guard let userID = await session.currentUserID else {
            accounts = []
            return
        }
        let profileID = ProfileID(userID.rawValue)
        if TradeEntryEntitlementGate.viewerHasTraxProAccess(profileID: profileID) {
            accounts = []
            return
        }
        if let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            accounts = cached
            return
        }
        do {
            accounts = try await trades.accounts(for: profileID)
        } catch {
            accounts = []
        }
    }

    var needsAutomaticPresentation: Bool {
        guard let profileID = accounts.first?.ownerProfileID else { return false }
        let tier = TradeEntryEntitlementGate.viewerTier(profileID: profileID)
        return FreePlanTradeAccountPolicy.needsSlotSelection(accounts: accounts, viewerTier: tier)
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
        guard let profileID = accounts.first?.ownerProfileID else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await trades.selectFreePlanTradeAccounts(ownerID: profileID, accountIDs: ids)
            manualPresentationRequested = false
            FreePlanAccountSlotRequestStore.shared.manualOpenRequested = false
            accounts = try await trades.accounts(for: profileID)
            SessionAccountsStore.shared.seed(accounts, for: profileID, detailCache: nil)
            AccountMutationStore.shared.noteAccountsChanged(allAccounts: accounts, viewerID: profileID)
            return true
        } catch {
            if !ProLimitPresentation.presentUpgradeIfProLimit(error) {
                errorMessage = UserFacingError.message(for: error)
            }
            return false
        }
    }
}

struct FreePlanAccountSlotOverlay: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var viewModel: FreePlanAccountSlotViewModel?
    @State private var selectedIDs: Set<String> = []

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
                    }
                }
            )) {
                if let viewModel {
                    FreePlanAccountSlotSheet(
                        accounts: viewModel.accounts,
                        selectedIDs: $selectedIDs,
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
                                    Text(account.mode.rawValue.capitalized)
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
            .navigationTitle("Choose Active Accounts")
            .navigationBarTitleDisplayMode(.inline)
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
        .presentationDetents([.large])
    }
}
