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
        PsychologyReportTemplate.allCases.map { template in
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
    }
}

extension PsychologyReportsSnapshot: Equatable {
    static func == (lhs: PsychologyReportsSnapshot, rhs: PsychologyReportsSnapshot) -> Bool {
        lhs.computedAt == rhs.computedAt && lhs.catalogPeriods == rhs.catalogPeriods
    }
}
