import Foundation

/// Home-stack navigation helpers for Trading Reports.
enum ReportsNavigation {
    static func openCatalog(using coordinator: NavigationCoordinator) {
        coordinator.open(.home(.reports))
    }

    static func openDetail(_ reportID: ReportID, using coordinator: NavigationCoordinator) {
        coordinator.open(.home(.report(reportID)))
    }

    static func openYearlyDetail(year: Int, using coordinator: NavigationCoordinator) {
        coordinator.open(.home(.report(TradingReportYearRef(year: year).reportID)))
    }

    static func openPsychologyDetail(_ reportID: ReportID, using coordinator: NavigationCoordinator) {
        coordinator.open(.home(.report(reportID)))
    }
}
