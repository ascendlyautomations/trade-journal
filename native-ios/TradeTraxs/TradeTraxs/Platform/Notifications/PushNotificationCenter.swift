import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// Bridges non-Sendable APNs payloads into `@Sendable` task boundaries.
private final class PushUserInfoBox: @unchecked Sendable {
    nonisolated(unsafe) let userInfo: [AnyHashable: Any]

    nonisolated init(_ userInfo: [AnyHashable: Any]) {
        self.userInfo = userInfo
    }
}

/// Centralized APNs ownership — features never register for remote notifications themselves.
///
/// Responsibilities:
/// - Permission + `registerForRemoteNotifications`
/// - Token → existing BFF `/api/push/register`
/// - Foreground presentation policy
/// - Tap → ``NotificationRouterFacade``
/// - Badge mirror from backend BadgeService (`GET /api/push/badge`)
@Observable
@MainActor
final class PushNotificationCenter: NSObject {
    private let tokenClient: any DevicePushTokenClienting
    private let navigation: NavigationEnvironment
    private let activityInbox: ActivityInboxStore
    private let badgeController: AppIconBadgeController
    private let routerFacade: NotificationRouterFacade
    /// Soft Activity unread refresh after push (existing NotificationRepository).
    private var notificationsRepository: (any NotificationRepository)?

    private let tokenDefaultsKey = "tt.ios.push.device_token"
    private let bannersDefaultsKey = "tt.ios.push.foreground_banners"

    private(set) var authorizationStatus: SystemNotificationAuthorizationStatus = .notDetermined
    private(set) var deviceTokenHex: String?
    private(set) var lastRegistrationError: String?
    private(set) var isRegistering = false

    /// Foreground banner preference (distinct from in-app notification category toggles).
    var foregroundBannersEnabled: Bool {
        get { UserDefaults.standard.object(forKey: bannersDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: bannersDefaultsKey) }
    }

    private var lastRegisteredToken: String?
    private let installationIDDefaultsKey = "tt.ios.push.installation_id"
    private var installationID: String {
        if let existing = UserDefaults.standard.string(forKey: installationIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty,
           existing != "unknown"
        {
            return existing
        }
        let generated =
            UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        UserDefaults.standard.set(generated, forKey: installationIDDefaultsKey)
        return generated
    }

    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private var isBound = false

    init(
        tokenClient: any DevicePushTokenClienting,
        navigation: NavigationEnvironment,
        activityInbox: ActivityInboxStore,
        badgeController: AppIconBadgeController,
        routerFacade: NotificationRouterFacade
    ) {
        self.tokenClient = tokenClient
        self.navigation = navigation
        self.activityInbox = activityInbox
        self.badgeController = badgeController
        self.routerFacade = routerFacade
        super.init()
        deviceTokenHex = UserDefaults.standard.string(forKey: tokenDefaultsKey)
    }

    func attachNotificationsRepository(_ repository: any NotificationRepository) {
        notificationsRepository = repository
    }

    func bindIfNeeded() {
        guard !isBound else { return }
        isBound = true
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
        syncBadgeFromActivity()
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await SystemNotificationAuthorization.currentStatus()
    }

    /// Call after authentication succeeds / session restore.
    func syncRegistrationForAuthenticatedSession() {
        bindIfNeeded()
        Task {
            await refreshAuthorizationStatus()
            if authorizationStatus == .notDetermined {
                let granted = await SystemNotificationAuthorization.requestAuthorization()
                authorizationStatus = granted ? .authorized : .denied
            }
            guard authorizationStatus.isEnabled else { return }
            UIApplication.shared.registerForRemoteNotifications()
            if let token = deviceTokenHex {
                await uploadToken(token)
            }
        }
    }

    /// Call on logout — removes this install's token from the shared backend.
    /// Must be awaited **before** clearing the auth session when possible.
    func unregisterForLogout() async {
        await unregisterPush(allDevices: false)
    }

    /// Call after successful account deletion — mirrors web Settings delete flow.
    func unregisterForAccountDeletion() async {
        await unregisterPush(allDevices: true)
    }

    private func unregisterPush(allDevices: Bool) async {
        let token = deviceTokenHex
        lastRegisteredToken = nil
        do {
            try await tokenClient.unregister(deviceToken: token, allDevices: allDevices)
            AppLog.notifications.info(
                "APNs device token unregistered (\(allDevices ? "all devices" : "this device", privacy: .public))"
            )
        } catch {
            AppLog.notifications.error(
                "APNs unregister failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        badgeController.clear()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func applicationDidRegisterForRemoteNotifications(deviceToken: Data) {
        let hex = deviceToken.hexString
        let previous = UserDefaults.standard.string(forKey: tokenDefaultsKey)
        deviceTokenHex = hex
        UserDefaults.standard.set(hex, forKey: tokenDefaultsKey)
        Task { await uploadToken(hex, previousDeviceToken: previous == hex ? nil : previous) }
    }

    func applicationDidFailToRegisterForRemoteNotifications(error: Error) {
        lastRegistrationError = error.localizedDescription
        AppLog.notifications.error(
            "APNs registration failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        route(userInfo: userInfo)
        // Mirror backend BadgeService — do not trust a stale APNs payload integer alone.
        AppIconBadgeSync.refresh(animated: false)
        Task { await softRefreshActivityUnread() }
    }

    func handleForegroundRemoteNotification(userInfo: [AnyHashable: Any]) {
        AppIconBadgeSync.refresh(animated: true)
        Task { await softRefreshActivityUnread() }
    }

    func syncBadgeFromActivity() {
        AppIconBadgeSync.refresh(animated: true)
    }

    // MARK: - Private

    private func uploadToken(_ token: String, previousDeviceToken: String? = nil) async {
        guard navigation.store.sessionPhase == .authenticated else { return }
        if lastRegisteredToken == token { return }
        isRegistering = true
        defer { isRegistering = false }
        do {
            try await tokenClient.register(
                deviceToken: token,
                previousDeviceToken: previousDeviceToken,
                installationID: installationID,
                appVersion: appVersion
            )
            lastRegisteredToken = token
            lastRegistrationError = nil
            AppLog.notifications.info("APNs device token registered with BFF")
        } catch {
            lastRegistrationError = error.localizedDescription
            AppLog.notifications.error(
                "APNs token upload failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func softRefreshActivityUnread() async {
        guard let notificationsRepository else { return }
        if let count = try? await notificationsRepository.unreadCount() {
            activityInbox.setUnreadCount(count)
        }
    }

    private func route(userInfo: [AnyHashable: Any]) {
        let destination = PushNotificationPayloadParser.parse(userInfo: userInfo)
        if let roomID = destination.roomID {
            RoomNavigationFocusStore.shared.seed(
                roomID: roomID,
                sectionID: destination.sectionID,
                messageID: destination.messageID ?? destination.threadID
            )
        }
        _ = routerFacade.route(
            destination,
            using: navigation.coordinator,
            store: navigation.store
        )
    }
}

extension PushNotificationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfoBox = PushUserInfoBox(notification.request.content.userInfo)
        Task { @MainActor in
            handleForegroundRemoteNotification(userInfo: userInfoBox.userInfo)
            let destination = PushNotificationPayloadParser.parse(userInfo: userInfoBox.userInfo)
            let options = PushNotificationPresentationPolicy.foregroundOptions(
                for: destination,
                bannersEnabled: foregroundBannersEnabled
            )
            completionHandler(options)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationResponse(response)
            completionHandler()
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02.2hhx", $0) }.joined()
    }
}
