import Foundation
import Observation

/// Session-scoped Vault state — mirrors ``EngagementStore`` optimistic patterns.
@Observable
@MainActor
final class VaultStore {
    private(set) var states: [VaultContentRef: VaultItemState] = [:]
    private(set) var folders: [VaultFolder] = []
    private(set) var lastConfirmationMessage: String?

    private let repository: any VaultRepository
    private var loadedRefs: Set<VaultContentRef> = []
    private var requestedRefs: Set<VaultContentRef> = []
    private var pendingRefs: Set<VaultContentRef> = []
    private var inFlightRefs: Set<VaultContentRef> = []
    private var prefetchTask: Task<Void, Never>?
    private var foldersLoaded = false
    private var foldersTask: Task<Void, Never>?

    private static let recentFolderKey = "vault.recentFolderID"

    init(repository: any VaultRepository) {
        self.repository = repository
    }

    func state(for ref: VaultContentRef) -> VaultItemState {
        states[ref] ?? .notVaulted
    }

    func prefetch(_ refs: [VaultContentRef]) {
        let fresh = refs.filter {
            !loadedRefs.contains($0) && !requestedRefs.contains($0)
        }
        guard !fresh.isEmpty else { return }
        requestedRefs.formUnion(fresh)
        pendingRefs.formUnion(fresh)
        pumpPrefetchIfNeeded()
    }

    func loadFoldersIfNeeded() {
        guard !foldersLoaded, foldersTask == nil else { return }
        foldersTask = Task { [weak self] in
            guard let self else { return }
            defer { self.foldersTask = nil }
            do {
                let loaded = try await self.repository.folders()
                self.folders = loaded
                self.foldersLoaded = true
            } catch {
                // Soft-fail — sheet can retry on next open.
            }
        }
    }

    func refreshFolders() async {
        do {
            folders = try await repository.folders()
            foldersLoaded = true
        } catch {
            ExperienceHaptics.play(.warning)
        }
    }

    func quickSave(_ ref: VaultContentRef) async -> Bool {
        await save(ref, folderID: nil, confirmation: "Added to Vault")
    }

