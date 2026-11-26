import Foundation

@MainActor
enum PsychologyReportsBootstrap {
    struct Context {
        var psychologyReports: any PsychologyReportRepository
        var forceNetwork: Bool = false
    }

    struct Result: Equatable {
        var snapshot: PsychologyReportsSnapshot
        var cards: [PsychologyReportCardModel]
        var loadedAt: Date
    }

    static func load(_ context: Context) async throws -> Result {
        let snapshot = try await context.psychologyReports.ensureSnapshot(
            forceNetwork: context.forceNetwork
        )
        let cards = buildCards(from: snapshot)
        return Result(snapshot: snapshot, cards: cards, loadedAt: Date())
    }

    static func buildCards(from snapshot: PsychologyReportsSnapshot) -> [PsychologyReportCardModel] {
        var cards = PsychologyReportTemplate.allCases
            .filter { $0 != .custom }
            .map { cardModel(for: $0, snapshot: snapshot) }

        if let monthlyIndex = cards.firstIndex(where: { $0.template == .monthly }) {
            cards.insert(customCatalogCard(), at: monthlyIndex + 1)
        } else {
            cards.insert(customCatalogCard(), at: min(2, cards.count))
        }
        return cards
    }

    private static func cardModel(
        for template: PsychologyReportTemplate,
        snapshot: PsychologyReportsSnapshot
    ) -> PsychologyReportCardModel {
        let periods = snapshot.catalogPeriods.filter { $0.template == template }
        let latest = periods.first
        let report = latest.flatMap { snapshot.report(for: $0.reportID) }
        let availability: ReportAvailability = report == nil ? .readyToGenerate : .ready
        return PsychologyReportCardModel(
            template: template,
            title: template.catalogTitle,
            subtitle: report?.dateRangeLabel ?? template.catalogSubtitle,
            systemImage: template.systemImage,
            actionTitle: template.isPeriodic && periods.count > 1 ? "Choose Period" : availability.actionTitle,
            availability: availability,
            periodRef: latest,
            availablePeriods: periods
        )
    }

    private static func customCatalogCard() -> PsychologyReportCardModel {
        let template = PsychologyReportTemplate.custom
        return PsychologyReportCardModel(
            template: template,
            title: template.catalogTitle,
            subtitle: template.catalogSubtitle,
            systemImage: template.systemImage,
            actionTitle: "Choose Dates",
            availability: .readyToGenerate,
            periodRef: nil,
            availablePeriods: []
        )
    }
}
