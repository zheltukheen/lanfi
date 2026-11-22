import Foundation

/// Fetches one sweep from a remote spectrum source. The WLAN Pi and NetAlly
/// workflows both end in a frequency/dBm table, so this accepts either a JSON
/// `{startMHz, stepMHz, amplitudes}` document or CSV. Read-only, one request,
/// strict timeout; no credentials are stored.
enum RemoteSpectrumSource {
    enum FetchError: LocalizedError, Equatable {
        case invalidURL
        case notHTTP
        case emptyResponse
        case unreadable

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Enter an http(s) URL for the remote sweep."
            case .notHTTP: return "Only http and https URLs are supported."
            case .emptyResponse: return "The remote source returned no data."
            case .unreadable:
                return "The response is neither a frequency/dBm table nor a sweep JSON document."
            }
        }
    }

    static func fetch(url: URL, timeout: TimeInterval = 8) async throws -> SpectrumSweep {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw url.scheme == nil ? FetchError.invalidURL : FetchError.notHTTP
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.emptyResponse
        }
        guard !data.isEmpty else { throw FetchError.emptyResponse }
        if let sweep = parseJSON(data, source: url.host ?? "remote") {
            return sweep
        }
        if let text = String(data: data, encoding: .utf8),
            let sweep = SpectrumCSVImporter.parse(text, source: url.host ?? "remote")
        {
            return sweep
        }
        throw FetchError.unreadable
    }

    /// JSON produced by a small collector on a WLAN Pi or exported by a tool:
    /// `{"startMHz":2400,"stepMHz":0.5,"amplitudes":[...]}`.
    static func parseJSON(_ data: Data, source: String) -> SpectrumSweep? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
            let object = raw as? [String: Any],
            let start = (object["startMHz"] as? NSNumber)?.doubleValue,
            let step = (object["stepMHz"] as? NSNumber)?.doubleValue,
            let values = object["amplitudes"] as? [Any],
            !values.isEmpty
        else { return nil }
        let amplitudes = values.compactMap { value -> Double? in
            (value as? NSNumber)?.doubleValue
        }
        guard amplitudes.count == values.count else { return nil }
        return SpectrumSweep(
            source: source, capturedAt: Date(), startMHz: start, stepMHz: step,
            amplitudes: amplitudes)
    }
}
