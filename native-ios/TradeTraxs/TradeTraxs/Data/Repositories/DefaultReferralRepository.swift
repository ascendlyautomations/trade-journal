import Foundation

nonisolated struct DefaultReferralRepository: ReferralRepository {
    private let supabase: SupabaseInfrastructure
    private let cache: CacheStack

    init(supabase: SupabaseInfrastructure, cache: CacheStack = .placeholder()) {
        self.supabase = supabase
        self.cache = cache
    }

    func referral(for profileID: ProfileID) async throws -> Referral? {
        let dto: ProfileDTO.Profile = try await supabase.database.selectOne(
            ProfileDTO.Profile.self,
            from: "profiles",
            query: [
                SupabaseQuery.select("id,referral_code,created_at"),
                SupabaseQuery.eq("id", profileID.rawValue),
            ]
        )
        guard let code = dto.referral_code, !code.isEmpty else { return nil }
        return Referral(
            id: ReferralID(profileID.rawValue),
            referrerProfileID: profileID,
            code: code,
            inviteeProfileID: nil,
            rewardDescription: nil,
            createdAt: ISO8601.date(from: dto.created_at) ?? Date(),
            completedAt: nil
        )
    }

    func apply(code: String, invitee: ProfileID) async throws -> Referral {
        struct Body: Encodable { var referred_by: String }
        _ = try await supabase.database.update(
            Body(referred_by: code.uppercased()),
            table: "profiles",
            query: [SupabaseQuery.eq("id", invitee.rawValue)],
            returning: ProfileDTO.Profile.self
        )
        return Referral(
            id: ReferralID("\(invitee.rawValue)-\(code)"),
            referrerProfileID: invitee,
            code: code.uppercased(),
            inviteeProfileID: invitee,
            rewardDescription: nil,
            createdAt: Date(),
            completedAt: Date()
        )
    }
}
