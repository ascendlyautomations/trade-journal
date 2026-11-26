import Foundation

/// In-memory copy-trading groups for owner account filter menus (same Supabase tables as web).
@MainActor
final class CopyTradingGroupsMenuCache {
    static let shared = CopyTradingGroupsMenuCache()

    private var groupsByProfile: [ProfileID: [CopyTradingGroup]] = [:]
    private var inFlight: Set<ProfileID> = []

    private init() {}

    func groups(for profileID: ProfileID) -> [CopyTradingGroup] {
        groupsByProfile[profileID] ?? []
    }

    func isLoading(profileID: ProfileID?) -> Bool {
        guard let profileID else { return false }
        return inFlight.contains(profileID)
            && groupsByProfile[profileID] == nil
    }

    func loadIfNeeded(
        profileID: ProfileID,
        repository: any CopyTradingGroupRepository
    ) async {
        if groupsByProfile[profileID] != nil { return }
        if inFlight.contains(profileID) { return }
        inFlight.insert(profileID)
        defer { inFlight.remove(profileID) }
        let loaded = (try? await repository.groups(for: profileID)) ?? []
        groupsByProfile[profileID] = loaded
    }

    func invalidate(profileID: ProfileID) {
        groupsByProfile[profileID] = nil
        inFlight.remove(profileID)
    }

    /// Clears cached groups and refetches from the repository (after settings mutations).
    func reload(
        profileID: ProfileID,
        repository: any CopyTradingGroupRepository
    ) async {
        invalidate(profileID: profileID)
        await loadIfNeeded(profileID: profileID, repository: repository)
    }
}