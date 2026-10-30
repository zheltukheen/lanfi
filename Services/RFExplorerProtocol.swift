import Foundation

/// RF Explorer serial protocol, as documented in the official UART/USB
/// protocol specification (rf-explorer.com). Implemented from the wire
/// format only — no third-party code is embedded.
///
/// Wire framing:
///  - Text lines start with `#` and end with `\r\n`. The spectrum-analyzer
///    configuration is the `#C2-F:` / `#C2-f:` variant.
///  - Spectrum sweeps are `$S` + one length byte + N amplitude bytes +
///    `\r\n`. `$s` means length × 16 (a zero length byte encodes 256×16)
///    and `$z` is an extended length: first byte × 256 + second byte.
///  - Each amplitude byte encodes dBm as byte / -2.0.
enum RFExplorerProtocol {

    struct Config: Equatable {
        var startMHz: Double
        var stepMHz: Double
        var dataPoints: Int
        var amplitudeTopDBm: Double
        var amplitudeBottomDBm: Double
        var offsetDB: Double
    }

    enum StreamEvent: Equatable {
        case config(Config)
        case sweep([Double], Config)
        /// Any other complete text line (serial numbers, acknowledgements…).
        case message(String)
    }

    /// Parses a `#C2-F:` / `#C2-f:` configuration line (without CRLF).
    /// Returns nil for any other or malformed line.
    static func parseConfigLine(_ line: String) -> Config? {
        guard line.hasPrefix("#C2-F:") || line.hasPrefix("#C2-f:") else { return nil }
        let isHighRes = line.hasPrefix("#C2-f:")
        let chars = Array(line)
        var pos = 6
        func take(_ count: Int) -> String? {
            guard pos + count <= chars.count else { return nil }
            let slice = String(chars[pos..<(pos + count)])
            pos += count
            return slice
        }
        func takeInt(_ count: Int) -> Int? {
            guard let slice = take(count) else { return nil }
            return Int(slice)
        }
        // Start frequency, KHz, 7 digits.
        guard let startKHz = takeInt(7) else { return nil }
        // Step frequency, Hz, 7 or 8 digits. `pos` sits on the comma after
        // the start field, so the step field starts at pos + 1; the comma
        // right after a 7-digit field marks the short variant (spec).
        let stepDigits = pos + 8 < chars.count && chars[pos + 8] == "," ? 7 : 8
        guard take(1) != nil else { return nil }  // comma
        guard let stepHz = takeInt(stepDigits) else { return nil }
        guard take(1) != nil else { return nil }  // comma
        guard let ampTop = takeInt(4) else { return nil }
        guard take(1) != nil else { return nil }  // comma
        guard let ampBottom = takeInt(4) else { return nil }
        guard take(1) != nil else { return nil }  // comma
        let pointDigits = isHighRes ? 5 : 4
        guard let dataPoints = takeInt(pointDigits) else { return nil }
        guard take(1) != nil else { return nil }  // comma
        guard take(2) != nil else { return nil }  // expansion flag pair ",0|1"
        guard take(3) != nil else { return nil }  // mode
        guard take(1) != nil else { return nil }  // comma
        guard takeInt(7) != nil else { return nil }  // min freq KHz
        guard take(1) != nil else { return nil }  // comma
        guard takeInt(7) != nil else { return nil }  // max freq KHz
        guard take(1) != nil else { return nil }  // comma
        guard takeInt(7) != nil else { return nil }  // max span KHz
        guard take(1) != nil else { return nil }  // comma
        guard takeInt(5) != nil else { return nil }  // RBW KHz
        guard take(1) != nil else { return nil }  // comma
        guard let offset = takeInt(4) else { return nil }
        return Config(
            startMHz: Double(startKHz) / 1000.0,
            stepMHz: Double(stepHz) / 1_000_000.0,
            dataPoints: dataPoints,
            amplitudeTopDBm: Double(ampTop),
            amplitudeBottomDBm: Double(ampBottom),
            offsetDB: Double(offset)
        )
    }

    /// Decodes one `$S` amplitude payload (the bytes after the length
    /// prefix) into dBm values. The result always has `config.dataPoints`
    /// entries; a short payload is padded with the bottom-of-scale value.
    static func decodeSweepPayload(_ bytes: [UInt8], config: Config) -> [Double] {
        let count = max(config.dataPoints, 0)
        let floor = config.amplitudeBottomDBm
        return (0..<count).map { index in
            guard index < bytes.count else { return floor }
            return Double(bytes[index]) / -2.0 + config.offsetDB
        }
    }

