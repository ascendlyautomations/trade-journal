import Foundation

nonisolated protocol FollowRequestRepository: Sendable {
    func pendingRequests() async throws -> [FollowRequest]
    func approve(id: FollowRequestID) async throws
    func decline(id: FollowRequestID) async throws
}
