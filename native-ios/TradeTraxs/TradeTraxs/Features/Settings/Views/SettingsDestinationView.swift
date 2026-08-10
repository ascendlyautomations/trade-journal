import SwiftUI

/// Maps ``SettingsRoute`` → feature screens for the Profile navigation stack.
struct SettingsDestinationView: View {
    let route: SettingsRoute
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    let currentUserProfile: CurrentUserProfileStore?

    var body: some View {
        Group {
            switch route {
            case .home:
                SettingsHomeView(
                    navigationCoordinator: navigationCoordinator,
                    authenticationCoordinator: authenticationCoordinator
                )
            case .account:
                SettingsAccountView(
                    data: data,
                    authenticationCoordinator: authenticationCoordinator,
                    navigationCoordinator: navigationCoordinator
                )
            case .security:
                SettingsSecurityView(
                    data: data,
                    authenticationCoordinator: authenticationCoordinator,
                    navigationCoordinator: navigationCoordinator
                )
            case .profile:
                SettingsProfileView(data: data, profileStore: currentUserProfile)
            case .notifications:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            case .notificationsMessages:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .messages
                )
            case .notificationsSocial:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .social
                )
            case .notificationsRooms:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .rooms
                )
            case .notificationsAchievements:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .achievements
                )
            case .notificationsProduct:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .product
                )
            case .subscription:
                SettingsSubscriptionView(
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            case .tradingAccounts:
                SettingsTradingAccountsView(data: data)
            case .propFirm:
                SettingsTradingAccountsView(data: data, propFirmOnly: true)
            case .privacy:
                SettingsPrivacyView(data: data, profileStore: currentUserProfile)
            case .affiliate:
                SettingsAffiliateView(data: data)
            case .support:
                SettingsSupportView()
            case .about:
                SettingsAboutView(navigationCoordinator: navigationCoordinator)
            case .legalTerms, .legalPrivacy, .legalCommunityGuidelines, .legalRefund:
                SettingsLegalView(route: route)
            }
        }
    }
}
