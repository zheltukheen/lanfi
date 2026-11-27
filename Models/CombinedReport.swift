import Foundation
import LanFiCore

/// One document that carries the evidence a support call or a client handover
/// needs: the current scan, the survey, security findings, diagnostics, speed
/// history and recent monitor events. Rendering lives in
/// `CombinedReportExporter`; this value is pure so it can be tested.
struct CombinedReport: Equatable {
    struct ScanRow: Equatable {
        let ssid: String
        let bssid: String
        let band: String
        let channel: Int
        let widthMHz: Int
        let signal: Int
        let quality: Int?
        let security: String
    }

    struct SurveySummary: Equatable {
        let name: String
        let sampleCount: Int
        let averageRSSI: Int?
        let weakestRSSI: Int?
        let strongestRSSI: Int?
        /// G9 verdict, absent when no requirement is enabled.
        var requirementSummary: String? = nil
        var verdict: String? = nil
    }

    struct Finding: Equatable {
        let severity: String
        let title: String
        let detail: String
        let bssid: String
    }

    struct DiagnosticRow: Equatable {
        let title: String
        let status: String
        let value: String
        let detail: String
    }

    struct SpeedRow: Equatable {
        let at: Date
        let downloadMbps: Double?
        let uploadMbps: Double?
        let latencyMilliseconds: Double?
        let grade: String?
    }

    struct EventRow: Equatable {
        let at: Date
        let kind: String
        let detail: String
    }

    /// G10 verdict over the stored monitor history. Absent when the monitor
    /// has no samples, so a report never claims a score it cannot back.
    struct ReliabilitySummary: Equatable {
        struct ProblemRow: Equatable {
            let title: String
            let count: Int
            let range: String
        }

        let grade: String
        let score: Int?
        let detail: String
        let problems: [ProblemRow]

        static func make(_ assessment: ReliabilityAssessment) -> ReliabilitySummary? {
            guard assessment.sampleCount > 0 else { return nil }
            let detail: String
            if let score = assessment.score {
                detail = String(
                    format: String(
                        localized: "%lld of 100 · %lld samples over %@ · average %lld dBm"),
                    score, assessment.sampleCount, duration(assessment.observedSeconds),
                    assessment.averageRSSI ?? 0)
            } else {
                detail = String(
                    format: String(localized: "Not enough data: %lld samples over %@."),
                    assessment.sampleCount, duration(assessment.observedSeconds))
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let problems = assessment.problems.map { problem in
                ProblemRow(
                    title: problem.signal.title, count: problem.count,
                    range:
                        "\(formatter.string(from: problem.firstAt)) – \(formatter.string(from: problem.lastAt))"
                )
            }
            return ReliabilitySummary(
                grade: assessment.grade.title, score: assessment.score, detail: detail,
                problems: problems)
        }

        private static func duration(_ seconds: TimeInterval) -> String {
            let total = max(0, Int(seconds.rounded()))
            if total >= 3_600 { return "\(total / 3_600) h \(total % 3_600 / 60) min" }
            if total >= 60 { return "\(total / 60) min" }
            return "\(total) s"
        }
    }

    /// Per-site branding for a client handover. Optional so reports made from
    /// an unnamed survey keep the generic LanFi header.
    struct Branding: Equatable {
        let title: String?
        let clientName: String?
        let notes: String?
    }

