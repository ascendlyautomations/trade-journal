import Foundation
import OSLog
import UserNotifications

/// Local Performance Report reminders — Saturday and 1st-of-month at 1:00 PM Eastern.
enum PerformanceReportReminderScheduler {
  static let identifierPrefix = "performance-report:"

  static let weeklyIdentifier = "performance-report:weekly:1300:wd7"
  static let monthlyIdentifier = "performance-report:monthly:1300:d1"

#if DEBUG
  static let debugWeeklyIdentifier = "performance-report:debug:weekly"
  static let debugMonthlyIdentifier = "performance-report:debug:monthly"
  private static let debugProbeDelaySeconds: TimeInterval = 90
#endif

  static let reminderHour = 13
  static let reminderMinute = 0

  static let weeklyNotificationBody = "Your weekly performance report is ready!"
  static let monthlyNotificationBody = "Your monthly performance report is ready!"

  static var canonicalIdentifiers: [String] {
    [weeklyIdentifier, monthlyIdentifier]
  }

  static func isDebugProbeIdentifier(_ identifier: String) -> Bool {
    identifier.hasPrefix("\(identifierPrefix)debug:")
  }

  /// Returns whether production weekly + monthly repeating requests are pending after sync.
  @MainActor
  static func sync(isEnabled: Bool) async -> Bool {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    let pendingIDs = pending.map(\.identifier)

    guard isEnabled else {
      let productionIDs = pendingIDs.filter {
        shouldRemove(identifier: $0) && !isDebugProbeIdentifier($0)
      }
      if !productionIDs.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: productionIDs)
      }
      return false
    }

    let hasCanonical = Set(pendingIDs).isSuperset(of: Set(canonicalIdentifiers))
    if hasCanonical {
      return true
    }

    let staleIDs = pendingIDs.filter {
      shouldRemove(identifier: $0) && !isDebugProbeIdentifier($0)
    }
    if !staleIDs.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: staleIDs)
    }

    await scheduleWeekly(center: center)
    await scheduleMonthly(center: center)
    return await hasCanonicalRemindersScheduled(center: center)
  }

  static func shouldRemove(identifier: String) -> Bool {
    identifier.hasPrefix(identifierPrefix)
  }

  @MainActor
  static func cancelAll() async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    let ids = pending.map(\.identifier).filter { shouldRemove(identifier: $0) }
    guard !ids.isEmpty else { return }
    center.removePendingNotificationRequests(withIdentifiers: ids)
  }

  @MainActor
  private static func hasCanonicalRemindersScheduled(
    center: UNUserNotificationCenter
  ) async -> Bool {
    let pending = await center.pendingNotificationRequests()
    let ids = Set(pending.map(\.identifier))
    return canonicalIdentifiers.allSatisfy { ids.contains($0) }
  }

  @MainActor
  private static func scheduleWeekly(center: UNUserNotificationCenter) async {
    let content = UNMutableNotificationContent()
    content.title = weeklyNotificationBody
    content.body = ""
    content.sound = .default
    content.userInfo = [
      "type": "trading_report",
      PerformanceReportReminderPeriodResolution.userInfoKey:
        PerformanceReportReminderPeriodResolution.Kind.weekly.rawValue,
    ]

    var components = DateComponents()
    components.timeZone = WeekdayEasternReminderSupport.easternTimeZone
    components.weekday = 7 // Saturday
    components.hour = reminderHour
    components.minute = reminderMinute

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(
      identifier: weeklyIdentifier,
      content: content,
      trigger: trigger
    )
    do {
      try await center.add(request)
    } catch {
      AppLog.notifications.error(
        "Performance report weekly reminder schedule failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  @MainActor
  private static func scheduleMonthly(center: UNUserNotificationCenter) async {
    let content = UNMutableNotificationContent()
    content.title = monthlyNotificationBody
    content.body = ""
    content.sound = .default
    content.userInfo = [
      "type": "trading_report",
      PerformanceReportReminderPeriodResolution.userInfoKey:
        PerformanceReportReminderPeriodResolution.Kind.monthly.rawValue,
    ]

    var components = DateComponents()
    components.timeZone = WeekdayEasternReminderSupport.easternTimeZone
    components.day = 1
    components.hour = reminderHour
    components.minute = reminderMinute

    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(
      identifier: monthlyIdentifier,
      content: content,
      trigger: trigger
    )
    do {
      try await center.add(request)
    } catch {
      AppLog.notifications.error(
        "Performance report monthly reminder schedule failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

#if DEBUG
  @MainActor
  static func cancelDebugProbesOnly() async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    let debugIDs = pending.map(\.identifier).filter { isDebugProbeIdentifier($0) }
    guard !debugIDs.isEmpty else { return }
    center.removePendingNotificationRequests(withIdentifiers: debugIDs)
  }

  /// One-shot weekly + monthly probes (~90s). Launch QA + Settings developer action.
  @MainActor
  static func scheduleDebugProbesForTesting() async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    let debugIDs = pending.map(\.identifier).filter { isDebugProbeIdentifier($0) }
    if !debugIDs.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: debugIDs)
    }
    await scheduleDebugProbe(
      center: center,
      identifier: debugWeeklyIdentifier,
      kind: .weekly,
      titleSuffix: " (DEBUG weekly)"
    )
    await scheduleDebugProbe(
      center: center,
      identifier: debugMonthlyIdentifier,
      kind: .monthly,
      titleSuffix: " (DEBUG monthly)"
    )
  }

  @MainActor
  private static func scheduleDebugProbe(
    center: UNUserNotificationCenter,
    identifier: String,
    kind: PerformanceReportReminderPeriodResolution.Kind,
    titleSuffix: String
  ) async {
    let content = UNMutableNotificationContent()
    content.title = (kind == .weekly ? weeklyNotificationBody : monthlyNotificationBody) + titleSuffix
    content.body = ""
    content.sound = .default
    content.userInfo = [
      "type": "trading_report",
      PerformanceReportReminderPeriodResolution.userInfoKey: kind.rawValue,
    ]

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(60, debugProbeDelaySeconds),
      repeats: false
    )
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    do {
      try await center.add(request)
    } catch {
      AppLog.notifications.error(
        "Performance report DEBUG probe failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
#endif
}