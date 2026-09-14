import Foundation

/// Coalesced 401 recovery — wired from ``CompositionRoot`` into ``URLSessionNetworkClient``.
actor NetworkUnauthorizedRecovery {
    static let shared = NetworkUnauthorizedRecovery()

    enum Outcome: Sendable {
        case recovered
        case failedTransient
        case sessionEnded
        case noHandler
    }

    private var handler: (@Sendable () async -> Outcome)?
    private var inFlight: Task<Outcome, Never>?

    func configure(handler: @escaping @Sendable () async -> Outcome) {
        self.handler = handler
    }

    func recoverFromUnauthorized() async -> Outcome {
        guard let handler else { return .noHandler }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await handler() }
        inFlight = task
        defer { inFlight = nil }
        return await task.value
    }
}