    /// Number of amplitude bytes announced by a sweep header, or nil when
    /// the header is not a recognised sweep packet.
    static func sweepPayloadLength(header: [UInt8]) -> Int? {
        guard header.count >= 2, header[0] == UInt8(ascii: "$") else { return nil }
        switch header[1] {
        case UInt8(ascii: "S"):
            guard header.count >= 3 else { return nil }
            return Int(header[2])
        case UInt8(ascii: "s"):
            guard header.count >= 3 else { return nil }
            let blocks = header[2] == 0 ? 256 : Int(header[2])
            return blocks * 16
        case UInt8(ascii: "z"):
            guard header.count >= 4 else { return nil }
            return Int(header[2]) * 256 + Int(header[3])
        default:
            return nil
        }
    }

    /// Frames an outgoing command: `#` + length byte (payload + 2) + payload.
    static func frameCommand(_ command: String) -> Data {
        var bytes: [UInt8] = [UInt8(ascii: "#"), UInt8(command.count + 2)]
        bytes.append(contentsOf: command.utf8)
        return Data(bytes)
    }

    /// Incremental deframer: feed raw serial bytes, receive decoded events.
    /// Handles interleaved text lines and binary sweeps, tolerates garbage
    /// bytes, and waits for more input when a packet is only partially
    /// buffered.
    final class StreamParser {
        private var buffer: [UInt8] = []
        private(set) var config: Config?

        func append(_ bytes: [UInt8]) -> [StreamEvent] {
            buffer.append(contentsOf: bytes)
            var events: [StreamEvent] = []
            while let event = nextDecodableEvent() {
                if case .config(let newConfig) = event {
                    config = newConfig
                }
                events.append(event)
            }
            // Garbage safety valve (mirrors the reference driver).
            if buffer.count > 66 * 1024 { buffer.removeAll() }
            return events
        }

        /// Returns the next decodable event, or nil when more bytes are
        /// needed. Consumes stray garbage bytes iteratively, so recursion
        /// depth stays bounded regardless of input quality.
        private func nextDecodableEvent() -> StreamEvent? {
            while !buffer.isEmpty {
                switch buffer[0] {
                case UInt8(ascii: "#"):
                    guard let event = nextLineEvent() else { return nil }
                    return event
                case UInt8(ascii: "$"):
                    guard buffer.count >= 2 else { return nil }
                    let type = buffer[1]
                    if type != UInt8(ascii: "S"), type != UInt8(ascii: "s"), type != UInt8(ascii: "z") {
                        buffer.removeFirst()
                        continue
                    }
                    guard let event = nextSweepEvent() else { return nil }
                    return event
                default:
                    buffer.removeFirst()
                }
            }
            return nil
        }

        /// Extracts a CRLF-terminated `#` line, or nil while incomplete.
        private func nextLineEvent() -> StreamEvent? {
            var index = 1
            while index + 1 < buffer.count {
                if buffer[index] == 13, buffer[index + 1] == 10 { break }
                index += 1
            }
            guard index + 1 < buffer.count else { return nil }  // no CRLF yet
            let lineBytes = Array(buffer[0..<index])  // keep the `#` prefix
            buffer.removeFirst(index + 2)
            guard let line = String(bytes: lineBytes, encoding: .utf8) else {
                return nextDecodableEvent()
            }
            if let config = RFExplorerProtocol.parseConfigLine(line) {
                return .config(config)
            }
            return .message(line)
        }

        /// Extracts one complete `$S/$s/$z` sweep, or nil while incomplete.
        private func nextSweepEvent() -> StreamEvent? {
            let headerSize = buffer[1] == UInt8(ascii: "z") ? 4 : 3
            guard buffer.count >= headerSize,
                let payloadLength = RFExplorerProtocol.sweepPayloadLength(header: buffer)
            else { return nil }
            let total = headerSize + payloadLength + 2
            guard buffer.count >= total else { return nil }  // wait for the rest
            // A missing CRLF trailer means a corrupted stream; drop one byte
            // and resynchronise rather than misframing the sweep.
            guard buffer[total - 2] == 13, buffer[total - 1] == 10 else {
                buffer.removeFirst()
                return nextDecodableEvent()
            }
            let payload = Array(buffer[headerSize..<(headerSize + payloadLength)])
            buffer.removeFirst(total)
            guard let config else { return nextDecodableEvent() }
            return .sweep(RFExplorerProtocol.decodeSweepPayload(payload, config: config), config)
        }
    }
}
