import Foundation
import UIKit
import UserNotifications

/**
 TEMPORARY PUSH DEBUG — remove after delivery diagnosis.

 Wraps UNUserNotificationCenter.delegate so we log willPresent / didReceive
 without changing Capacitor's presentation options or action handling.
 Search logs for: [tt-push-debug]
 */
enum TradeTraxsPushDebug {
  static let prefix = "[tt-push-debug]"

  static func installDelegateWrapper() {
    TradeTraxsPushDebugCenter.shared.install()
  }

  static func logNotificationSettings(reason: String) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let payload: [String: Any] = [
        "reason": reason,
        "timestamp": isoNow(),
        "authorizationStatus": authStatusName(settings.authorizationStatus),
        "alertSetting": settingName(settings.alertSetting),
        "badgeSetting": settingName(settings.badgeSetting),
        "soundSetting": settingName(settings.soundSetting),
        "lockScreenSetting": settingName(settings.lockScreenSetting),
        "notificationCenterSetting": settingName(settings.notificationCenterSetting),
        "scheduledDeliverySetting": settingName(settings.scheduledDeliverySetting),
        "timeSensitiveSetting": settingName(settings.timeSensitiveSetting),
        "announcementSetting": settingName(settings.announcementSetting),
        "showPreviewsSetting": previewSettingName(settings.showPreviewsSetting),
        "criticalAlertSetting": settingName(settings.criticalAlertSetting),
        "carPlaySetting": settingName(settings.carPlaySetting),
        "providesAppNotificationSettings": settings.providesAppNotificationSettings,
      ]
      NSLog("%@ UNNotificationSettings %@", prefix, String(describing: payload))
    }
  }

  static func logDeliveredNotifications(reason: String) {
    UNUserNotificationCenter.current().getDeliveredNotifications { notes in
      let summaries: [[String: Any]] = notes.map { note in
        [
          "id": note.request.identifier,
          "title": note.request.content.title,
          "body": note.request.content.body,
          "userInfo": note.request.content.userInfo,
          "date": isoString(note.date),
        ]
      }
      NSLog(
        "%@ getDeliveredNotifications reason=%@ count=%d items=%@",
        prefix,
        reason,
        notes.count,
        String(describing: summaries)
      )
    }
  }

  static func logRemoteNotification(
    source: String,
    userInfo: [AnyHashable: Any],
    fetchCompletion: ((UIBackgroundFetchResult) -> Void)?
  ) {
    let appState = appStateName(UIApplication.shared.applicationState)
    let aps = userInfo["aps"] as? [String: Any]
    var title = ""
    var body = ""
    if let alert = aps?["alert"] as? [String: Any] {
      title = String(describing: alert["title"] ?? "")
      body = String(describing: alert["body"] ?? "")
    } else if let alert = aps?["alert"] as? String {
      body = alert
    }
    NSLog(
      "%@ %@ title=%@ body=%@ appState=%@ timestamp=%@ userInfo=%@",
      prefix,
      source,
      title,
      body,
      appState,
      isoNow(),
      String(describing: userInfo)
    )
    // Do not claim background-fetch work — preserve prior behavior.
    fetchCompletion?(.noData)
  }

  static func logDeviceToken(_ deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    #if DEBUG
    let environment = "sandbox/development"
    #else
    let environment = "production"
    #endif
    NSLog(
      "%@ didRegisterForRemoteNotifications token=%@ length=%d environment=%@ bundleId=%@ timestamp=%@",
      prefix,
      hex,
      hex.count,
      environment,
      Bundle.main.bundleIdentifier ?? "unknown",
      isoNow()
    )
  }

  static func logRegistrationFailure(_ error: Error) {
    NSLog(
      "%@ didFailToRegisterForRemoteNotifications error=%@ timestamp=%@",
      prefix,
      error.localizedDescription,
      isoNow()
    )
  }

  private static func isoNow() -> String {
    isoString(Date())
  }

  private static func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private static func appStateName(_ state: UIApplication.State) -> String {
    switch state {
    case .active: return "foreground/active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }

  private static func authStatusName(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    @unknown default: return "unknown(\(status.rawValue))"
    }
  }

  private static func settingName(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported: return "notSupported"
    case .disabled: return "disabled"
    case .enabled: return "enabled"
    @unknown default: return "unknown(\(setting.rawValue))"
    }
  }

  private static func previewSettingName(_ setting: UNShowPreviewsSetting) -> String {
    switch setting {
    case .always: return "always"
    case .whenAuthenticated: return "whenAuthenticated"
    case .never: return "never"
    @unknown default: return "unknown(\(setting.rawValue))"
    }
  }
}

/// Forwards to Capacitor's existing UNUserNotificationCenterDelegate after logging.
/// Only installs once a prior delegate exists so presentation options stay unchanged.
private final class TradeTraxsPushDebugCenter: NSObject, UNUserNotificationCenterDelegate {
  static let shared = TradeTraxsPushDebugCenter()

  private weak var previous: UNUserNotificationCenterDelegate?

  func install() {
    let center = UNUserNotificationCenter.current()
    if center.delegate === self {
      return
    }
    // Wait for Capacitor's NotificationRouter — never steal the delegate with no forward target.
    guard let current = center.delegate, current !== self else {
      NSLog(
        "%@ delegate wrapper waiting (Capacitor not ready) timestamp=%@",
        TradeTraxsPushDebug.prefix,
        ISO8601DateFormatter().string(from: Date())
      )
      return
    }
    previous = current
    center.delegate = self
    NSLog(
      "%@ delegate wrapper installed previous=%@ timestamp=%@",
      TradeTraxsPushDebug.prefix,
      String(describing: previous),
      ISO8601DateFormatter().string(from: Date())
    )
    TradeTraxsPushDebug.logNotificationSettings(reason: "delegate_install")
    TradeTraxsPushDebug.logDeliveredNotifications(reason: "delegate_install")
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let content = notification.request.content
    let appState = UIApplication.shared.applicationState
    NSLog(
      "%@ willPresent title=%@ body=%@ appState=%@ timestamp=%@ userInfo=%@",
      TradeTraxsPushDebug.prefix,
      content.title,
      content.body,
      appState == .active ? "foreground/active" : appState == .background ? "background" : "inactive",
      ISO8601DateFormatter().string(from: Date()),
      String(describing: content.userInfo)
    )

    guard let previous else {
      NSLog("%@ willPresent ERROR: no previous delegate — completing with []", TradeTraxsPushDebug.prefix)
      completionHandler([])
      return
    }
    previous.userNotificationCenter?(
      center,
      willPresent: notification,
      withCompletionHandler: completionHandler
    )
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let content = response.notification.request.content
    let appState = UIApplication.shared.applicationState
    NSLog(
      "%@ didReceive actionId=%@ title=%@ body=%@ appState=%@ timestamp=%@ userInfo=%@",
      TradeTraxsPushDebug.prefix,
      response.actionIdentifier,
      content.title,
      content.body,
      appState == .active ? "foreground/active" : appState == .background ? "background" : "inactive",
      ISO8601DateFormatter().string(from: Date()),
      String(describing: content.userInfo)
    )

    guard let previous else {
      completionHandler()
      return
    }
    previous.userNotificationCenter?(
      center,
      didReceive: response,
      withCompletionHandler: completionHandler
    )
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    openSettingsFor notification: UNNotification?
  ) {
    NSLog(
      "%@ openSettingsFor timestamp=%@",
      TradeTraxsPushDebug.prefix,
      ISO8601DateFormatter().string(from: Date())
    )
    previous?.userNotificationCenter?(center, openSettingsFor: notification)
  }
}
