import SwiftUI

/// Maps ``SettingsRoute`` → feature screens on any tab navigation stack.
struct SettingsDestinationView: View {
    let route: SettingsRoute
    let data: DataEnvironment
    let navigationCoordinator: NavigationCoordinator
    let authenticationCoordinator: AuthenticationCoordinator
    let currentUserProfile: CurrentUserProfileStore?

    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Group {
            switch route {
            case .home:
                SettingsHomeView(
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
                    navigationCoordinator: navigationCoordinator,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .appearance:
                SettingsAppearanceView(themeManager: appEnvironment.themeManager)
            case .notificationsMessages:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .messages,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .notificationsSocial:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .social,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .notificationsRooms:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .rooms,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .notificationsAchievements:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .achievements,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .notificationsProduct:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    category: .product,
                    pushNotifications: appEnvironment.pushNotifications
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
            case .privacyBlockedAccounts:
                SettingsBlockedAccountsView(
                    messages: data.messages,
                    navigationCoordinator: navigationCoordinator
                )
            case .privacyMutedAccounts:
                SettingsMutedAccountsView(
                    messages: data.messages,
                    navigationCoordinator: navigationCoordinator
                )
            case .privacyMessageAudience:
                SettingsDmPrivacyPickerView(
                    viewModel: SettingsPrivacyViewModel(
                        profiles: data.profiles,
                        messages: data.messages,
                        session: data.session,
                        profilePrivacy: SettingsProfileViewModel(
                            profiles: data.profiles,
                            session: data.session,
                            profileStore: currentUserProfile
                        )
                    )
                )
            case .affiliate:
                SettingsAffiliateView(data: data)
            case .support:
                SettingsSupportView()
            case .about:
                SettingsAboutView()
            case .legalTerms, .legalPrivacy, .legalCommunityGuidelines, .legalRefund:
                SettingsLegalView(route: route)
            }
        }
    }
}
