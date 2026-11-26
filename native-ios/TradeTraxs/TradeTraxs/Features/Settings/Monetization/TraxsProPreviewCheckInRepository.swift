import Foundation

/// Check-in reads for TraxsPro preview (canonical sample only).
nonisolated struct TraxsProPreviewCheckInRepository: TraderDailyCheckInRepository, Sendable {
    func checkIn(for profileID: ProfileID, date: String) async throws -> TraderDailyCheckIn? {
        DemoCanonicalDataset.checkIns().first { $0.checkInDate == date }
    }

    func checkIns(
        for profileID: ProfileID,
        from startDate: String,
        to endDate: String
    ) async throws -> [TraderDailyCheckIn] {
        DemoCanonicalDataset.checkIns().filter {
            $0.checkInDate >= startDate && $0.checkInDate <= endDate
        }
    }

    func upsert(
        _ draft: TraderDailyCheckInDraft,
        for profileID: ProfileID
    ) async throws -> TraderDailyCheckIn {
        throw DemoAuthRequired.error
    }
}