    let generatedAt: Date
    let branding: Branding?
    let networkCount: Int
    let averageQuality: Int
    let scan: [ScanRow]
    let survey: SurveySummary?
    let findings: [Finding]
    let diagnostics: [DiagnosticRow]
    let speedTests: [SpeedRow]
    let events: [EventRow]
    let reliability: ReliabilitySummary?
}

enum CombinedReportBuilder {
    static func make(
        generatedAt: Date = Date(),
        networks: [NetworkModel],
        analysis: AnalysisReport,
        survey: SurveyProject?,
        diagnostics: DiagnosticsReport?,
        speedTests: [ThroughputMeasurement],
        events: [MonitorEvent],
        monitorSamples: [MonitorSample] = [],
        maximumEvents: Int = 40
    ) -> CombinedReport {
        let scan =
            networks
            .sorted { $0.signal > $1.signal }
            .map { network in
                CombinedReport.ScanRow(
                    ssid: network.displaySSID,
                    bssid: network.bssid,
                    band: network.bandLabel,
                    channel: network.channel,
                    widthMHz: network.channelWidthMHz,
                    signal: network.signal,
                    quality: analysis.metricsByNetworkId[network.id]?.qualityScore,
                    security: network.security
                )
            }

        let surveySummary: CombinedReport.SurveySummary? = survey.map { project in
            let values = project.samples.map(\.rssi)
            let validation = SurveyValidator.evaluate(
                samples: project.samples, requirement: project.requirement)
            return CombinedReport.SurveySummary(
                name: project.name,
                sampleCount: values.count,
                averageRSSI: values.isEmpty
                    ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()),
                weakestRSSI: values.min(),
                strongestRSSI: values.max(),
                requirementSummary: validation.map(\.requirement.summary),
                verdict: validation?.reportLine
            )
        }

        let findings = analysis.securityFindings.map { finding in
            CombinedReport.Finding(
                severity: label(for: finding.severity),
                title: finding.title,
                detail: finding.detail,
                bssid: finding.bssid
            )
        }

        let diagnosticRows =
            diagnostics?.checks.map { check in
                CombinedReport.DiagnosticRow(
                    title: check.title,
                    status: check.status.label,
                    value: check.value,
                    detail: check.detail
                )
            } ?? []

        let speedRows = speedTests.suffix(10).map { measurement in
            CombinedReport.SpeedRow(
                at: measurement.testedAt,
                downloadMbps: measurement.report.downloadMbps,
                uploadMbps: measurement.report.uploadMbps,
                latencyMilliseconds: measurement.report.latencyMilliseconds,
                grade: measurement.report.bufferbloatGrade
            )
        }

        let eventRows = events.suffix(max(1, maximumEvents)).map { event in
            CombinedReport.EventRow(at: event.at, kind: event.kind.title, detail: event.detail)
        }

        let reliability = CombinedReport.ReliabilitySummary.make(
            ReliabilityAssessor.assess(
                samples: monitorSamples.map { ReliabilitySample(at: $0.at, rssi: $0.rssi) },
                signals: events.compactMap { event in
                    event.kind.reliabilitySignal.map {
                        ReliabilitySignalRecord(signal: $0, at: event.at)
                    }
                }))

        let branding = survey.flatMap { project -> CombinedReport.Branding? in
            let title = project.reportTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let client = project.clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = project.reportNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !(title ?? "").isEmpty || !(client ?? "").isEmpty || !(notes ?? "").isEmpty
            else { return nil }
            return CombinedReport.Branding(
                title: (title ?? "").isEmpty ? nil : title,
                clientName: (client ?? "").isEmpty ? nil : client,
                notes: (notes ?? "").isEmpty ? nil : notes)
        }

        return CombinedReport(
            generatedAt: generatedAt,
            branding: branding,
            networkCount: networks.count,
            averageQuality: analysis.averageQuality,
            scan: scan,
            survey: surveySummary,
            findings: findings,
            diagnostics: diagnosticRows,
            speedTests: speedRows,
            events: eventRows,
            reliability: reliability
        )
    }

    /// Most severe first, so the HTML can render findings in priority order.
    static func sortedFindings(_ findings: [CombinedReport.Finding]) -> [CombinedReport.Finding] {
        let order = ["Critical": 0, "Warning": 1, "Info": 2]
        return findings.sorted { order[$0.severity, default: 3] < order[$1.severity, default: 3] }
    }

    private static func label(for severity: IssueSeverity) -> String {
        switch severity {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }
}
