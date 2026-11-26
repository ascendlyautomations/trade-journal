#if DEBUG
import Foundation

extension DataEnvironment {
    /// Minimal signed-in production seam for TraxsPro preview unit tests (`detailCache` is the live cache under test).
    @MainActor
    static func traxsProPreviewTestHarness(
        detailCache: DetailPresentationCache,
        session: any SessionProviding
    ) -> DataEnvironment {
        let appConfiguration = AppConfiguration.make()
        let navigationStore = NavigationStore()
        let navigation = NavigationEnvironment(
            store: navigationStore,
            coordinator: NavigationCoordinator(store: navigationStore)
        )
        let authentication = AuthenticationEnvironment.make(
            appConfiguration: appConfiguration,
            navigation: navigation
        )
        let login = make(
            appConfiguration: appConfiguration,
            session: session,
            authenticationManager: authentication.manager,
            launchMode: .loginShell
        )
        return login.forking(
            detailCache: detailCache,
            trades: login.trades,
            tradeDetailRepository: DefaultTradeDetailRepository(
                trades: login.trades,
                session: session,
                detailCache: detailCache
            ),
            tradingReports: login.tradingReports,
            psychologyReports: login.psychologyReports,
            dailyCheckIns: login.dailyCheckIns,
            tradingPreferences: login.tradingPreferences
        )
    }
}
#endif