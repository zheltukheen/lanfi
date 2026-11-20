import Foundation
import Network

/// A DNS-over-TLS resolver (RFC 7858). DoT is the third transport in the
/// comparison because a network can rewrite port 53 while leaving 853 alone,
/// and a TLS answer also proves the server's certificate for that name.
struct DoTResolver: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    init(id: String, name: String, host: String, port: UInt16 = 853) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }

    static let cloudflare = DoTResolver(
        id: "dot-cloudflare", name: "Cloudflare DoT", host: "one.one.one.one")
    static let google = DoTResolver(id: "dot-google", name: "Google DoT", host: "dns.google")

    static let builtIn: [DoTResolver] = [.cloudflare, .google]

    /// Accepts `tls://dns.google`, `dns.google` or `dns.google:853`.
    static func custom(_ text: String) -> DoTResolver? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("tls://") { trimmed.removeFirst("tls://".count) }
        guard !trimmed.isEmpty else { return nil }
        var host = trimmed
        var port: UInt16 = 853
        if let colon = trimmed.lastIndex(of: ":"),
            trimmed[trimmed.index(after: colon)...].allSatisfy(\.isNumber)
        {
            host = String(trimmed[..<colon])
            guard let parsed = UInt16(trimmed[trimmed.index(after: colon)...]), parsed > 0 else {
                return nil
            }
            port = parsed
        }
        guard !host.isEmpty, !host.hasPrefix("-") else { return nil }
        return DoTResolver(id: "dot:\(host):\(port)", name: host, host: host, port: port)
    }
}

/// Length-prefixed framing shared by every DoT message: two bytes of size, then
/// the DNS wire format. Kept apart from the socket so partial reads are testable.
enum DoTFraming {
    static func frame(_ message: Data) -> Data {
        var framed = Data([UInt8(message.count >> 8), UInt8(message.count & 0xFF)])
        framed.append(message)
        return framed
    }

    /// Removes and returns one complete frame, or nil while it is still arriving.
    static func takeFrame(from buffer: inout Data) -> Data? {
        guard buffer.count >= 2 else { return nil }
        let bytes = [UInt8](buffer.prefix(2))
        let length = Int(bytes[0]) << 8 | Int(bytes[1])
        guard buffer.count >= 2 + length else { return nil }
        let start = buffer.index(buffer.startIndex, offsetBy: 2)
        let end = buffer.index(start, offsetBy: length)
        let frame = Data(buffer[start..<end])
        buffer.removeSubrange(buffer.startIndex..<end)
        return frame
    }
}
import Foundation
import Network

/// Resolves over DNS-over-TLS. The answer is parsed with the same
/// `DNSMessage.parseResponse` the UDP path uses, so a comparison compares
/// answers and not encodings.
struct DoTDNSClient: Sendable {
    func lookup(
        host: String,
        type: DNSRecordType,
        resolver: DoTResolver,
        timeout: TimeInterval = 6
    ) async throws -> DNSLookupResult {
        let identifier = UInt16.random(in: UInt16.min...UInt16.max)
        let query = try DNSMessage.query(name: host, type: type, id: identifier)
        let started = Date()
        let data = try await Self.exchange(
            DoTFraming.frame(query), resolver: resolver, timeout: timeout)
        let response = try DNSMessage.parseResponse(data, expecting: identifier)
        if response.truncated { throw DNSClientError.truncated }
        return DNSLookupResult(
            host: host, resolver: resolver.name, records: response.records,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    private static func exchange(
        _ framed: Data, resolver: DoTResolver, timeout: TimeInterval
    ) async throws -> Data {
        // The exchange must outlive this closure: its own handlers hold it
        // weakly, so without a strong reference here it can be deallocated
        // before the handshake finishes and the continuation never resumes.
        var exchange: DoTExchange?
        let data = try await withCheckedThrowingContinuation { continuation in
            let session = DoTExchange(
                framed: framed, resolver: resolver, timeout: timeout
            ) { result in
                continuation.resume(with: result)
            }
            exchange = session
            session.start()
        }
        _ = exchange
        return data
    }
}

/// One TLS connection, one question and one answer. Everything that can end the
/// exchange — ready, failure, cancellation, timeout — funnels into `finish`, so
/// the continuation is resumed exactly once.
private final class DoTExchange: @unchecked Sendable {
    private let framed: Data
    private let resolver: DoTResolver
    private let completion: (Result<Data, Error>) -> Void
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ru.zheltukheen.LanFi.dot")
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false

    init(
        framed: Data, resolver: DoTResolver, timeout: TimeInterval, completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.framed = framed
        self.resolver = resolver
        self.completion = completion

        let tls = NWProtocolTLS.Options()
        // SNI must name the resolver even when the connection is made by
        // address, otherwise the certificate check has nothing to match.
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, resolver.host)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        connection = NWConnection(
            host: NWEndpoint.Host(resolver.host),
            port: NWEndpoint.Port(rawValue: resolver.port) ?? 853,
            using: parameters)

        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(DNSClientError.timeout))
        }
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                self.send()
            case .failed(let error):
                self.finish(.failure(DNSClientError.socket(error.localizedDescription)))
            case .cancelled:
                self.finish(.failure(DNSClientError.timeout))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func send() {
        connection.send(
            content: framed,
            completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.finish(.failure(DNSClientError.socket(error.localizedDescription)))
                } else {
                    self.receive()
                }
            })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_535) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.lock.lock()
            if let data { self.buffer.append(data) }
            let frame = DoTFraming.takeFrame(from: &self.buffer)
            self.lock.unlock()

            if let frame {
                self.finish(.success(frame))
                return
            }
            if let error {
                self.finish(.failure(DNSClientError.socket(error.localizedDescription)))
                return
            }
            if isComplete {
                self.finish(.failure(DNSClientError.invalidResponse("The DoT server closed the connection.")))
                return
            }
            self.receive()
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        // Breaks the connection <-> handler cycle so the exchange can deallocate.
        connection.stateUpdateHandler = nil
        connection.cancel()
        completion(result)
    }
}
