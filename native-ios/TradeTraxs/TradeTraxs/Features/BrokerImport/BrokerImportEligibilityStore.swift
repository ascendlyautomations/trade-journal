import Foundation
import Observation
import os

/// Session-scoped broker import eligibility — one fetch, cached for Dashboard visibility (no polling).
@Observable
@MainActor
final class BrokerImportEligibilityStore {
    static let shared = BrokerImportEligibilityStore()

    private(set) var linkedAccounts: [BrokerImportEligibilityTarget] = []
    private(set) var connectionCount = 0
    private(set) var linkedAccountCount = 0
    private(set) var hasSupportedConnection = false
    private(set) var needsAccountLinking = false
    private(set) var canImportImmediately = false
    private(set) var optOut = false
    /// True after a successful eligibility response (including legitimately empty).
    private(set) var isReady = false
    private(set) var isRefreshing = false

    var hasLinkedBrokerAccount: Bool {
        linkedAccountCount > 0 || !linkedAccounts.isEmpty
    }

    var showsDashboardImportAction: Bool {
        !optOut && hasSupportedConnection
    }

    private var broker: (any BrokerIntegrationRepository)?
    private var session: (any SessionProviding)?
    private var refreshTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var lastSuccessfulFetchAt: Date?
    private var persistedViewerID: String?

    private init() {}

    func configure(
        broker: any BrokerIntegrationRepository,
        session: any SessionProviding
    ) {
        self.broker = broker
        self.session = session
    }

    /// Presentation-only hydrate — does not hit the network.
    func hydrateFromDiskIfNeeded(viewerID: String) {
        guard !isReady else { return }
        guard let blob = BrokerImportEligibilityDiskCache.load(viewerID: viewerID) else { return }
        persistedViewerID = viewerID
        apply(blob.response)
        lastSuccessfulFetchAt = blob.savedAt
        #if DEBUG
        AppLog.application.debug(
            "dashboard.brokerImportEligibility.hydratedFromDisk ageSec=\(Int(Date().timeIntervalSince(blob.savedAt)), privacy: .public)"
        )
        #endif
    }

    /// Deferred startup — refresh only when disk cache is missing or stale.
    func loadIfNeeded() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if let userID = await session?.currentUserID?.rawValue {
                hydrateFromDiskIfNeeded(viewerID: userID)
            }
            await AuthenticatedLaunchPhasing.waitUntilDeferredStartupNetworkingAllowed()
            await performStaleAwareRefresh(fromUserAction: false)
            refreshTask = nil
        }
    }

    func refresh(fromUserAction: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(fromUserAction: fromUserAction)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    /// Background refresh — skips network when last-known state is still fresh.
    func refreshIfStale(fromUserAction: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performStaleAwareRefresh(fromUserAction: fromUserAction)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func refreshAndWait(fromUserAction: Bool = false) async {
        refreshTask?.cancel()
        refreshTask = nil
        await performRefresh(fromUserAction: fromUserAction)
    }

    func apply(_ response: BrokerImportEligibilityResponse) {
        linkedAccounts = response.linkedAccounts
        connectionCount = response.connectionCount
        linkedAccountCount = max(response.linkedAccountCount, response.linkedAccounts.count)
        optOut = response.optOut
        hasSupportedConnection = response.resolvedHasSupportedConnection
        needsAccountLinking = response.resolvedNeedsAccountLinking
        canImportImmediately = response.resolvedCanImportImmediately
        isReady = true
        logLoaded(response)
    }

    func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
        linkedAccounts = []
        connectionCount = 0
        linkedAccountCount = 0
        hasSupportedConnection = false
        needsAccountLinking = false
        canImportImmediately = false
        optOut = false
        isReady = false
        isRefreshing = false
        lastSuccessfulFetchAt = nil
        loadGeneration &+= 1
        if let persistedViewerID {
            BrokerImportEligibilityDiskCache.clear(viewerID: persistedViewerID)
        }
        persistedViewerID = nil
    }

    func fetchEligibility() async throws -> BrokerImportEligibilityResponse {
        guard let broker else {
            throw NetworkError.unknown(message: "Broker integrations unavailable.")
        }
        guard let userID = await session?.currentUserID?.rawValue else {
            throw NetworkError.unauthorized
        }
        await SessionNetworkGate.shared.awaitReady()
        let response = try await broker.importEligibility()
        persistedViewerID = userID
        apply(response)
        lastSuccessfulFetchAt = Date()
        BrokerImportEligibilityDiskCache.save(response, viewerID: userID)
        return response
    }

    private func performStaleAwareRefresh(fromUserAction: Bool) async {
        if fromUserAction {
            await performRefresh(fromUserAction: true)
            return
        }
        if let lastSuccessfulFetchAt,
           Date().timeIntervalSince(lastSuccessfulFetchAt)
            < BrokerImportEligibilityDiskCache.presentationSoftStaleSeconds
        {
            #if DEBUG
            AppLog.application.debug("dashboard.brokerImportEligibility.skipNetwork reason=freshCache")
            #endif
            return
        }
        await performRefresh(fromUserAction: false)
    }

    private func performRefresh(fromUserAction: Bool) async {
        guard let session, broker != nil else { return }
        guard AuthBootstrapReadiness.allowsAuthenticatedBackgroundWork() else { return }
        if !fromUserAction {
            guard AuthenticatedLaunchPhasing.allowsDeferredStartupNetworking else { return }
        }
        let generation = loadGeneration
        if fromUserAction || !isReady {
            isRefreshing = true
        }
        defer { isRefreshing = false }

        guard await session.currentUserID != nil else {
            if generation == loadGeneration {
                linkedAccounts = []
                connectionCount = 0
                linkedAccountCount = 0
                hasSupportedConnection = false
                needsAccountLinking = false
                canImportImmediately = false
                isReady = false
            }
            return
        }

        do {
            _ = try await fetchEligibility()
        } catch {
            guard generation == loadGeneration else { return }
            if Self.isBenignCancellation(error) || Task.isCancelled {
                return
            }
            #if DEBUG
            AppLog.application.debug(
                "dashboard.brokerImportEligibility.loadFailed error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    private static func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case NetworkError.cancelled = error { return true }
        if case AppError.cancelled = error { return true }
        return false
    }

    #if DEBUG
    private func logLoaded(_ response: BrokerImportEligibilityResponse) {
        let providers = response.linkedAccounts.map(\.provider.rawValue).joined(separator: ",")
        let cardVisible = showsDashboardImportAction
        AppLog.application.debug(
            """
            dashboard.brokerImport.connectionCount=\(response.connectionCount, privacy: .public) \
            dashboard.brokerImport.linkedAccountCount=\(response.linkedAccountCount, privacy: .public) \
            dashboard.brokerImport.provider=\(providers.isEmpty ? "none" : providers, privacy: .public) \
            dashboard.brokerImport.mappingLinked=\(response.resolvedHasLinkedAccount, privacy: .public) \
            dashboard.brokerImport.cardVisible=\(cardVisible, privacy: .public) \
            dashboard.brokerImportEligibility.loaded importEligible=\(response.eligible, privacy: .public) \
            dashboard.brokerImport.hasSupportedConnection=\(self.hasSupportedConnection, privacy: .public) \
            dashboard.brokerImport.needsAccountLinking=\(self.needsAccountLinking, privacy: .public)
            """
        )
    }
    #else
    private func logLoaded(_: BrokerImportEligibilityResponse) {}
    #endif
}
