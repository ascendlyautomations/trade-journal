import Foundation
import Observation

@MainActor
@Observable
final class TradingRulesComplianceSessionStore {
    static let shared = TradingRulesComplianceSessionStore()

    private(set) var ready = false
    private(set) var result: TradingRulesComplianceAnalytics.Result?
    private(set) var scopeLabel = ""
    private(set) var profileID: ProfileID?
    private(set) var scopeFingerprint: String?
    private(set) var hasConfiguredRules = false
    private(set) var loadError: String?
    private(set) var scopedTradeCount = 0
    private(set) var insufficientScope = false
    private(set) var eligibility: TradingRulesComplianceEligibility.Summary?
    private(set) var personalInsights: [DashboardInsightItem] = []
    private(set) var contentRevision = 0
    /// Input fingerprint of the snapshot currently on screen. Nil when the store is empty or was invalidated.
    private(set) var inputFingerprint: String?
    private(set) var publishGeneration: UInt64 = 0
    /// False when compliance is shown from a provisional snapshot (e.g. incomplete owner history).
    private(set) var isAuthoritative = true

    var isProvisionalCompliance: Bool {
        ready && result != nil && !isAuthoritative
    }

    private init() {}

    /// Publishes only when `generation` is still the latest coordinator token.
    /// A missing or failed preference load cannot replace a configured-rules snapshot for the same profile.
    @discardableResult
    func commit(
        output: TradingRulesComplianceSnapshotBuilder.Output,
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        ready: Bool,
        inputFingerprint: String?,
        generation: UInt64,
        preferencesUnavailable: Bool
    ) -> Bool {
        guard TradingRulesComplianceRecomputeCoordinator.isCurrent(generation) else { return false }
        if preferencesUnavailable,
           !output.hasConfiguredRules,
           retainsConfiguredRules(for: profileID)
        {
            return false
        }
        publish(
            output: output,
            profileID: profileID,
            scope: scope,
            ready: ready,
            inputFingerprint: inputFingerprint,
            generation: generation
        )
        return true
    }

    func publish(
        output: TradingRulesComplianceSnapshotBuilder.Output,
        profileID: ProfileID,
        scope: PsychologyAnalyticsScopeResolver.Resolved,
        ready: Bool,
        inputFingerprint: String? = nil,
        generation: UInt64 = 0
    ) {
        let error = output.preferencesError ?? output.tradesError
        self.ready = ready
        self.profileID = profileID
        self.scopeFingerprint = scope.fingerprint
        self.scopeLabel = scope.label
        self.hasConfiguredRules = output.hasConfiguredRules
        self.result = output.insufficientScope ? nil : output.result
        self.loadError = error
        self.scopedTradeCount = output.scopedTradeCount
        self.insufficientScope = output.insufficientScope
        self.eligibility = output.eligibility
        self.personalInsights = output.personalInsights
        self.inputFingerprint = inputFingerprint
        self.publishGeneration = generation
        isAuthoritative = output.isAuthoritative
        contentRevision += 1
    }

    func publish(
        ready: Bool,
        profileID: ProfileID?,
        scopeFingerprint: String?,
        scopeLabel: String,
        hasConfiguredRules: Bool,
        result: TradingRulesComplianceAnalytics.Result?,
        error: String?,
        scopedTradeCount: Int = 0,
        insufficientScope: Bool = false,
        inputFingerprint: String? = nil,
        generation: UInt64 = 0,
        isAuthoritative: Bool = true
    ) {
        self.ready = ready
        self.profileID = profileID
        self.scopeFingerprint = scopeFingerprint
        self.scopeLabel = scopeLabel
        self.hasConfiguredRules = hasConfiguredRules
        self.result = insufficientScope ? nil : result
        self.loadError = error
        self.scopedTradeCount = scopedTradeCount
        self.insufficientScope = insufficientScope
        self.eligibility = nil
        self.personalInsights = []
        self.inputFingerprint = inputFingerprint
        self.publishGeneration = generation
        self.isAuthoritative = isAuthoritative
        contentRevision += 1
    }

    func reset() {
        result = nil
        eligibility = nil
        personalInsights = []
        publish(
            ready: false,
            profileID: nil,
            scopeFingerprint: nil,
            scopeLabel: "",
            hasConfiguredRules: false,
            result: nil,
            error: nil
        )
    }

    func clearIfProfileMismatch(_ profileID: ProfileID) {
        guard let current = self.profileID, current != profileID else { return }
        TradingRulesComplianceRecomputeCoordinator.resetForSessionBoundary()
    }

    func matchesCachedPresentation(profileID: ProfileID, scopeFingerprint: String) -> Bool {
        self.profileID == profileID && self.scopeFingerprint == scopeFingerprint
    }

    /// True when this profile, scope, and input fingerprint are what the card is already showing.
    func matchesPublishedSnapshot(
        profileID: ProfileID,
        scopeFingerprint: String,
        inputFingerprint: String
    ) -> Bool {
        ready
            && self.profileID == profileID
            && self.scopeFingerprint == scopeFingerprint
            && self.inputFingerprint == inputFingerprint
    }

    /// Configured rules are on screen for this profile. A nil preference load must not clear them.
    func retainsConfiguredRules(for profileID: ProfileID) -> Bool {
        ready && self.profileID == profileID && hasConfiguredRules
    }

    var dashboardAdherencePercent: Double? {
        guard !insufficientScope else { return nil }
        return result?.score.adherencePercent
    }

    var dashboardViolationCount: Int? {
        guard !insufficientScope, let result else { return nil }
        return result.score.violated
    }
}
