import Foundation
import os

/// REST session bootstrap — legacy fallback when V2 RPC is unavailable.
nonisolated struct SessionRestBootstrapRepository: SessionBootstrapProviding {
    private let profiles: any ProfileRepository
    private let session: any SessionProviding

    init(profiles: any ProfileRepository, session: any SessionProviding) {
        self.profiles = profiles
        self.session = session
    }

    func loadSessionBootstrap() async throws -> SessionBootstrapV1 {
        throw BackendV2RPCError.notImplemented("Use SessionBootstrapLoader legacyProfileStats")
    }
}

/// RPC session bootstrap — calls `rpc_v1_session_bootstrap`.
nonisolated struct SessionRpcBootstrapRepository: SessionBootstrapProviding {
    private let client: BackendV2RPCClient

    init(rpc: any RPCClient) {
        self.client = BackendV2RPCClient(transport: rpc)
    }

    func loadSessionBootstrap() async throws -> SessionBootstrapV1 {
        await MainActor.run {
            SessionBootstrapAuthDebug.requestStarted(authRequired: true)
        }
        do {
            let value = try await client.call(
                .session,
                as: SessionBootstrapV1.self,
                options: BackendV2RPCCallOptions(
                    cacheMiss: true,
                    flagName: BackendV2FeatureFlag.session.dottedName
                )
            )
            try value.validateContractVersion()
            await MainActor.run {
                SessionBootstrapAuthDebug.requestCompleted(
                    responseStatus: 200,
                    classification: "success"
                )
            }
            return value
        } catch {
            let diagnostic = MessagesBootstrapFailureDiagnostic.make(error: error)
            await MainActor.run {
                SessionBootstrapAuthDebug.requestCompleted(
                    responseStatus: diagnostic.httpStatus,
                    classification: diagnostic.summary
                )
            }
            throw error
        }
    }
}

/// Holds last Session Bootstrap for badge/following seeds (flag-ON path).
@MainActor
final class SessionBootstrapStore {
    static let shared = SessionBootstrapStore()

    private(set) var last: SessionBootstrapV1?
    private(set) var source: String?

    /// Local avatar that must win over a session payload still carrying the previous URL.
    private var adoptedAvatar: AdoptedAvatar?

    func seed(_ bootstrap: SessionBootstrapV1, source: String) {
        last = bootstrap
        self.source = source
        if let viewerID = bootstrap.meta.viewer_id ?? Optional(bootstrap.data.viewer.id) {
            BackendV2BootstrapDiskCache.saveSession(bootstrap, viewerID: viewerID)
        }
    }

