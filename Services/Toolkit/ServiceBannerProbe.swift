import Foundation
import Network

enum ServiceBannerParser {
    static func parse(port: UInt16, text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if port == 22, let range = trimmed.range(of: "SSH-2.0-") {
            let version =
                String(trimmed[range.upperBound...])
                .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let cleaned = version.replacingOccurrences(of: "_", with: " ")
            return cleaned.isEmpty ? nil : cleaned
        }

        if httpPorts.contains(port) {
            for line in trimmed.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                    parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Server")
                        == .orderedSame
                else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }

        if [21, 25, 110, 143, 587].contains(port) {
            let known = [
                "vsFTPd", "ProFTPD", "Pure-FTPd", "FileZilla", "Postfix", "Exim",
                "Sendmail", "OpenSMTPD", "Dovecot", "Courier",
            ]
            for token in known {
                guard let range = trimmed.range(of: token, options: .caseInsensitive) else {
                    continue
                }
                let tail =
                    trimmed[range.upperBound...]
                    .split(whereSeparator: { $0.isWhitespace || $0 == ")" || $0 == "(" })
                    .first.map(String.init) ?? ""
                return tail.isEmpty ? token : "\(token) \(tail)"
            }
        }

        return nil
    }

    static let httpPorts: Set<UInt16> = [80, 3000, 5000, 8000, 8080, 9000]
}

struct ServiceBannerProbe: Sendable {
    func probe(host: String, port: UInt16, timeout: TimeInterval = 2) async -> String? {
        let request: Data? =
            ServiceBannerParser.httpPorts.contains(port)
            ? "HEAD / HTTP/1.0\r\nHost: \(host)\r\n\r\n".data(using: .utf8)
            : nil
        guard
            let data = await TCPBannerReader.read(
                host: host, port: port, request: request, timeout: timeout)
        else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return ServiceBannerParser.parse(port: port, text: text)
    }
}

private enum TCPBannerReader {
    static func read(
        host: String, port: UInt16, request: Data?, timeout: TimeInterval
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any,
                using: .tcp
            )
            let box = CompletionBox(continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let request {
                        connection.send(
                            content: request,
                            completion: .contentProcessed { error in
                                if error != nil {
                                    box.finish(nil)
                                    connection.cancel()
                                }
                            })
                    }
                    connection.receive(
                        minimumIncompleteLength: 1, maximumLength: 4096
                    ) { data, _, _, _ in
                        box.finish(data)
                        connection.cancel()
                    }
                case .failed, .cancelled:
                    box.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                box.finish(nil)
                connection.cancel()
            }
        }
    }

    private final class CompletionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let continuation: CheckedContinuation<Data?, Never>

        init(continuation: CheckedContinuation<Data?, Never>) {
            self.continuation = continuation
        }

        func finish(_ data: Data?) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.resume(returning: data)
        }
    }
}
