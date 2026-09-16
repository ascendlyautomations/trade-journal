import Foundation
import Observation

/// Session-scoped signal that broker connections, links, or imports changed (no polling).
@Observable
@MainActor
final class BrokerIntegrationMutationStore {
    static let shared = BrokerIntegrationMutationStore()

    private(set) var revision: Int = 0

    private init() {}

    func noteBrokerIntegrationChanged() {
        revision += 1
    }
}
