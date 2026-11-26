import Foundation
import Observation

@Observable
@MainActor
final class CopyTradingAccountsViewModel {
    private(set) var groups: [CopyTradingGroup] = []
    private(set) var accounts: [TradingAccount] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    var editor: Editor?
    var pendingDelete: CopyTradingGroup?

    struct Editor: Identifiable {
        let id: String
        var groupID: String?
        var name: String
        var selectedAccountIDs: [String]

        static func create() -> Editor {
            Editor(id: "create", groupID: nil, name: "", selectedAccountIDs: [])
        }

        static func edit(_ group: CopyTradingGroup) -> Editor {
            Editor(
                id: group.id,
                groupID: group.id,
                name: group.name,
                selectedAccountIDs: group.accountIDs
            )
        }
    }

    private let groupsRepository: any CopyTradingGroupRepository
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private var loadedUserID: ProfileID?

    init(
        groupsRepository: any CopyTradingGroupRepository,
        trades: any TradeRepository,
        session: any SessionProviding
    ) {
        self.groupsRepository = groupsRepository
        self.trades = trades
        self.session = session
    }

    var selectableAccounts: [TradingAccount] {
        accounts
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func accountName(for id: String) -> String {
        accounts.first(where: { $0.id.rawValue == id })?.name ?? "Linked account"
    }

    func linkedAccounts(for group: CopyTradingGroup) -> [TradingAccount] {
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id.rawValue, $0) })
        return group.accountIDs.compactMap { byID[$0] }
    }

    func loadIfNeeded() {
        guard !isLoading else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard let userID = await currentProfileID() else {
            groups = []
            accounts = []
            loadedUserID = nil
            return
        }
        if loadedUserID != userID {
            groups = []
            accounts = []
        }
        isLoading = groups.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            accounts = try await trades.accounts(for: userID)
            groups = try await groupsRepository.groups(for: userID)
            loadedUserID = userID
        } catch {
            groups = []
            errorMessage = "Couldn't load copy trading accounts."
        }
    }

    func beginCreate() {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        if ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: profileID) {
            return
        }
        editor = .create()
    }

    func beginEdit(_ group: CopyTradingGroup) {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        if ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: profileID) {
            return
        }
        editor = .edit(group)
    }

    func toggleAccount(_ accountID: String) {
        guard var editor else { return }
        if let index = editor.selectedAccountIDs.firstIndex(of: accountID) {
            editor.selectedAccountIDs.remove(at: index)
        } else {
            editor.selectedAccountIDs.append(accountID)
        }
        self.editor = editor
    }

    func saveEditor() async -> Bool {
        guard let editor, !isSaving else { return false }
        if let userID = await currentProfileID(),
           ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: userID)
        {
            return false
        }
        let owned = Set(accounts.map(\.id.rawValue))
        if let message = CopyTradingGroupRules.validationError(
            name: editor.name,
            accountIDs: editor.selectedAccountIDs,
            ownedAccountIDs: owned
        ) {
            errorMessage = message
            return false
        }
        guard let userID = await currentProfileID() else {
            errorMessage = "Sign in to manage copy trading accounts."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let name = editor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountIDs = editor.selectedAccountIDs
        do {
            if let groupID = editor.groupID {
                _ = try await groupsRepository.update(
                    userID: userID,
                    groupID: groupID,
                    name: name,
                    accountIDs: accountIDs
                )
            } else {
                _ = try await groupsRepository.create(
                    userID: userID,
                    name: name,
                    accountIDs: accountIDs
                )
            }
            self.editor = nil
            await refresh()
            await notifyCopyGroupsChanged(deletedGroupID: nil, userID: userID)
            return true
        } catch let failure as CopyTradingGroupFailure {
            if ProLimitPresentation.presentUpgradeIfProGate(failure) {
                return false
            }
            errorMessage = message(for: failure)
            return false
        } catch {
            if ProLimitPresentation.presentUpgradeIfProGate(error) {
                return false
            }
            errorMessage = "Couldn't save this copy trading group."
            return false
        }
    }

    func confirmDelete() async {
        guard let groupToDelete = pendingDelete, !isSaving else { return }
        guard let userID = await currentProfileID() else { return }
        if ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: userID) {
            self.pendingDelete = nil
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await groupsRepository.delete(userID: userID, groupID: groupToDelete.id)
            let deletedID = groupToDelete.id
            self.pendingDelete = nil
            await refresh()
            await notifyCopyGroupsChanged(deletedGroupID: deletedID, userID: userID)
        } catch let failure as CopyTradingGroupFailure {
            if ProLimitPresentation.presentUpgradeIfProGate(failure) {
                return
            }
            errorMessage = message(for: failure)
        } catch {
            if ProLimitPresentation.presentUpgradeIfProGate(error) {
                return
            }
            errorMessage = "Couldn't delete this copy trading group."
        }
    }

    func requestDelete(_ group: CopyTradingGroup) {
        let profileID = SessionBootstrapStore.shared.last.map { ProfileID($0.data.viewer.id) }
        if ProAccessGate.presentFeatureIfNeeded(.copyTrading, profileID: profileID) {
            return
        }
        pendingDelete = group
    }

    private func currentProfileID() async -> ProfileID? {
        guard let userID = await session.currentUserID else { return nil }
        return ProfileID(userID.rawValue)
    }

    private func message(for failure: CopyTradingGroupFailure) -> String {
        switch failure {
        case .duplicateName:
            return "A group with this name already exists"
        case .notFound:
            return "Copy trading group not found"
        case .message(let text):
            return text
        }
    }

    private func notifyCopyGroupsChanged(deletedGroupID: String?, userID: ProfileID) async {
        await OwnerAccountFilterDropdownCopyTradingBridge.reloadGroupsAfterMutation(profileID: userID)
        CopyTradingGroupsMutationStore.shared.noteGroupsChanged(deletedGroupID: deletedGroupID)
    }
}
