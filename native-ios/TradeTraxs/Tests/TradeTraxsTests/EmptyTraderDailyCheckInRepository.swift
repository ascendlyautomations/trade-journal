import Foundation
@testable import TradeTraxs

struct EmptyTraderDailyCheckInRepository: TraderDailyCheckInRepository {
    func checkIn(for profileID: ProfileID, date: String) async throws -> TraderDailyCheckIn? { nil }

    func checkIns(
        for profileID: ProfileID,
        from startDate: String,
        to endDate: String
    ) async throws -> [TraderDailyCheckIn] { [] }

    func upsert(
        _ draft: TraderDailyCheckInDraft,
        for profileID: ProfileID
    ) async throws -> TraderDailyCheckIn {
        throw AppError.notImplemented(feature: "EmptyTraderDailyCheckInRepository.upsert")
    }
}
