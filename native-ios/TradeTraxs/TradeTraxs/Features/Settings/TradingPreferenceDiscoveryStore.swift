import Foundation
import Observation

@MainActor
@Observable
final class TradingPreferenceDiscoveryStore {
    static let shared = TradingPreferenceDiscoveryStore()

    private(set) var response: PreferenceDiscoveryResponse?
    /// Preferences row exists / user has saved Trading Rules at least once.
    private(set) var configured = false
    /// At least one active trading rule check is configured (compliance engine).
    private(set) var hasConfiguredRules = false
    private(set) var hasTrade = false
    private(set) var ready = false
    /// Hides the quieter dashboard card for the rest of this launch after the one-time invite.
    private(set) var holdQuietDashboard = false

    private var userID: ProfileID?
    private var repository: (any TradingPreferencesRepository)?

    private init() {}

    func refresh(userID: ProfileID, repository: any TradingPreferencesRepository) async {
        if AppLaunchController.shared.isDemoExperienceActive {
            self.userID = userID
            self.repository = repository
            response = .dismissed
            configured = true
            hasConfiguredRules = true
            ready = true
            return
        }
        self.userID = userID
        self.repository = repository
        do {
            if let cached = TradingRulesCompliancePreferencesCache.cachedContext(for: userID) {
                applyPreferenceContext(cached)
                async let discovery = repository.discovery(for: userID)
                async let traded = repository.hasJournalTrade(for: userID)
                response = try await discovery
                hasTrade = try await traded
            } else {
                async let discovery = repository.discovery(for: userID)
                async let traded = repository.hasJournalTrade(for: userID)
                let preferenceOutcome = await TradingRulesCompliancePreferencesCache.load(
                    for: userID,
                    repository: repository,
                    injected: nil
                )
                response = try await discovery
                hasTrade = try await traded
                if case .loaded(let context) = preferenceOutcome {
                    applyPreferenceContext(context)
                } else {
                    configured = false
                    hasConfiguredRules = false
                }
            }
        } catch {
            response = nil
            configured = false
            hasConfiguredRules = false
        }
        ready = true
    }

    func bind(userID: ProfileID, repository: any TradingPreferencesRepository) {
        self.userID = userID
        self.repository = repository
    }

    func noteHasTrade() {
        hasTrade = true
    }

    func placement(
        tourEligible: Bool,
        tourSettled: Bool,
        tourBlocking: Bool,
        hasTrade localHasTrade: Bool
    ) -> PreferenceDiscoveryPlacement? {
        guard ready else { return nil }
        return PreferenceDiscoveryDecision.placement(
            configured: configured,
            response: response,
            tourEligible: tourEligible,
            tourSettled: tourSettled,
            tourBlocking: tourBlocking,
            hasTrade: hasTrade || localHasTrade
        )
    }

    func record(_ next: PreferenceDiscoveryResponse) async {
        guard let userID, let repository else { return }
        if next == .skipped { holdQuietDashboard = true }
        if let current = response {
            if current.rank >= next.rank { return }
        }
        response = next
        if next == .completed { configured = true }
        if let saved = try? await repository.recordDiscovery(next, for: userID) {
            response = saved
            if saved == .completed { configured = true }
        }
        if next == .completed, let cached = TradingRulesCompliancePreferencesCache.cachedContext(for: userID) {
            hasConfiguredRules = TradingRulesComplianceSupport.hasConfiguredRules(context: cached)
        }
    }

    private func applyPreferenceContext(_ context: PreferenceRuleContext) {
        configured = context.global?.updatedAt != nil
        hasConfiguredRules = TradingRulesComplianceSupport.hasConfiguredRules(context: context)
    }
}
