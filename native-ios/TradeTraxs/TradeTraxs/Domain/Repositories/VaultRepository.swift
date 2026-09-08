import Foundation

protocol VaultRepository: Sendable {
    func state(for refs: [VaultContentRef]) async throws -> [VaultContentRef: VaultItemState]
    func folders() async throws -> [VaultFolder]
    func createFolder(name: String) async throws -> VaultFolder
    func renameFolder(id: VaultFolderID, name: String) async throws -> VaultFolder
    func deleteFolder(id: VaultFolderID) async throws
    func saveToVault(ref: VaultContentRef, folderID: VaultFolderID?) async throws -> VaultItem
    func addToFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws
    func removeFromFolder(vaultItemID: VaultItemID, folderID: VaultFolderID) async throws
    func removeFromVault(vaultItemID: VaultItemID) async throws
    func listItems(
        filter: VaultContentFilter,
        folderID: VaultFolderID?,
        cursor: String?,
        limit: Int
    ) async throws -> VaultListPage
}
