import Foundation
import Observation

/// Session-scoped today's daily check-in — one fetch, no Realtime; own saves via ``applySaved``.
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
    private var viewerID: ProfileID?
    private var refreshTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0

    private init() {}

    func configure(
        repository: any TraderDailyCheckInRepository,
        session: any SessionProviding,
        realtimeHub: RealtimeHub?
    ) {
        self.repository = repository
        self.session = session
        _ = realtimeHub
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
        DailyCheckInReminderCoordinator.shared.syncIfNeeded()
    }

    func invalidate() {
        refreshTask?.cancel()
        refreshTask = nil
        todayCheckIn = nil
        isReady = false
        isRefreshing = false
        viewerID = nil
        loadGeneration &+= 1
    }

    private func performRefresh(fromUserAction: Bool) async {
        guard let repository, let session else { return }
        guard let userID = await session.currentUserID else { return }

        let profileID = ProfileID(userID.rawValue)
        if viewerID != profileID {
            viewerID = profileID
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
        DailyCheckInReminderCoordinator.shared.syncIfNeeded()
    }
}
