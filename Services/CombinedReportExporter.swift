import Foundation

/// Renders `CombinedReport` as a self-contained HTML document (no scripts, no
/// external assets) so it opens in any browser and prints cleanly to PDF.
enum CombinedReportExporter {
    static func html(for report: CombinedReport) -> String {
        var sections: [String] = []
        sections.append(summary(report))
        if let notes = report.branding?.notes { sections.append(brandingNotes(notes)) }
        sections.append(scanSection(report.scan))
        if let survey = report.survey { sections.append(surveySection(survey)) }
        sections.append(findingsSection(CombinedReportBuilder.sortedFindings(report.findings)))
        sections.append(diagnosticsSection(report.diagnostics))
        sections.append(speedSection(report.speedTests))
        sections.append(eventsSection(report.events))

        return """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <title>LanFi report — \(escape(dateText(report.generatedAt)))</title>
            <style>
            body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; margin: 32px; color: #1c1c1e; }
            h1 { font-size: 22px; margin: 0 0 4px; }
            h2 { font-size: 15px; margin: 28px 0 8px; text-transform: uppercase; letter-spacing: 0.06em; color: #6b6b70; }
            .meta { color: #6b6b70; font-size: 12px; }
            table { border-collapse: collapse; width: 100%; font-size: 12px; }
            th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid #e5e5ea; }
            th { color: #6b6b70; font-weight: 600; }
            .critical { color: #c0392b; font-weight: 600; }
            .warning { color: #b9770e; font-weight: 600; }
            .info { color: #2e86c1; font-weight: 600; }
            .tiles { display: flex; gap: 24px; margin-top: 12px; }
            .tile strong { display: block; font-size: 20px; }
            .tile span { color: #6b6b70; font-size: 12px; }
            footer { margin-top: 32px; color: #8e8e93; font-size: 11px; }
            </style>
            </head>
            <body>
            <h1>\(escape(report.branding?.title ?? "LanFi combined report"))</h1>
            <div class="meta">\(brandingLine(report))Generated \(escape(dateText(report.generatedAt))) · Everything below was captured locally on this Mac.</div>
            \(sections.joined(separator: "\n"))
            <footer>LanFi · read-only Wi-Fi analysis, no telemetry.</footer>
            </body>
            </html>
            """
    }

    // MARK: - Sections

    private static func summary(_ report: CombinedReport) -> String {
        """
        <div class="tiles">
          <div class="tile"><strong>\(report.networkCount)</strong><span>networks in scan</span></div>
          <div class="tile"><strong>\(report.averageQuality)</strong><span>average quality</span></div>
          <div class="tile"><strong>\(report.findings.count)</strong><span>security findings</span></div>
          <div class="tile"><strong>\(report.diagnostics.count)</strong><span>diagnostic checks</span></div>
        </div>
        """
    }

    private static func brandingLine(_ report: CombinedReport) -> String {
        guard let client = report.branding?.clientName else { return "" }
        return "Prepared for \(escape(client)) · "
    }

    private static func brandingNotes(_ notes: String) -> String {
        section("Notes", "<p>\(escape(notes).replacingOccurrences(of: "\n", with: "<br>"))</p>")
    }

    private static func scanSection(_ rows: [CombinedReport.ScanRow]) -> String {
        guard !rows.isEmpty else { return section("Scan", "<p>No networks in the current scan.</p>") }
        let body = rows.map { row in
            """
            <tr><td>\(escape(row.ssid))</td><td>\(escape(row.bssid))</td><td>\(escape(row.band))</td>\
            <td>\(row.channel)</td><td>\(row.widthMHz) MHz</td><td>\(row.signal) dBm</td>\
            <td>\(row.quality.map(String.init) ?? "—")</td><td>\(escape(row.security))</td></tr>
            """
        }.joined()
        return section(
            "Scan",
            """
            <table><thead><tr><th>SSID</th><th>BSSID</th><th>Band</th><th>Channel</th>\
            <th>Width</th><th>Signal</th><th>Quality</th><th>Security</th></tr></thead>\
            <tbody>\(body)</tbody></table>
            """)
    }

