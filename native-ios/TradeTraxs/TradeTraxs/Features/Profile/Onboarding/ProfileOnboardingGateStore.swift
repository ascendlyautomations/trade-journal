import Foundation
import Observation

/// Resolves session bootstrap onboarding state before the authenticated shell appears.
@Observable
@MainActor
final class ProfileOnboardingGateStore: SessionBootstrapRefreshObserving {
    enum Phase: Equatable, Sendable {
        case idle
        case resolving
        case required(ProfileOnboardingSnapshot)
        case brokerOnboarding
        case complete
        /// Transient connectivity while authoritative bootstrap is still pending (session preserved).
        case connectivityBlocked(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var snapshot: ProfileOnboardingSnapshot?

    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let rpc: (any RPCClient)?
    private let detailCache: DetailPresentationCache?
    private let realtimeHub: RealtimeHub?
    private let profileStore: CurrentUserProfileStore

    private var resolveTask: Task<Void, Never>?
    private var connectivityRetryTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var viewerProfileRealtimeConsumer: RealtimeRouteConsumerHandle?
    private var loadGeneration: UInt64 = 0
    /// True until the first successful gate resolve for this authenticated session.
    private var requiresAuthoritativeResolve = true

    init(
        profiles: any ProfileRepository,
        session: any SessionProviding,
        rpc: (any RPCClient)?,
        detailCache: DetailPresentationCache?,
        realtimeHub: RealtimeHub?,
        profileStore: CurrentUserProfileStore
    ) {
        self.profiles = profiles
        self.session = session
        self.rpc = rpc
        self.detailCache = detailCache
        self.realtimeHub = realtimeHub
        self.profileStore = profileStore
        SessionBootstrapLoader.refreshCommitObserver = self
    }

    var needsOnboarding: Bool {
        switch phase {
        case .required, .brokerOnboarding:
            return true
        default:
            return false
        }
    }

    func reset() {
        resolveTask?.cancel()
        connectivityRetryTask?.cancel()
        realtimeTask?.cancel()
        resolveTask = nil
        connectivityRetryTask = nil
        realtimeTask = nil
        phase = .idle
        snapshot = nil
        loadGeneration &+= 1
        requiresAuthoritativeResolve = true
        OAuthProfileOnboardingNameStore.resetAll()
    }

    /// Explore / Demo Mode — skip onboarding gates without touching Supabase auth.
    func markCompleteForDemoExperience() {
        resolveTask?.cancel()
        realtimeTask?.cancel()
        resolveTask = nil
        realtimeTask = nil
        phase = .complete
        snapshot = nil
        requiresAuthoritativeResolve = false
    }

    func resolveIfNeeded(forceNetwork: Bool = false) {
        if resolveTask != nil { return }
        if case .complete = phase, !forceNetwork { return }
        if case .connectivityBlocked = phase, !forceNetwork { return }

        let generation: UInt64
        loadGeneration += 1
        generation = loadGeneration
        resolveTask = Task { [weak self] in
            await self?.performResolve(forceNetwork: forceNetwork, generation: generation)
            await MainActor.run { self?.resolveTask = nil }
        }
    }

    func markCompleted(with profile: Profile, snapshot: ProfileOnboardingSnapshot) {
        self.snapshot = snapshot
        OAuthProfileOnboardingNameStore.discard(for: UserID(snapshot.profileID.rawValue))
        stopRealtime()
        profileStore.applyBootstrapResult(profile: profile, stats: profileStore.stats)
        SessionBootstrapStore.shared.applyOnboardingCompletion(
            profile: profile,
            snapshot: snapshot
        )
        GettingStartedRefreshCenter.noteEligibleUserAction()
        BrokerOnboardingPersistence.markPending(snapshot.profileID)
        phase = .brokerOnboarding
    }

    func markBrokerOnboardingFinished() {
        if let profileID = snapshot?.profileID {
            BrokerOnboardingPersistence.markFinished(profileID)
        }
        phase = .complete
    }

    /// Re-attempt authoritative bootstrap when connectivity returns (returning users only).
    func noteAppBecameActive() {
        guard case .connectivityBlocked = phase else { return }
        scheduleConnectivityRetry(after: 0.5)
    }

    private func scheduleConnectivityRetry(after delaySeconds: TimeInterval) {
        connectivityRetryTask?.cancel()
        connectivityRetryTask = Task { [weak self] in
            let nanos = UInt64(max(0, delaySeconds) * 1_000_000_000)
            if nanos > 0 {
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.resolveIfNeeded(forceNetwork: true)
            }
        }
    }

    private func performResolve(forceNetwork: Bool, generation: UInt64) async {
        #if DEBUG
        if requiresAuthoritativeResolve {
            ColdLaunchSummaryProbe.markLaunchStarted()
        }
        #endif
        guard let userID = await session.currentUserID else {
            phase = .failed("Sign in to continue.")
            return
        }

        if await isDevelopmentBypassSession() {
            phase = .complete
            requiresAuthoritativeResolve = false
            return
        }

        let profileID = ProfileID(userID.rawValue)
        let uid = userID.rawValue
        let cacheInspection = SessionWarmStartProbe.inspectSessionDiskCache(viewerID: uid)
        let sessionDiskUsable = BackendV2BootstrapDiskCache.hasRenderableSession(viewerID: uid)
        let cacheWarmPath = !forceNetwork && sessionDiskUsable
        SessionWarmStartProbe.log(cacheInspection, userID: uid, forceNetwork: forceNetwork)
        if cacheWarmPath {
            SessionWarmStartProbe.warmStartTrace("cacheValidated")
            _ = applyPhaseFromSessionDiskCache(profileID: profileID, uid: uid)
        }

        if forceNetwork, case .connectivityBlocked = phase {
            phase = .resolving
        }

        if !cacheWarmPath {
            await SessionNetworkGate.shared.awaitReady()
            phase = .resolving
        }

        do {
            let onboardingSnapshot: ProfileOnboardingSnapshot
            let profile: Profile
            var sessionBootstrapPath: BackendV2BootstrapPath?
            var sessionBootstrapRpcCount = 0

            if BackendV2FeatureFlags.isEnabled(.session), let rpc {
                if cacheWarmPath {
                    SessionWarmStartProbe.warmStartTrace("cacheApplyStarted")
                }
                let result = try await SessionBootstrapLoader.load(
                    viewerID: profileID,
                    rpc: rpc,
                    profiles: profiles,
                    detailCache: detailCache,
                    forceNetwork: forceNetwork,
                    loadGeneration: generation,
                    currentGeneration: { [weak self] in self?.loadGeneration ?? generation }
                )
                profile = result.profile
                onboardingSnapshot = result.onboardingSnapshot
                sessionBootstrapPath = result.path
                sessionBootstrapRpcCount = result.rpcRequestCount
                profileStore.applyBootstrapResult(profile: profile, stats: result.stats)

                if result.rpcRequestCount == 0 {
                    SessionWarmStartProbe.warmStartTrace("cacheApplyCompleted")
                    SessionWarmStartProbe.warmStartTrace("shellReleaseStarted")
                    SessionWarmStartProbe.logShellRenderedFromCache(true, userID: uid)
                    SessionWarmStartProbe.warmStartTrace("shellReleased")
                    #if DEBUG
                    ColdLaunchSummaryProbe.markLaunchSource("disk")
                    ColdLaunchSummaryProbe.markAuthenticatedShell()
                    #endif
                } else {
                    #if DEBUG
                    ColdLaunchSummaryProbe.markLaunchSource("network")
                    #endif
                }
            } else {
                onboardingSnapshot = try await profiles.onboardingSnapshot(
                    for: profileID,
                    authoritative: forceNetwork
                )
                profile = try await profiles.profile(id: profileID)
                let stats = try await profiles.stats(for: profileID)
                profileStore.applyBootstrapResult(profile: profile, stats: stats)
            }

            guard generation == loadGeneration, !Task.isCancelled else {
                if case .resolving = phase { phase = .idle }
                return
            }

            snapshot = onboardingSnapshot
            if sessionBootstrapPath == .cache_display_only {
                requiresAuthoritativeResolve = true
            } else if sessionBootstrapRpcCount > 0 || forceNetwork {
                requiresAuthoritativeResolve = false
            } else {
                requiresAuthoritativeResolve = false
            }
            if ProfileOnboardingPolicy.profileNeedsOnboarding(onboardingSnapshot) {
                phase = .required(onboardingSnapshot)
                startRealtime(viewerID: userID.rawValue)
            } else {
                phase = brokerOnboardingPhase(for: profileID)
                stopRealtime()
            }
            _ = profile
        } catch is CancellationError {
            if case .resolving = phase { phase = .idle }
        } catch {
            let message = UserFacingError.message(for: error)
            if requiresAuthoritativeResolve,
               ProfileOnboardingErrorMapping.isTransientConnectivityFailure(error)
            {
                switch phase {
                case .complete, .required, .brokerOnboarding:
                    scheduleConnectivityRetry(after: 8)
                default:
                    phase = .connectivityBlocked(message)
                    scheduleConnectivityRetry(after: 8)
                }
            } else if case .complete = phase, sessionDiskUsable {
                scheduleConnectivityRetry(after: 8)
            } else {
                phase = .failed(message)
            }
        }
    }

    @discardableResult
    private func applyPhaseFromSessionDiskCache(profileID: ProfileID, uid: String) -> Bool {
        guard let cached = BackendV2BootstrapDiskCache.loadSession(viewerID: uid) else { return false }
        do {
            let applied = try SessionBootstrapApplier.mapApplied(cached.bootstrap, expectedViewerID: uid)
            snapshot = applied.onboardingSnapshot
            let stats = profileStore.stats?.profileID == applied.profile.id
                ? (profileStore.stats ?? applied.stats)
                : applied.stats
            profileStore.applyBootstrapResult(profile: applied.profile, stats: stats)
            if ProfileOnboardingPolicy.profileNeedsOnboarding(applied.onboardingSnapshot) {
                phase = .required(applied.onboardingSnapshot)
            } else {
                phase = brokerOnboardingPhase(for: profileID)
                if cached.freshness == .displayOnly {
                    requiresAuthoritativeResolve = true
                }
            }
            return true
        } catch {
            return false
        }
    }

    func sessionBootstrapDidCommitNetworkRefresh(_ result: SessionBootstrapLoadResult) async {
        profileStore.applyBootstrapResult(profile: result.profile, stats: result.stats)
        snapshot = result.onboardingSnapshot
        if ProfileOnboardingPolicy.profileNeedsOnboarding(result.onboardingSnapshot) {
            if case .complete = phase {
                phase = .required(result.onboardingSnapshot)
                if let userID = await session.currentUserID {
                    startRealtime(viewerID: userID.rawValue)
                }
            }
        } else if case .required = phase {
            if let profileID = snapshot?.profileID {
                phase = brokerOnboardingPhase(for: profileID)
            } else {
                phase = .complete
            }
            stopRealtime()
        }
    }

    private func brokerOnboardingPhase(for profileID: ProfileID) -> Phase {
        switch BrokerOnboardingPersistence.status(for: profileID) {
        case .pending:
            return .brokerOnboarding
        case .finished:
            return .complete
        case .unknown:
            BrokerOnboardingPersistence.grandfatherExistingProfileIfNeeded(profileID)
            return .complete
        }
    }

    private func isDevelopmentBypassSession() async -> Bool {
        guard let userID = await session.currentUserID else { return false }
        return userID.rawValue.hasPrefix("dev.")
    }

    private func startRealtime(viewerID: String) {
        guard let realtimeHub else { return }
        stopRealtime()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let token = await self.session.accessToken
            let watch = realtimeHub.watchViewerProfile(
                userID: viewerID,
                accessToken: token,
                debugOwner: "ProfileOnboarding"
            )
            viewerProfileRealtimeConsumer = watch.consumer
            for await _ in watch.events {
                guard !Task.isCancelled else { break }
                await self.handleExternalProfileUpdate()
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        let consumer = viewerProfileRealtimeConsumer
        viewerProfileRealtimeConsumer = nil
        Task {
            await realtimeHub?.releaseWatch(consumer)
        }
    }

    private func handleExternalProfileUpdate() async {
        guard let userID = await session.currentUserID else { return }
        do {
            let fresh = try await profiles.onboardingSnapshot(
                for: ProfileID(userID.rawValue),
                authoritative: true
            )
            snapshot = fresh
            if !ProfileOnboardingPolicy.profileNeedsOnboarding(fresh) {
                let profile = try await profiles.profile(id: ProfileID(userID.rawValue))
                markCompleted(with: profile, snapshot: fresh)
            }
        } catch {
            // Preserve current onboarding UI on transient failures.
        }
    }
}
