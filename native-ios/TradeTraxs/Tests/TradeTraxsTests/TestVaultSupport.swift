import Foundation
@testable import TradeTraxs

/// No-op Vault repository for unit tests.
struct TestVaultRepository: VaultRepository {
    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState] {
        Dictionary(uniqueKeysWithValues: refs.map { ($0, .notVaulted) })
    }

    func folders() async throws -> [VaultFolder] { [] }

    func createFolder(name: String) async throws -> VaultFolder {
        VaultFolder(
            id: VaultFolderID(UUID().uuidString),
            name: name,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder {
        VaultFolder(id: id, name: name, createdAt: Date(), updatedAt: Date())
    }

    func deleteFolder(id: VaultFolderID) async throws {}

    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem {
        VaultItem(
            id: VaultItemID(UUID().uuidString),
            ref: ref,
            createdAt: Date(),
            folderIDs: folderID.map { [$0] } ?? []
        )
    }

    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws {}
    func removeFromVault(vaultItemID: VaultItemID) async throws {}

    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage {
        VaultListPage(items: [], nextCursor: nil)
    }
}

extension VaultStore {
    static func testInstance() -> VaultStore {
        VaultStore(repository: TestVaultRepository())
    }
}
