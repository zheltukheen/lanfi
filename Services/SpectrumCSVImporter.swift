import Foundation

/// Imports hardware-spectrum traces from CSV. Accepts the Wi-Spy
/// Chanalyzer export layout (`Frequency (MHz),Amplitude (dBm)` rows after
/// an optional header) and any plain two-column `frequency,dbm` table.
enum SpectrumCSVImporter {
    static func parse(_ text: String, source: String = "CSV import") -> SpectrumSweep? {
        var frequencies: [Double] = []
        var amplitudes: [Double] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A comma, when present, is the column separator (standard CSV
            // with dot decimals); semicolon and tab cover European exports
            // that keep the comma as the decimal character.
            let separator: Character = line.contains(",") ? "," : (line.contains(";") ? ";" : "\t")
            let fields = line.split(separator: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2,
                let mhz = Double(fields[0]),
                mhz > 0,
                let dbm = Double(fields[1])
            else { continue }  // header rows and comments simply do not parse
            frequencies.append(mhz)
            amplitudes.append(dbm)
        }
        guard frequencies.count >= 2 else { return nil }
        let step = (frequencies.last! - frequencies.first!) / Double(frequencies.count - 1)
        guard step > 0 else { return nil }
        // A regular grid is required for the sweep model; tolerate tiny
        // jitter from exported decimals by keeping the nominal step.
        return SpectrumSweep(
            source: source,
            capturedAt: Date(),
            startMHz: frequencies.first!,
            stepMHz: step,
            amplitudes: amplitudes
        )
    }
}

enum SpectrumCSVExporter {
    /// One `frequency_mhz,dbm` pair per line, matching the importer so
    /// traces round-trip through LanFi.
    static func csv(_ sweep: SpectrumSweep) -> String {
        var lines: [String] = ["Frequency (MHz),Amplitude (dBm)"]
        for (index, dbm) in sweep.amplitudes.enumerated() {
            lines.append(
                String(format: "%.3f,%.1f", sweep.frequencyMHz(at: index), dbm)
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
