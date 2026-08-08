import Foundation

nonisolated protocol BillingRepository: Sendable {
    func status(for profileID: ProfileID) async throws -> BillingStatus
    func subscription(for profileID: ProfileID) async throws -> Subscription?
    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus
}
