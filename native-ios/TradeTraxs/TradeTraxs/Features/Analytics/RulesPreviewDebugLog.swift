import Foundation

#if DEBUG
/// Xcode console filter: `[RulesPreview]`
enum RulesPreviewDebugLog {
    static func log(_ message: String) {
        print("[RulesPreview] \(message)")
    }

    static func storeID(_ store: TradingRulesComplianceSessionStore) -> String {
        String(describing: ObjectIdentifier(store))
    }

    static func describe(
        _ environment: TraxsProPreviewDataEnvironment?
    ) -> String {
        guard let environment else { return "previewEnvironment=nil" }
        return [
            "viewer=\(environment.viewer.rawValue)",
            "feature=\(environment.feature)",
            "generation=\(environment.generation)",
            "rulesStore=\(storeID(environment.rulesPresentationStore))",
            "detailCache=\(ObjectIdentifier(environment.data.detailCache))",
            "trades=\(environment.trades.count)",
            "accounts=\(environment.accounts.count)",
        ].joined(separator: " ")
    }

    static func describeConfiguredRules(context: PreferenceRuleContext?) -> String {
        guard let context else { return "preferenceContext=nil" }
        let families = TradingRulesComplianceDiagnostics.configuredRuleFamilyCount(context: context)
        return "preferenceContext=loaded configuredRuleFamilies=\(families)"
    }

    static func describe(scope: PsychologyAnalyticsScopeResolver.Resolved) -> String {
        "scope fingerprint=\(scope.fingerprint) label=\(scope.label)"
    }

    static func describe(scopeFilter: DashboardClientScopeFilter) -> String {
        "accountFilter=\(scopeFilter.accountFilter) dateRange=\(scopeFilter.dateRange) accountMode=\(scopeFilter.accountMode) showPublicOnly=\(scopeFilter.showPublicOnly)"
    }

    static func describe(output: TradingRulesComplianceSnapshotBuilder.Output) -> String {
        let result = output.result.map {
            "adherence=\($0.score.adherencePercent.map { String(format: "%.1f", $0) } ?? "nil") evaluated=\($0.score.evaluated) followed=\($0.score.followed) violated=\($0.score.violated)"
        } ?? "result=nil"
        let eligibility = output.eligibility.map {
            "eligibility scopedTrades=\($0.scopedTradeCount) withActiveRules=\($0.tradesWithActiveRulesAtEntry) usesRevision=\($0.usesRevisionHistory)"
        } ?? "eligibility=nil"
        return [
            "hasConfiguredRules=\(output.hasConfiguredRules)",
            "scopedTradeCount=\(output.scopedTradeCount)",
            "ownerTradeCount=\(output.ownerTradeCount)",
            "insufficientScope=\(output.insufficientScope)",
            "historyComplete=\(output.historyComplete)",
            "isAuthoritative=\(output.isAuthoritative)",
            "preferencesError=\(output.preferencesError ?? "nil")",
            "tradesError=\(output.tradesError ?? "nil")",
            result,
            eligibility,
        ].joined(separator: " ")
    }

    static func describe(session: TradingRulesComplianceSessionStore) -> String {
        [
            "store=\(storeID(session))",
            "ready=\(session.ready)",
            "hasConfiguredRules=\(session.hasConfiguredRules)",
            "insufficientScope=\(session.insufficientScope)",
            "scopedTradeCount=\(session.scopedTradeCount)",
            "profileID=\(session.profileID?.rawValue ?? "nil")",
            "scopeFingerprint=\(session.scopeFingerprint ?? "nil")",
            "result=\(session.result == nil ? "nil" : "present")",
            "publishGeneration=\(session.publishGeneration)",
            "contentRevision=\(session.contentRevision)",
            "loadError=\(session.loadError ?? "nil")",
            "isAuthoritative=\(session.isAuthoritative)",
        ].joined(separator: " ")
    }

    static func dashboardSectionBranch(
        compliancePresentation: ProPremiumFeaturePresentation,
        session: TradingRulesComplianceSessionStore
    ) -> String {
        switch compliancePresentation {
        case .verifyingEntitlement:
            return "outerHidden(verifyingEntitlement)"
        case .unrestricted, .lockedPreview:
            if !session.ready { return "loadingPlaceholder" }
            if !session.hasConfiguredRules { return "setupCard" }
            if session.insufficientScope { return "filteredEmptyCard" }
            if session.result != nil { return "complianceCard" }
            return "emptyCard"
        }
    }

    static func detailViewBranch(session: TradingRulesComplianceSessionStore) -> String {
        if session.loadError != nil { return "errorState" }
        if !session.ready { return "loadingSpinner" }
        if !session.hasConfiguredRules { return "noRulesConfigured" }
        if session.insufficientScope { return "insufficientScope" }
        if session.result != nil { return "scrollContent" }
        if session.scopedTradeCount == 0 { return "emptyNoTradesInScope" }
        return "loadingAwaitingResult"
    }

    static func homeRouteBranch(
        embeddedInTraxsProPreview: Bool,
        showsEntitlementVerification: Bool,
        canShowDetail: Bool,
        isRefreshing: Bool,
        loadOutcome: TradingRulesComplianceLoadOutcome,
        store: TradingRulesComplianceSessionStore
    ) -> String {
        if showsEntitlementVerification { return "entitlementVerification" }
        if canShowDetail { return "detailView(\(detailViewBranch(session: store)))" }
        if isRefreshing { return "loadingSpinner(refreshing)" }
        if case .failed = loadOutcome { return "errorState" }
        return "loadingSpinner(waitingSnapshot)"
    }
}
#else
enum RulesPreviewDebugLog {
    static func log(_ message: String) {}
    static func storeID(_ store: TradingRulesComplianceSessionStore) -> String { "" }
    static func describe(_ environment: TraxsProPreviewDataEnvironment?) -> String { "" }
    static func describeConfiguredRules(context: PreferenceRuleContext?) -> String { "" }
    static func describe(scope: PsychologyAnalyticsScopeResolver.Resolved) -> String { "" }
    static func describe(scopeFilter: DashboardClientScopeFilter) -> String { "" }
    static func describe(output: TradingRulesComplianceSnapshotBuilder.Output) -> String { "" }
    static func describe(session: TradingRulesComplianceSessionStore) -> String { "" }
    static func dashboardSectionBranch(
        compliancePresentation: ProPremiumFeaturePresentation,
        session: TradingRulesComplianceSessionStore
    ) -> String { "" }
    static func detailViewBranch(session: TradingRulesComplianceSessionStore) -> String { "" }
    static func homeRouteBranch(
        embeddedInTraxsProPreview: Bool,
        showsEntitlementVerification: Bool,
        canShowDetail: Bool,
        isRefreshing: Bool,
        loadOutcome: TradingRulesComplianceLoadOutcome,
        store: TradingRulesComplianceSessionStore
    ) -> String { "" }
}
#endif