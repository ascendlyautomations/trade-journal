import Foundation

/// Keeps local Performance Report reminders aligned with Pro access and notification authorization.
@MainActor
final class PerformanceReportReminderCoordinator {
  static let shared = PerformanceReportReminderCoordinator()

  private var syncTask: Task<Void, Never>?

#if DEBUG
  private var scheduledDebugProbesThisLaunch = false
#endif

  private init() {}

  func syncIfNeeded(profileID: ProfileID?) {
    syncTask?.cancel()
    syncTask = Task { [weak self] in
      await self?.reconcile(profileID: profileID)
    }
  }

  /// Aligns local schedules with Pro + notification auth and mirrors state for this installation.
  func reconcile(profileID: ProfileID?) async {
    await sync(profileID: profileID)
  }

  func sync(profileID: ProfileID?) async {
    guard !Task.isCancelled else { return }

    let authorization = await SystemNotificationAuthorization.currentStatus()
    let isPro = TraxProEffectiveEntitlement.hasVerifiedTraxProAccess(profileID: profileID)
    let enabled = authorization.isEnabled && isPro && profileID != nil

    let scheduled = await PerformanceReportReminderScheduler.sync(isEnabled: enabled)
    await PerformanceReportReminderServerSync.reportActive(enabled && scheduled)
#if DEBUG
    if enabled {
      if !scheduledDebugProbesThisLaunch {
        await PerformanceReportReminderScheduler.scheduleDebugProbesForTesting()
        scheduledDebugProbesThisLaunch = true
      }
    } else {
      await PerformanceReportReminderScheduler.cancelDebugProbesOnly()
    }
#endif
  }

  func cancelAll() async {
    syncTask?.cancel()
    syncTask = nil
    await PerformanceReportReminderScheduler.cancelAll()
    await PerformanceReportReminderServerSync.reportActive(false)
  }

#if DEBUG
  /// Re-schedules probes (~90s); also runs automatically once per DEBUG app launch when reminders are enabled.
  func scheduleDebugProbesForTesting() async {
    await PerformanceReportReminderScheduler.scheduleDebugProbesForTesting()
    scheduledDebugProbesThisLaunch = true
  }
#endif
}