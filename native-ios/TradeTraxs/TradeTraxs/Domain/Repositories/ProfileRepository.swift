import Foundation

nonisolated protocol ProfileRepository: Sendable {
    func currentUser() async throws -> User
    func profile(id: ProfileID) async throws -> Profile
    /// Bounded batch — PostgREST `id=in.(…)`. Prefer ``SessionProfileStore`` at call sites.
    func profiles(ids: [ProfileID]) async throws -> [Profile]
    func profile(username: String) async throws -> Profile
    func updateProfile(_ profile: Profile) async throws -> Profile
    func stats(for profileID: ProfileID) async throws -> ProfileStats
    /// Web Profile wall — `profile_posts` (not feed `posts`).
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post>
    /// Single wall post for detail destinations (`profile_posts`).
    func wallPost(id: PostID) async throws -> Post
    /// Web Profile “Create Post” — inserts into `profile_posts` (not feed `posts`).
    func createWallPost(authorID: ProfileID, content: String, imageURL: String?) async throws -> Post
    /// Deletes a wall post the viewer owns (`profile_posts`).
    func deleteWallPost(id: PostID) async throws
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState
    func follow(from viewer: ProfileID, to target: ProfileID) async throws
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile>
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile>
    func creator(for profileID: ProfileID) async throws -> Creator?
}

extension ProfileRepository {
    func createWallPost(authorID: ProfileID, content: String, imageURL: String?) async throws -> Post {
        throw AppError.notImplemented(feature: "createWallPost")
    }

    func deleteWallPost(id: PostID) async throws {
        throw AppError.notImplemented(feature: "deleteWallPost")
    }

    /// Default: sequential singles (tests / incomplete backends). Production overrides with `in.()`.
    func profiles(ids: [ProfileID]) async throws -> [Profile] {
        var result: [Profile] = []
        result.reserveCapacity(ids.count)
        for id in Set(ids) {
            if let profile = try? await profile(id: id) {
                result.append(profile)
            }
        }
        return result
    }
}