    private static func surveySection(_ survey: CombinedReport.SurveySummary) -> String {
        let average = survey.averageRSSI.map { "\($0) dBm" } ?? "—"
        let weakest = survey.weakestRSSI.map { "\($0) dBm" } ?? "—"
        let strongest = survey.strongestRSSI.map { "\($0) dBm" } ?? "—"
        return section(
            "Survey",
            """
            <p><strong>\(escape(survey.name))</strong> · \(survey.sampleCount) samples</p>
            \(verdictHTML(survey))
            <table><thead><tr><th>Average</th><th>Strongest</th><th>Weakest</th></tr></thead>\
            <tbody><tr><td>\(average)</td><td>\(strongest)</td><td>\(weakest)</td></tr></tbody></table>
            """)
    }

    /// G9: the requirement and its verdict, or nothing at all when the survey
    /// has no pass/fail profile.
    private static func verdictHTML(_ survey: CombinedReport.SurveySummary) -> String {
        guard let verdict = survey.verdict else { return "" }
        let requirement =
            survey.requirementSummary.map {
                "<p>Requirement: \(escape($0))</p>"
            } ?? ""
        return requirement + "<p><strong>\(escape(verdict))</strong></p>"
    }

    private static func findingsSection(_ findings: [CombinedReport.Finding]) -> String {
        guard !findings.isEmpty else {
            return section("Security", "<p>No security findings in this scan.</p>")
        }
        let body = findings.map { finding in
            let css = finding.severity.lowercased()
            return
                "<tr><td class=\"\(css)\">\(escape(finding.severity))</td><td>\(escape(finding.title))</td>"
                + "<td>\(escape(finding.detail))</td><td>\(escape(finding.bssid))</td></tr>"
        }.joined()
        return section(
            "Security",
            """
            <table><thead><tr><th>Severity</th><th>Finding</th><th>Detail</th><th>BSSID</th></tr></thead>\
            <tbody>\(body)</tbody></table>
            """)
    }

    private static func diagnosticsSection(_ rows: [CombinedReport.DiagnosticRow]) -> String {
        guard !rows.isEmpty else {
            return section("Diagnostics", "<p>No diagnostics have been run.</p>")
        }
        let body = rows.map { row in
            "<tr><td>\(escape(row.title))</td><td>\(escape(row.status))</td>"
                + "<td>\(escape(row.value))</td><td>\(escape(row.detail))</td></tr>"
        }.joined()
        return section(
            "Diagnostics",
            """
            <table><thead><tr><th>Check</th><th>Status</th><th>Value</th><th>Detail</th></tr></thead>\
            <tbody>\(body)</tbody></table>
            """)
    }

    private static func speedSection(_ rows: [CombinedReport.SpeedRow]) -> String {
        guard !rows.isEmpty else {
            return section("Speed history", "<p>No speed tests stored.</p>")
        }
        let body = rows.reversed().map { row in
            "<tr><td>\(escape(dateText(row.at)))</td>"
                + "<td>\(row.downloadMbps.map { String(format: "%.0f", $0) } ?? "—")</td>"
                + "<td>\(row.uploadMbps.map { String(format: "%.0f", $0) } ?? "—")</td>"
                + "<td>\(row.latencyMilliseconds.map { String(format: "%.0f", $0) } ?? "—")</td>"
                + "<td>\(escape(row.grade ?? "—"))</td></tr>"
        }.joined()
        return section(
            "Speed history",
            """
            <table><thead><tr><th>When</th><th>Down (Mbps)</th><th>Up (Mbps)</th><th>Latency (ms)</th>\
            <th>Bufferbloat</th></tr></thead><tbody>\(body)</tbody></table>
            """)
    }

    private static func eventsSection(_ rows: [CombinedReport.EventRow]) -> String {
        guard !rows.isEmpty else {
            return section("Monitor events", "<p>No Wi-Fi Monitor events recorded.</p>")
        }
        let body = rows.reversed().map { row in
            "<tr><td>\(escape(dateText(row.at)))</td><td>\(escape(row.kind))</td>"
                + "<td>\(escape(row.detail))</td></tr>"
        }.joined()
        return section(
            "Monitor events",
            """
            <table><thead><tr><th>When</th><th>Event</th><th>Detail</th></tr></thead>\
            <tbody>\(body)</tbody></table>
            """)
    }

    // MARK: - Helpers

    private static func section(_ title: String, _ body: String) -> String {
        "<h2>\(escape(title))</h2>\n\(body)"
    }

    static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
