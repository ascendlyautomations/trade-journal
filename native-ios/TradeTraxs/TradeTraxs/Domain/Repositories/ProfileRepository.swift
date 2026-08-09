import Foundation

nonisolated protocol ProfileRepository: Sendable {
    func currentUser() async throws -> User
    func profile(id: ProfileID) async throws -> Profile
    func profile(username: String) async throws -> Profile
    func updateProfile(_ profile: Profile) async throws -> Profile
    func stats(for profileID: ProfileID) async throws -> ProfileStats
    /// Web Profile wall — `profile_posts` (not feed `posts`).
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post>
    /// Single wall post for detail destinations (`profile_posts`).
    func wallPost(id: PostID) async throws -> Post
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState
    func follow(from viewer: ProfileID, to target: ProfileID) async throws
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile>
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile>
    func creator(for profileID: ProfileID) async throws -> Creator?
}
