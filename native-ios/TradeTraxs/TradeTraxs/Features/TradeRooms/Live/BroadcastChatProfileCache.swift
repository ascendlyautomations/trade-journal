import Foundation

@MainActor
final class BroadcastChatProfileCache {
    private var cache: [String: Profile] = [:]
    private var profileLookup: (([ProfileID]) async throws -> [Profile])?

    func configure(profileLookup: @escaping ([ProfileID]) async throws -> [Profile]) {
        self.profileLookup = profileLookup
    }

    func clear() {
        cache.removeAll()
    }

    func profile(forUserId userId: String) -> Profile? {
        cache[userId]
    }

    func hydrate(userIds: [String]) async {
        guard let profileLookup else { return }
        let missing = userIds.filter { cache[$0] == nil }
        guard !missing.isEmpty else { return }

        let profileIDs = missing.compactMap { ProfileID(rawValue: $0) }
        guard !profileIDs.isEmpty else { return }

        do {
            let profiles = try await profileLookup(profileIDs)
            for profile in profiles {
                cache[profile.userID.rawValue] = profile
                cache[profile.id.rawValue] = profile
            }
        } catch {
            // fall back to message display names only
        }
    }
}
