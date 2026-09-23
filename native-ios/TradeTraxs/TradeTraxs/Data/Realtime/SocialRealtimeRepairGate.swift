import Foundation

/// Phase 10F social missed-event repair — correctness infrastructure (not a Release product flag).
nonisolated enum SocialRealtimeRepairGate {
    static var isEnabled: Bool { true }
}
