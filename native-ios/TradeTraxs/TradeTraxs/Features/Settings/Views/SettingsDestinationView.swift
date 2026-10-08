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
                    navigationCoordinator: navigationCoordinator,
                    profileStore: currentUserProfile
                )
            case .security:
                SettingsSecurityView(
                    data: data,
                    authenticationCoordinator: authenticationCoordinator,
                    navigationCoordinator: navigationCoordinator
                )
            case .profile:
                SettingsProfileView(
                    data: data,
                    profileStore: currentUserProfile,
                    appConfiguration: appEnvironment.configuration
                )
            case .notifications:
                SettingsNotificationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    pushNotifications: appEnvironment.pushNotifications
                )
            case .notificationsTradetraxsReminders:
                SettingsTradetraxsRemindersView(
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
                if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled {
                    SettingsSubscriptionView(
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                } else {
                    SettingsHomeView(authenticationCoordinator: authenticationCoordinator)
                }
            case .tradingAccounts:
                SettingsTradingAccountsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            case .brokerIntegrations:
                BrokerIntegrationsView(
                    data: data,
                    navigationCoordinator: navigationCoordinator
                )
            case .copyTradingAccounts:
                CopyTradingAccountsView(data: data)
            case .payouts:
                PayoutsScreenView(data: data, navigationCoordinator: navigationCoordinator)
            case .withdrawalDetail:
                if let historyItemID = WithdrawalDetailSelection.historyItemID {
                    WithdrawalDetailView(
                        historyItemID: historyItemID,
                        data: data,
                        navigationCoordinator: navigationCoordinator
                    )
                } else {
                    ExperienceEmptyState(
                        icon: .payouts,
                        title: "Withdrawal unavailable",
                        message: "Open this withdrawal again from Withdrawals."
                    )
                }
            case .privacy:
                SettingsPrivacyView(data: data, profileStore: currentUserProfile)
            case .privacyBlockedAccounts:
                SettingsBlockedAccountsView(
                    messages: data.messages,
                    detailCache: data.detailCache,
                    imagePipeline: data.imagePipeline,
                    navigationCoordinator: navigationCoordinator
                )
            case .privacyMutedAccounts:
                SettingsMutedAccountsView(
                    messages: data.messages,
                    imagePipeline: data.imagePipeline,
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
                if IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled {
                    SettingsAffiliateView(data: data)
                } else {
                    SettingsHomeView(authenticationCoordinator: authenticationCoordinator)
                }
            case .vault:
                VaultHomeView(data: data, navigationCoordinator: navigationCoordinator)
            case .support, .supportContact:
                ContactSupportFormView(repository: data.userSubmissions)
            case .productFeedback, .supportFeedback:
                SendFeedbackFormView(repository: data.userSubmissions)
            case .supportBugReport:
                ReportBugFormView(repository: data.userSubmissions)
            case .admin:
                AdminPortalView(
                    data: data,
                    navigationCoordinator: navigationCoordinator,
                    currentUserProfile: currentUserProfile
                )
            case .whatsNew:
                PlatformWhatsNewView(data: data)
            case .about:
                SettingsAboutView()
            case .legalTerms, .legalPrivacy, .legalCommunityGuidelines, .legalRefund:
                SettingsLegalView(route: route)
            }
        }
    }
}
