import XCTest
@testable import TradeTraxs

final class LeaderboardCurveChartDataTests: XCTestCase {
    func testTooltipPlacementClampsWithinContainer() {
        let width: CGFloat = 128
        let inset: CGFloat = 6
        let half = width / 2

        let left = LeaderboardCurveTooltipPlacement.clampedCenterX(
            anchorX: 0,
            containerMinX: 0,
            containerMaxX: 400,
            tooltipWidth: width,
            edgeInset: inset
        )
        XCTAssertEqual(left, inset + half, accuracy: 0.5)

        let right = LeaderboardCurveTooltipPlacement.clampedCenterX(
            anchorX: 400,
            containerMinX: 0,
            containerMaxX: 400,
            tooltipWidth: width,
            edgeInset: inset
        )
        XCTAssertEqual(right, 400 - inset - half, accuracy: 0.5)

        let mid = LeaderboardCurveTooltipPlacement.clampedCenterX(
            anchorX: 200,
            containerMinX: 0,
            containerMaxX: 400,
            tooltipWidth: width,
            edgeInset: inset
        )
        XCTAssertEqual(mid, 200, accuracy: 0.5)
    }
    func testDecodesRpcPayloadAndBuildsIndependentSortedSeries() throws {
        let json = """
        {
          "meta": {
            "contract_version": "v1",
            "server_time": "2026-08-13T12:00:00.000Z",
            "viewer_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
          },
          "data": {
            "timeframe": "month",
            "category": "pnl",
            "audience": "all",
            "supported": true,
            "metric_format": "currency",
            "highest_profile_id": "11111111-1111-1111-1111-111111111111",
            "lowest_profile_id": "22222222-2222-2222-2222-222222222222",
            "points": [
              {
                "day": "2026-08-10",
                "highest": 200,
                "lowest": -120,
                "you": 40,
                "average": 25,
                "population_count": 8
              },
              {
                "day": "2026-08-11",
                "highest": 260,
                "lowest": -80,
                "you": null,
                "average": 30,
                "population_count": 9
              },
              {
                "day": "2026-08-12",
                "highest": 310,
                "lowest": -50,
                "you": 95,
                "average": 44,
                "population_count": 10
              },
              {
                "day": "2026-08-12",
                "highest": 999,
                "lowest": 999,
                "you": 999,
                "average": 999,
                "population_count": 99
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let bootstrap = try JSONDecoder().decode(LeaderboardCurveV1.self, from: json)
        let points = LeaderboardCurveChartData.preparePoints(from: bootstrap.data.points)
        XCTAssertEqual(points.count, 3, "Duplicate NY days collapse to one bucket")
        XCTAssertEqual(points.map(\.dayKey), ["2026-08-10", "2026-08-11", "2026-08-12"])

        let prepared = LeaderboardCurveChartData.prepare(points: points)
        XCTAssertEqual(prepared.days.count, 3)

        for series in LeaderboardCurveSeries.allCases {
            let marks = prepared.marks(for: series)
            let dayKeys = marks.map(\.dayKey)
            XCTAssertEqual(dayKeys, dayKeys.sorted(), "\(series) must be chronological")
            XCTAssertEqual(Set(dayKeys).count, dayKeys.count, "\(series) must not repeat a day")
        }

        XCTAssertEqual(prepared.marks(for: .highest).map(\.value), [200, 260, 310])
        XCTAssertEqual(prepared.marks(for: .lowest).map(\.value), [-120, -80, -50])
        XCTAssertEqual(prepared.marks(for: .average).map(\.value), [25, 30, 44])
        XCTAssertEqual(prepared.marks(for: .you).map(\.dayKey), ["2026-08-10", "2026-08-11", "2026-08-12"])
        XCTAssertEqual(prepared.marks(for: .you).map(\.value), [40, 40, 95], "Last-known series value carries across inactive days")

        XCTAssertEqual(
            points[2].highest,
            310,
            "First duplicate day wins; chart must not zig-zag from duplicate RPC rows"
        )
    }

    func testCarryForwardDoesNotInventValuesBeforeFirstObservation() {
        guard let d1 = LeaderboardCurveChartPoint.parseDay("2026-08-10"),
              let d2 = LeaderboardCurveChartPoint.parseDay("2026-08-11") else {
            return XCTFail("NY day parse failed")
        }
        let points = [
            LeaderboardCurveChartPoint(
                dayKey: "2026-08-10",
                date: d1,
                highest: nil,
                lowest: nil,
                you: nil,
                average: 10
            ),
            LeaderboardCurveChartPoint(
                dayKey: "2026-08-11",
                date: d2,
                highest: 5,
                lowest: nil,
                you: nil,
                average: 20
            ),
        ]
        let prepared = LeaderboardCurveChartData.prepare(points: points)
        XCTAssertEqual(prepared.marks(for: .average).map(\.value), [10, 20])
        XCTAssertEqual(prepared.marks(for: .highest).map(\.dayKey), ["2026-08-11"], "No plot before first highest value")
        XCTAssertEqual(prepared.marks(for: .highest).map(\.value), [5])
    }

    func testWireValuesStayAlignedWithPlotMarksForTooltipParity() {
        guard let day = LeaderboardCurveChartPoint.parseDay("2026-08-10") else {
            return XCTFail("NY day parse failed")
        }
        let point = LeaderboardCurveChartPoint(
            dayKey: "2026-08-10",
            date: day,
            highest: 500,
            lowest: -200,
            you: 120,
            average: 80
        )
        let prepared = LeaderboardCurveChartData.prepare(points: [point])
        XCTAssertEqual(prepared.marks.count, 4)
        for mark in prepared.marks {
            XCTAssertEqual(mark.value, point.value(for: mark.series))
        }
    }
}