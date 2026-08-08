import Foundation

nonisolated protocol LoadHomeUseCase: Sendable {
    func execute(profileID: ProfileID) async throws -> HomeDashboard
}

nonisolated protocol RefreshDashboardUseCase: Sendable {
    func execute(profileID: ProfileID) async throws -> HomeDashboard
}

nonisolated protocol GenerateInsightsUseCase: Sendable {
    func execute(profileID: ProfileID, interval: DateIntervalValue) async throws -> [Insight]
}
