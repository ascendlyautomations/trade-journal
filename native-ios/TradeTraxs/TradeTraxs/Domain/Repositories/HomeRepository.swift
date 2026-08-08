import Foundation

nonisolated protocol HomeRepository: Sendable {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard
    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary
}
