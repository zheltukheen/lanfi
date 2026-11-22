import Foundation

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
            return CombinedReport.SurveySummary(
                name: project.name,
                sampleCount: values.count,
                averageRSSI: values.isEmpty
                    ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()),
                weakestRSSI: values.min(),
                strongestRSSI: values.max()
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
            events: eventRows
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