    func save(_ ref: VaultContentRef, folderID: VaultFolderID?, confirmation: String) async -> Bool {
        guard !inFlightRefs.contains(ref) else { return false }
        if ref.contentID.hasPrefix("dev-") {
            applyOptimisticVault(ref: ref, folderID: folderID, provisionalID: VaultItemID("dev-vault-\(ref.contentID)"))
            loadedRefs.insert(ref)
            lastConfirmationMessage = confirmation
            return true
        }

        let previous = state(for: ref)
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        applyOptimisticVault(ref: ref, folderID: folderID, provisionalID: previous.vaultItemID ?? VaultItemID(UUID().uuidString))

        do {
            let item = try await repository.saveToVault(ref: ref, folderID: folderID)
            commitSuccessfulMutation(
                ref: ref,
                state: VaultItemState(isVaulted: true, vaultItemID: item.id, folderIDs: item.folderIDs)
            )
            if let folderID {
                Self.storeRecentFolderID(folderID)
            }
            lastConfirmationMessage = confirmation
            return true
        } catch {
            states[ref] = previous
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func addToFolder(_ ref: VaultContentRef, folderID: VaultFolderID, folderName: String) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else {
            return await save(ref, folderID: folderID, confirmation: "Added to \(folderName)")
        }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        var optimistic = previous
        if !optimistic.folderIDs.contains(folderID) {
            optimistic.folderIDs.append(folderID)
        }
        optimistic.isVaulted = true
        states[ref] = optimistic

        do {
            try await repository.addToFolder(vaultItemID: vaultItemID, folderID: folderID)
            commitSuccessfulMutation(ref: ref, state: optimistic)
            Self.storeRecentFolderID(folderID)
            lastConfirmationMessage = "Added to \(folderName)"
            return true
        } catch {
            states[ref] = previous
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func removeFromFolder(_ ref: VaultContentRef, folderID: VaultFolderID) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else { return false }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        var optimistic = previous
        optimistic.folderIDs.removeAll { $0 == folderID }
        states[ref] = optimistic

        do {
            try await repository.removeFromFolder(vaultItemID: vaultItemID, folderID: folderID)
            commitSuccessfulMutation(ref: ref, state: optimistic)
            lastConfirmationMessage = "Removed from folder"
            return true
        } catch {
            states[ref] = previous
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func removeFromVault(_ ref: VaultContentRef) async -> Bool {
        guard let vaultItemID = state(for: ref).vaultItemID else { return false }
        guard !inFlightRefs.contains(ref) else { return false }
        inFlightRefs.insert(ref)
        defer { inFlightRefs.remove(ref) }

        let previous = state(for: ref)
        states[ref] = .notVaulted

        do {
            try await repository.removeFromVault(vaultItemID: vaultItemID)
            commitSuccessfulMutation(ref: ref, state: .notVaulted)
            lastConfirmationMessage = "Removed from Vault"
            return true
        } catch {
            states[ref] = previous
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    func createFolder(named rawName: String) async -> VaultFolder? {
        guard let name = VaultSupport.normalizedFolderName(rawName) else { return nil }
        do {
            let folder = try await repository.createFolder(name: name)
            folders.append(folder)
            folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            foldersLoaded = true
            return folder
        } catch {
            ExperienceHaptics.play(.warning)
            return nil
        }
    }

    func recentFolderID() -> VaultFolderID? {
        guard let raw = UserDefaults.standard.string(forKey: Self.recentFolderKey) else { return nil }
        return VaultFolderID(raw)
    }

    func clearConfirmation() {
        lastConfirmationMessage = nil
    }

    func removeAll() {
        prefetchTask?.cancel()
        prefetchTask = nil
        foldersTask?.cancel()
        foldersTask = nil
        states = [:]
        folders = []
        loadedRefs = []
        requestedRefs = []
        pendingRefs = []
        inFlightRefs = []
        foldersLoaded = false
        lastConfirmationMessage = nil
    }

    // MARK: - Private

    private func applyOptimisticVault(
        ref: VaultContentRef,
        folderID: VaultFolderID?,
        provisionalID: VaultItemID
    ) {
        var snap = state(for: ref)
        snap.isVaulted = true
        snap.vaultItemID = snap.vaultItemID ?? provisionalID
        if let folderID, !snap.folderIDs.contains(folderID) {
            snap.folderIDs.append(folderID)
        }
        states[ref] = snap
    }

    private func commitSuccessfulMutation(ref: VaultContentRef, state: VaultItemState) {
        states[ref] = state
        loadedRefs.insert(ref)
        requestedRefs.insert(ref)
    }

    private func applyIncomingState(_ state: VaultItemState, for ref: VaultContentRef) {
        if inFlightRefs.contains(ref), let current = states[ref] {
            var merged = state
            merged.isVaulted = current.isVaulted
            merged.vaultItemID = current.vaultItemID ?? merged.vaultItemID
            merged.folderIDs = current.folderIDs.isEmpty ? merged.folderIDs : current.folderIDs
            states[ref] = merged
        } else {
            states[ref] = state
        }
        loadedRefs.insert(ref)
        requestedRefs.insert(ref)
        pendingRefs.remove(ref)
    }

    private func pumpPrefetchIfNeeded() {
        guard prefetchTask == nil else { return }
        guard !pendingRefs.isEmpty else { return }

        prefetchTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingRefs.isEmpty {
                let batch = Array(self.pendingRefs)
                self.pendingRefs.removeAll()
                do {
                    let map = try await self.repository.state(for: batch)
                    guard !Task.isCancelled else { return }
                    for ref in batch {
                        let snap = map[ref] ?? .notVaulted
                        self.applyIncomingState(snap, for: ref)
                    }
                } catch {
                    self.requestedRefs.subtract(batch)
                }
            }
            self.prefetchTask = nil
            self.pumpPrefetchIfNeeded()
        }
    }

    private static func storeRecentFolderID(_ id: VaultFolderID) {
        UserDefaults.standard.set(id.rawValue, forKey: recentFolderKey)
    }
}