    func applyUsernameChange(profileID: ProfileID, username: String) {
        guard var bootstrap = last else { return }
        guard bootstrap.data.session_profile.id == profileID.rawValue
            || bootstrap.data.viewer.id == profileID.rawValue
        else { return }
        bootstrap.data.session_profile.username = username
        bootstrap.data.viewer.username = username
        last = bootstrap
        if let viewerID = bootstrap.meta.viewer_id ?? Optional(bootstrap.data.viewer.id) {
            BackendV2BootstrapDiskCache.saveSession(bootstrap, viewerID: viewerID)
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: profileID)
        }
    }

    func applyOnboardingCompletion(profile: Profile, snapshot: ProfileOnboardingSnapshot) {
        let avatarURL = Self.normalizedAvatarURL(
            session: snapshot.avatarURL ?? profile.avatar?.id,
            viewer: nil
        )
        recordAdoptedAvatar(profileID: profile.id, avatarURL: avatarURL)
        guard var bootstrap = last else { return }
        bootstrap.data.session_profile.username = profile.username
        bootstrap.data.session_profile.bio = profile.bio
        bootstrap.data.session_profile.trading_style = profile.tradingStyle
        bootstrap.data.session_profile.trader_type = profile.traderType?.rawValue
        bootstrap.data.session_profile.primary_market = profile.primaryMarket
        bootstrap.data.session_profile.started_trading = snapshot.startedTrading
        bootstrap.data.session_profile.onboarding_completed = true
        bootstrap.data.session_profile.avatar_url = avatarURL
        bootstrap.data.viewer.username = profile.username
        bootstrap.data.viewer.display_name = profile.displayName
        bootstrap.data.viewer.avatar_url = avatarURL
        bootstrap.data.viewer.onboarding_flags["onboarding_completed"] = true
        last = bootstrap
        if let viewerID = bootstrap.meta.viewer_id ?? Optional(bootstrap.data.viewer.id) {
            BackendV2BootstrapDiskCache.saveSession(bootstrap, viewerID: viewerID)
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: ProfileID(viewerID))
        }
    }

    /// Patches the cached session card when the owner avatar changes after onboarding.
    func applyAvatarChange(profileID: ProfileID, avatarURL: String?) {
        let normalized = Self.normalizedAvatarURL(session: avatarURL, viewer: nil)
        recordAdoptedAvatar(profileID: profileID, avatarURL: normalized)
        guard var bootstrap = last else { return }
        guard bootstrap.data.session_profile.id == profileID.rawValue
            || bootstrap.data.viewer.id == profileID.rawValue
        else { return }
        bootstrap.data.session_profile.avatar_url = normalized
        bootstrap.data.viewer.avatar_url = normalized
        last = bootstrap
        if let viewerID = bootstrap.meta.viewer_id ?? Optional(bootstrap.data.viewer.id) {
            BackendV2BootstrapDiskCache.saveSession(bootstrap, viewerID: viewerID)
            ViewerSyncStateRuntime.noteLocalMutation(viewerID: profileID)
        }
    }

    /// Keeps a locally chosen avatar when `bootstrap` still has a URL that choice replaced.
    ///
    /// A server payload that already contains the adopted URL clears the lock. Replaying
    /// our own disk write must not — an in-flight session RPC can still carry the old URL.
    @discardableResult
    func reconcileAdoptedAvatar(
        _ bootstrap: inout SessionBootstrapV1,
        serverAuthoritative: Bool
    ) -> Bool {
        guard let adopted = adoptedAvatar else { return false }
        guard adopted.profileID == bootstrap.data.session_profile.id
            || adopted.profileID == bootstrap.data.viewer.id
        else { return false }

        let incoming = Self.normalizedAvatarURL(
            session: bootstrap.data.session_profile.avatar_url,
            viewer: bootstrap.data.viewer.avatar_url
        )
        if incoming == adopted.avatarURL {
            if serverAuthoritative {
                adoptedAvatar = nil
            }
            return false
        }
        if adopted.replacedURLs.contains(incoming) {
            bootstrap.data.session_profile.avatar_url = adopted.avatarURL
            bootstrap.data.viewer.avatar_url = adopted.avatarURL
            return true
        }
        adoptedAvatar = nil
        return false
    }

    /// Avatar URL to keep on the current-user profile when a bootstrap result arrives.
    func preferredAvatarURL(profileID: ProfileID, incoming: String?) -> String? {
        let incomingNorm = Self.normalizedAvatarURL(session: incoming, viewer: nil)
        guard let adopted = adoptedAvatar, adopted.profileID == profileID.rawValue else {
            return incomingNorm
        }
        if incomingNorm == adopted.avatarURL || adopted.replacedURLs.contains(incomingNorm) {
            return adopted.avatarURL
        }
        adoptedAvatar = nil
        return incomingNorm
    }

    nonisolated static func normalizedAvatarURL(session: String?, viewer: String?) -> String? {
        for raw in [session, viewer] {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    func clear() {
        last = nil
        source = nil
        adoptedAvatar = nil
    }

    private struct AdoptedAvatar {
        var profileID: String
        var avatarURL: String?
        var replacedURLs: Set<String?>
    }

    private func recordAdoptedAvatar(profileID: ProfileID, avatarURL: String?) {
        let previous: String? = last.flatMap {
            Self.normalizedAvatarURL(
                session: $0.data.session_profile.avatar_url,
                viewer: $0.data.viewer.avatar_url
            )
        }
        if adoptedAvatar == nil, previous == avatarURL {
            return
        }
        if adoptedAvatar?.profileID == profileID.rawValue, adoptedAvatar?.avatarURL == avatarURL {
            return
        }
        var replaced = adoptedAvatar?.profileID == profileID.rawValue
            ? (adoptedAvatar?.replacedURLs ?? [])
            : []
        if let adoptedAvatar, adoptedAvatar.profileID == profileID.rawValue {
            replaced.insert(adoptedAvatar.avatarURL)
        }
        replaced.insert(previous)
        replaced.remove(avatarURL)
        adoptedAvatar = AdoptedAvatar(
            profileID: profileID.rawValue,
            avatarURL: avatarURL,
            replacedURLs: replaced
        )
    }

    /// Authoritative platform admin flag from session bootstrap (`admin_users` → `entitlement.flags.is_admin`).
    var isPlatformAdmin: Bool {
        last?.data.viewer.entitlement.flags["is_admin"] == true
    }
}

struct SessionBootstrapLoadResult: Sendable {
    var profile: Profile
    var stats: ProfileStats
    var onboardingSnapshot: ProfileOnboardingSnapshot
    var path: BackendV2BootstrapPath
    var rpcRequestCount: Int
    var usedLegacyREST: Bool
}

enum SessionBootstrapLoader {
    private static let rpcName = BackendV2Versioning.RPCName.session.rawValue
    private static let logger = Logger(
        subsystem: "com.tradetraxs.TradeTraxs",
        category: "BackendV2.Session"
    )

    /// Receives the single authoritative network refresh commit (not cache-only loads).
    @MainActor
    weak static var refreshCommitObserver: (any SessionBootstrapRefreshObserving)?

    /// Flag ON — cache → single RPC → controlled legacy fallback.
    @MainActor
    static func load(
        viewerID: ProfileID,
        rpc: any RPCClient,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?,
        forceNetwork: Bool,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64,
        skipSoftStaleReconcile: Bool = false
    ) async throws -> SessionBootstrapLoadResult {
        guard BackendV2FeatureFlags.isEnabled(.session) else {
            return try await loadLegacyREST(
                profileID: viewerID,
                profiles: profiles,
                detailCache: detailCache,
                forceNetwork: forceNetwork,
                path: .legacy_flag_off
            )
        }

        let uid = viewerID.rawValue
        let cacheInspection = SessionWarmStartProbe.inspectSessionDiskCache(viewerID: uid)
        SessionWarmStartProbe.log(cacheInspection, userID: uid, forceNetwork: forceNetwork)

        if !forceNetwork, let cached = BackendV2BootstrapDiskCache.loadSession(viewerID: uid) {
            #if DEBUG
            SessionWarmStartProbe.warmStartTrace("cacheValidated")
            SessionWarmStartProbe.warmStartTrace("cacheApplyStarted")
            #endif
            let applied = try await SessionBootstrapApplier.apply(
                cached.bootstrap,
                expectedViewerID: uid,
                detailCache: detailCache
            )
            #if DEBUG
            SessionWarmStartProbe.warmStartTrace("cacheApplyCompleted")
            #endif
            let stats = resolveHeaderStatsFromCacheOnly(
                profileID: viewerID,
                partial: applied.stats,
                detailCache: detailCache
            )
            #if DEBUG
            SessionWarmStartProbe.warmStartTrace("shellReleaseStarted")
            #endif
            let path = bootstrapPath(for: cached.freshness)
            logPath(path)
            scheduleBackgroundHeaderStatsHydration(
                profileID: viewerID,
                profiles: profiles,
                detailCache: detailCache
            )
            if shouldScheduleAuthoritativeSessionRefresh(cached.freshness), !skipSoftStaleReconcile {
                #if DEBUG
                SessionWarmStartProbe.warmStartTrace("revalidateScheduled")
                #endif
                scheduleSoftStaleReconcile(
                    viewerID: viewerID,
                    rpc: rpc,
                    profiles: profiles,
                    detailCache: detailCache,
                    loadGeneration: loadGeneration,
                    currentGeneration: currentGeneration
                )
            }
            if cached.freshness == .displayOnly {
                scheduleDisplayOnlyAuthoritativeSessionRefresh(
                    viewerID: viewerID,
                    rpc: rpc,
                    profiles: profiles,
                    detailCache: detailCache,
                    loadGeneration: loadGeneration,
                    currentGeneration: currentGeneration
                )
            }
            #if DEBUG
            SessionWarmStartProbe.warmStartTrace("shellReleased")
            #endif
            return SessionBootstrapLoadResult(
                profile: applied.profile,
                stats: stats,
                onboardingSnapshot: applied.onboardingSnapshot,
                path: path,
                rpcRequestCount: 0,
                usedLegacyREST: false
            )
        }

        if await BackendV2RpcAvailability.shared.isUnavailable(rpcName: rpcName, viewerID: uid) {
            return try await loadLegacyREST(
                profileID: viewerID,
                profiles: profiles,
                detailCache: detailCache,
                forceNetwork: forceNetwork,
                path: .legacy_missing_rpc
            )
        }

        do {
            let fetched = try await fetchRPC(viewerID: uid, rpc: rpc)
            guard currentGeneration() == loadGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            guard await SessionBootstrapRefreshCommit.shared.shouldCommit(
                slotID: fetched.slotID,
                viewerID: uid
            ) else {
                #if DEBUG
                logger.debug(
                    "session bootstrap commit skipped slot=\(fetched.slotID.uuidString.prefix(8), privacy: .public)"
                )
                #endif
                let applied = try SessionBootstrapApplier.mapApplied(
                    fetched.bootstrap,
                    expectedViewerID: uid
                )
                let stats = resolveHeaderStatsFromCacheOnly(
                    profileID: viewerID,
                    partial: applied.stats,
                    detailCache: detailCache
                )
                scheduleBackgroundHeaderStatsHydration(
                    profileID: viewerID,
                    profiles: profiles,
                    detailCache: detailCache
                )
                return SessionBootstrapLoadResult(
                    profile: applied.profile,
                    stats: stats,
                    onboardingSnapshot: applied.onboardingSnapshot,
                    path: .v2_rpc,
                    rpcRequestCount: 0,
                    usedLegacyREST: false
                )
            }
            return try await commitNetworkBootstrap(
                bootstrap: fetched.bootstrap,
                viewerID: viewerID,
                uid: uid,
                rpc: rpc,
                profiles: profiles,
                detailCache: detailCache,
                notifyObserver: true
            )
        } catch {
            if BackendV2RpcCompat.isRpcUnavailable(error, rpcName: rpcName) {
                await BackendV2RpcAvailability.shared.markUnavailable(rpcName: rpcName, viewerID: uid)
                return try await loadLegacyREST(
                    profileID: viewerID,
                    profiles: profiles,
                    detailCache: detailCache,
                    forceNetwork: forceNetwork,
                    path: .legacy_missing_rpc
                )
            }
            if let cached = BackendV2BootstrapDiskCache.loadSession(viewerID: uid) {
                let applied = try await SessionBootstrapApplier.apply(
                    cached.bootstrap,
                    expectedViewerID: uid,
                    detailCache: detailCache
                )
                let stats = resolveHeaderStatsFromCacheOnly(
                    profileID: viewerID,
                    partial: applied.stats,
                    detailCache: detailCache
                )
                scheduleBackgroundHeaderStatsHydration(
                    profileID: viewerID,
                    profiles: profiles,
                    detailCache: detailCache
                )
                logPath(.error_preserved_cache)
                return SessionBootstrapLoadResult(
                    profile: applied.profile,
                    stats: stats,
                    onboardingSnapshot: applied.onboardingSnapshot,
                    path: .error_preserved_cache,
                    rpcRequestCount: 0,
                    usedLegacyREST: !stats.hasLoadedHeaderMetrics
                )
            }
            throw error
        }
    }

    @MainActor
    private static func scheduleSoftStaleReconcile(
        viewerID: ProfileID,
        rpc: any RPCClient,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) {
        guard BackendV2FeatureFlags.isEnabled(.viewerSyncState) else {
            BackendV2BootstrapDiskCache.touchSession(viewerID: viewerID.rawValue)
            SyncStateProbe.logFallback("sync_flag_off_touch_session")
            return
        }
        ViewerSyncReconciliationCoordinator.shared.schedule(
            ViewerSyncReconcileContext(
                viewerID: viewerID,
                rpc: rpc,
                profiles: profiles,
                detailCache: detailCache,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration,
                needsSessionRefresh: true,
                needsDashboardRefresh: false
            )
        )
    }

    private struct FetchedRPC: Sendable {
        var bootstrap: SessionBootstrapV1
        var slotID: UUID
    }

    private static func fetchRPC(viewerID: String, rpc: any RPCClient) async throws -> FetchedRPC {
        let flightKey = BackendV2FlightKeys.session(viewerID: viewerID)
        let repo = SessionRpcBootstrapRepository(rpc: rpc)
        let flight = try await BootstrapTransportTimeout.run {
            try await BackendV2SingleFlight.shared.coalesceWithSlot(key: flightKey) {
                let bootstrap = try await repo.loadSessionBootstrap()
                return try JSONEncoder().encode(bootstrap)
            }
        }
        do {
            let bootstrap = try JSONDecoder().decode(SessionBootstrapV1.self, from: flight.data)
            return FetchedRPC(bootstrap: bootstrap, slotID: flight.slotID)
        } catch {
            throw BackendV2RPCError.decode("session bootstrap decode failed")
        }
    }

    @MainActor
    private static func commitNetworkBootstrap(
        bootstrap: SessionBootstrapV1,
        viewerID: ProfileID,
        uid: String,
        rpc: any RPCClient,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?,
        notifyObserver: Bool
    ) async throws -> SessionBootstrapLoadResult {
        BackendV2RpcStageTracer.trace(rpcName, stage: "state.apply.started", correlation: uid.prefix(8).description)
        let applied = try await SessionBootstrapApplier.apply(
            bootstrap,
            expectedViewerID: uid,
            detailCache: detailCache,
            serverAuthoritative: true
        )
        BackendV2RpcStageTracer.trace(rpcName, stage: "state.apply.completed", correlation: uid.prefix(8).description)
        let stats = try await resolveHeaderStats(
            profileID: viewerID,
            partial: applied.stats,
            profiles: profiles,
            detailCache: detailCache
        )
        BackendV2RpcStageTracer.trace(rpcName, stage: "cache.write.started", correlation: uid.prefix(8).description)
        if let reconciled = SessionBootstrapStore.shared.last {
            BackendV2BootstrapDiskCache.saveSession(reconciled, viewerID: uid)
        } else {
            BackendV2BootstrapDiskCache.saveSession(bootstrap, viewerID: uid)
        }
        BackendV2RpcStageTracer.trace(rpcName, stage: "cache.write.completed", correlation: uid.prefix(8).description)
        ViewerSyncStateCapturer.captureAfterBootstrap(viewerID: uid, rpc: rpc)
        logPath(.v2_rpc)
        let result = SessionBootstrapLoadResult(
            profile: applied.profile,
            stats: stats,
            onboardingSnapshot: applied.onboardingSnapshot,
            path: .v2_rpc,
            rpcRequestCount: 1,
            usedLegacyREST: false
        )
        if notifyObserver, let refreshCommitObserver {
            await refreshCommitObserver.sessionBootstrapDidCommitNetworkRefresh(result)
        }
        return result
    }

    /// Cache / in-memory only — never blocks warm-start on REST header aggregation.
    @MainActor
    private static func resolveHeaderStatsFromCacheOnly(
        profileID: ProfileID,
        partial: ProfileStats,
        detailCache: DetailPresentationCache?
    ) -> ProfileStats {
        if partial.hasLoadedHeaderMetrics {
            detailCache?.seed(stats: partial)
            return partial
        }
        if let cached = detailCache?.stats(for: profileID), cached.hasLoadedHeaderMetrics {
            return cached
        }
        detailCache?.seed(stats: partial)
        return partial
    }

    @MainActor
    private static func scheduleBackgroundHeaderStatsHydration(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?
    ) {
        guard !BackendV2FeatureFlags.isEnabled(.profile) else { return }
        Task { @MainActor in
            guard let loaded = try? await profiles.stats(for: profileID) else { return }
            detailCache?.seed(stats: loaded)
        }
    }

    @MainActor
    private static func resolveHeaderStats(
        profileID: ProfileID,
        partial: ProfileStats,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?
    ) async throws -> ProfileStats {
        if partial.hasLoadedHeaderMetrics {
            detailCache?.seed(stats: partial)
            return partial
        }
        if let cached = detailCache?.stats(for: profileID), cached.hasLoadedHeaderMetrics {
            return cached
        }
        if BackendV2FeatureFlags.isEnabled(.profile) {
            detailCache?.seed(stats: partial)
            return partial
        }
        let loaded = try await profiles.stats(for: profileID)
        detailCache?.seed(stats: loaded)
        return loaded
    }

    @MainActor
    private static func loadLegacyREST(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?,
        forceNetwork: Bool,
        path: BackendV2BootstrapPath
    ) async throws -> SessionBootstrapLoadResult {
        async let profileTask = profiles.profile(id: profileID)
        async let statsTask = profiles.stats(for: profileID)
        async let onboardingTask = profiles.onboardingSnapshot(
            for: profileID,
            authoritative: forceNetwork
        )
        let (profile, stats, onboardingSnapshot) = try await (profileTask, statsTask, onboardingTask)
        detailCache?.seed(profile)
        detailCache?.seed(stats: stats)
        logPath(path)
        return SessionBootstrapLoadResult(
            profile: profile,
            stats: stats,
            onboardingSnapshot: onboardingSnapshot,
            path: path,
            rpcRequestCount: 0,
            usedLegacyREST: true
        )
    }

    private static func bootstrapPath(for freshness: BackendV2BootstrapDiskCache.Freshness) -> BackendV2BootstrapPath {
        switch freshness {
        case .fresh:
            return .cache_fresh
        case .softStale:
            return .cache_stale_revalidate
        case .displayOnly:
            return .cache_display_only
        case .expired:
            return .error_preserved_cache
        }
    }

    private static func shouldScheduleAuthoritativeSessionRefresh(_ freshness: BackendV2BootstrapDiskCache.Freshness) -> Bool {
        freshness == .softStale
    }

    @MainActor
    private static func scheduleDisplayOnlyAuthoritativeSessionRefresh(
        viewerID: ProfileID,
        rpc: any RPCClient,
        profiles: any ProfileRepository,
        detailCache: DetailPresentationCache?,
        loadGeneration: UInt64,
        currentGeneration: @escaping () -> UInt64
    ) {
        Task(priority: .userInitiated) { @MainActor in
            _ = try? await load(
                viewerID: viewerID,
                rpc: rpc,
                profiles: profiles,
                detailCache: detailCache,
                forceNetwork: true,
                loadGeneration: loadGeneration,
                currentGeneration: currentGeneration,
                skipSoftStaleReconcile: true
            )
        }
    }

    private static func logPath(_ path: BackendV2BootstrapPath) {
        #if DEBUG
        logger.debug("session bootstrap path=\(path.rawValue, privacy: .public)")
        #endif
    }
}
