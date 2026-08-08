import Foundation

nonisolated protocol LoadProfileUseCase: Sendable {
    func execute(profileID: ProfileID) async throws -> Profile
}
