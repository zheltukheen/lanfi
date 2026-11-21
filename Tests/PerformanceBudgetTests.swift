import Foundation
import LanFiCore
import XCTest

/// Performance budgets for the hot paths the analyzer touches on every scan.
///
/// The budgets are deliberately generous: they catch a complexity regression
/// (an accidental O(n²), a per-row JSON decode) rather than machine noise, so
/// the same tests can run on a developer Mac and on a shared CI runner.
final class PerformanceBudgetTests: XCTestCase {

    func testAnalyzerHandlesThreeHundredNetworksWithinBudget() throws {
        let networks = makeNetworks(count: 300)

        let started = Date()
        let report = NetworkAnalyzer.analyze(networks: networks)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(report.analyzedNetworkCount, 300)
        XCTAssertLessThan(
            elapsed, 1.0,
            "300-network analysis budget is 1 s, took \(String(format: "%.3f", elapsed)) s")
    }

    func testJSONExportOfThreeHundredNetworksWithinBudget() throws {
        let networks = makeNetworks(count: 300)
        let analysis = NetworkAnalyzer.analyze(networks: networks)
        let exporter = ScanJSONExporter(version: "perf", analysis: analysis)

        let started = Date()
        let payload = exporter.make(networks: networks)
        let data = try JSONSerialization.data(withJSONObject: payload)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertLessThan(
            elapsed, 1.0,
            "300-network JSON export budget is 1 s, took \(String(format: "%.3f", elapsed)) s")
    }

    func testRouteWindowStatisticsAndDetectionWithinBudget() throws {
        var samples: [RouteSample] = []
        for index in 0..<180 {
            let destinationMisses = index % 7 == 0
            var hops: [RouteHopSample] = []
            for hop in 1...30 {
                let missed = hop == 30 && destinationMisses
                hops.append(
                    RouteHopSample(
                        hop: hop,
                        address: missed ? nil : "10.0.\(hop).1",
                        latencyMilliseconds: missed ? nil : Double(hop) + Double(index % 5)))
            }
            samples.append(
                RouteSample(
                    at: Date(timeIntervalSince1970: TimeInterval(index)), hops: hops))
        }
        var detector = RouteChangeDetector()
        var tracker = RouteThresholdTracker()

        let started = Date()
        for sample in samples {
            _ = detector.observe(RoutePath(sample: sample), at: sample.at)
        }
        let stats = RouteHopStatistics.compute(samples: samples)
        _ = tracker.evaluate(stats: stats, settings: RouteMonitorSettings())
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(stats.count, 30)
        XCTAssertLessThan(
            elapsed, 0.25,
            "route window budget is 250 ms, took \(String(format: "%.3f", elapsed)) s")
    }

    private func makeNetworks(count: Int) -> [NetworkModel] {
        (0..<count).map { index in
            let band: WiFiBand = index.isMultiple(of: 2) ? .band24 : .band5
            return makeNetwork(
                id: "net-\(index)",
                bssid: String(
                    format: "02:00:%02X:%02X:%02X:%02X",
                    index / 1_048_576 % 256, index / 4096 % 256, index / 256 % 256, index % 256),
                ssid: "Net \(index % 20)",
                band: band,
                channel: band == .band24 ? 1 + index % 11 : 36 + (index % 4) * 20,
                signal: -40 - index % 50)
        }
    }
}
