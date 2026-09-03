import Foundation
import Observation

/// Session-scoped today's daily check-in — one fetch, realtime refresh, no polling.
@Observable
@MainActor
final class TraderDailyCheckInStore {
    static let shared = TraderDailyCheckInStore()

    private(set) var todayCheckIn: TraderDailyCheckIn?
    private(set) var isReady = false
    private(set) var isRefreshing = false

    var isCompletedToday: Bool {
        todayCheckIn?.isComplete == true
    }

    var todayDateKey: String {
        TraderPsychologyAnalyticsFoundation.todayCheckInDateKey()
    }

    private var repository: (any TraderDailyCheckInRepository)?
    private var session: (any SessionProviding)?
    private var realtimeHub: RealtimeHub?
    private var viewerID: ProfileID?
    private var refreshTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    private init() {}

    func configure(
        repository: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        self.repository = repository
        self.session = session
        self.realtimeHub = realtimeHub
    }

    func loadIfNeeded() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.performRefresh(fromUserAction: false)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func refresh(fromUserAction: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(fromUserAction: fromUserAction)
            await MainActor.run { self?.refreshTask = nil }
        }
    }

    func applySaved(_ checkIn: TraderDailyCheckIn) {
        guard checkIn.checkInDate == todayDateKey else { return }
        todayCheckIn = checkIn
        isReady = true
    }

    func invalidate() {
        refreshTask?.cancel()
        realtimeTask?.cancel()
        refreshTask = nil
        realtimeTask = nil
        todayCheckIn = nil
        isReady = false
        isRefreshing = false
        viewerID = nil
        loadGeneration &+= 1
        stopRealtime()
    }

    private func performRefresh(fromUserAction: Bool) async {
        guard let repository, let session else { return }
        guard let userID = await session.currentUserID else { return }

        let profileID = ProfileID(userID.rawValue)
        if viewerID != profileID {
            viewerID = profileID
            startRealtimeIfNeeded(viewerID: userID.rawValue)
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        if !fromUserAction {
            isRefreshing = !isReady
        }

        do {
            await SessionNetworkGate.shared.awaitReady()
            let dateKey = todayDateKey
            let loaded = try await repository.checkIn(for: profileID, date: dateKey)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            todayCheckIn = loaded
            isReady = true
        } catch is CancellationError {
            // Preserve last known state.
        } catch {
            // Preserve last known state on transient failures.
            if !isReady {
                todayCheckIn = nil
                isReady = true
            }
        }

        isRefreshing = false
    }

    private func startRealtimeIfNeeded(viewerID: String) {
        guard let realtimeHub else { return }
        stopRealtime()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let token = await self.session?.accessToken
            for await _ in realtimeHub.watchTraderDailyCheckIns(userID: viewerID, accessToken: token) {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.refresh(fromUserAction: false)
                }
            }
        }
    }

    private func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let viewerID = viewerID?.rawValue {
            Task { await realtimeHub?.stopWatchingTraderDailyCheckIns(userID: viewerID) }
        }
    }
}
