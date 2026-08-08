import Foundation

nonisolated protocol ReferralRepository: Sendable {
    func referral(for profileID: ProfileID) async throws -> Referral?
    func apply(code: String, invitee: ProfileID) async throws -> Referral
}
