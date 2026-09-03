import Foundation

/// Session-scoped daily check-ins for dashboard psychology analytics.
@MainActor
final class SessionDailyCheckInsStore {
    static let shared = SessionDailyCheckInsStore()

    private(set) var checkIns: [TraderDailyCheckIn] = []
    private var profileID: ProfileID?
    private var loadedRange: (start: String, end: String)?

    private init() {}

    func seed(_ checkIns: [TraderDailyCheckIn], for profileID: ProfileID, range: (start: String, end: String)) {
        self.profileID = profileID
        self.checkIns = checkIns
        self.loadedRange = range
    }

    func upsert(_ checkIn: TraderDailyCheckIn) {
        guard profileID == checkIn.ownerProfileID else { return }
        if var range = loadedRange {
            if checkIn.checkInDate < range.start { range.start = checkIn.checkInDate }
            if checkIn.checkInDate > range.end { range.end = checkIn.checkInDate }
            loadedRange = range
        }
        if let index = checkIns.firstIndex(where: { $0.checkInDate == checkIn.checkInDate }) {
            checkIns[index] = checkIn
        } else {
            checkIns.append(checkIn)
            checkIns.sort { $0.checkInDate > $1.checkInDate }
        }
    }

    func invalidate() {
        checkIns = []
        profileID = nil
        loadedRange = nil
    }

    func needsLoad(
        for profileID: ProfileID,
        startDate: String,
        endDate: String
    ) -> Bool {
        guard self.profileID == profileID, let loadedRange else { return true }
        return loadedRange.start > startDate || loadedRange.end < endDate
    }
}
