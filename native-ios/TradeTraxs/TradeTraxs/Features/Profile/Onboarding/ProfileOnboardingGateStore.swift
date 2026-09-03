import Foundation
import Observation

/// Resolves session bootstrap onboarding state before the authenticated shell appears.
@Observable
@MainActor
final class ProfileOnboardingGateStore {
    enum Phase: Equatable, Sendable {
        case idle
        case resolving
        case required(ProfileOnboardingSnapshot)
        case complete
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
    private var realtimeTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

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
    }

    var needsOnboarding: Bool {
        if case .required = phase { return true }
        return false
    }

    func reset() {
        resolveTask?.cancel()
        realtimeTask?.cancel()
        resolveTask = nil
        realtimeTask = nil
        phase = .idle
        snapshot = nil
        loadGeneration &+= 1
    }

    func resolveIfNeeded(forceNetwork: Bool = false) {
        if resolveTask != nil { return }
        if case .complete = phase, !forceNetwork { return }

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
        phase = .complete
        stopRealtime()
        profileStore.applyBootstrapResult(profile: profile, stats: profileStore.stats)
        SessionBootstrapStore.shared.applyOnboardingCompletion(
            profile: profile,
            snapshot: snapshot
        )
        GettingStartedRefreshCenter.noteEligibleUserAction()
    }

    private func performResolve(forceNetwork: Bool, generation: UInt64) async {
        phase = .resolving
        await SessionNetworkGate.shared.awaitReady()

        guard let userID = await session.currentUserID else {
            phase = .failed("Sign in to continue.")
            return
        }

        if await isDevelopmentBypassSession() {
            phase = .complete
            return
        }

        let profileID = ProfileID(userID.rawValue)

        do {
            let onboardingSnapshot: ProfileOnboardingSnapshot
            let profile: Profile

            if BackendV2FeatureFlags.isEnabled(.session), let rpc {
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
                profileStore.applyBootstrapResult(profile: profile, stats: result.stats)
            } else {
                onboardingSnapshot = try await profiles.onboardingSnapshot(for: profileID)
                profile = try await profiles.profile(id: profileID)
                let stats = try await profiles.stats(for: profileID)
                profileStore.applyBootstrapResult(profile: profile, stats: stats)
            }

            guard generation == loadGeneration, !Task.isCancelled else { return }

            snapshot = onboardingSnapshot
            if ProfileOnboardingPolicy.profileNeedsOnboarding(onboardingSnapshot) {
                phase = .required(onboardingSnapshot)
                startRealtime(viewerID: userID.rawValue)
            } else {
                phase = .complete
                stopRealtime()
            }
            _ = profile
        } catch is CancellationError {
            if case .resolving = phase { phase = .idle }
        } catch {
            phase = .failed(UserFacingError.message(for: error))
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
            for await _ in realtimeHub.watchViewerProfile(userID: viewerID, accessToken: token) {
                guard !Task.isCancelled else { break }
                await self.handleExternalProfileUpdate()
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let userID = snapshot?.profileID.rawValue {
            Task {
                await realtimeHub?.stopWatchingViewerProfile(userID: userID)
            }
        }
    }

    private func handleExternalProfileUpdate() async {
        guard let userID = await session.currentUserID else { return }
        do {
            let fresh = try await profiles.onboardingSnapshot(for: ProfileID(userID.rawValue))
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
