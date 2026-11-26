import Foundation
import Network

/// A DNS-over-QUIC resolver (RFC 9250). DoQ is the fourth transport in the
/// comparison because UDP/53 and TCP/853 can both be blocked by a network that
/// still allows QUIC on 853, and a QUIC handshake also proves the server's
/// certificate.
struct DoQResolver: Identifiable, Equatable, Hashable, Sendable {
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

    static let adGuard = DoQResolver(
        id: "doq-adguard", name: "AdGuard DoQ", host: "dns.adguard-dns.com")
    static let google = DoQResolver(id: "doq-google", name: "Google DoQ", host: "dns.google")

    static let builtIn: [DoQResolver] = [.adGuard, .google]

    /// Accepts `quic://dns.adguard-dns.com`, a bare `host` or `host:853`. QUIC
    /// has no separate scheme permission, so only the host and port are kept.
    static func custom(_ text: String) -> DoQResolver? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("quic://") { trimmed.removeFirst("quic://".count) }
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
        return DoQResolver(id: "doq:\(host):\(port)", name: host, host: host, port: port)
    }
}

/// Resolves over DNS-over-QUIC. Each query opens one QUIC connection with the
/// `doq` ALPN, one bidirectional stream and one length-prefixed message; the
/// answer is parsed with the same `DNSMessage.parseResponse` the UDP path uses,
/// so a comparison still compares answers rather than encodings.
struct DoQDNSClient: Sendable {
    func lookup(
        host: String,
        type: DNSRecordType,
        resolver: DoQResolver,
        timeout: TimeInterval = 6
    ) async throws -> DNSLookupResult {
        let identifier = UInt16.random(in: UInt16.min...UInt16.max)
        let query = try DNSMessage.query(name: host, type: type, id: identifier)
        let started = Date()
        // RFC 9250 §4.2 keeps the same two-octet length prefix DoT uses, so the
        // framing is shared instead of re-implemented.
        let data = try await Self.exchange(
            DoTFraming.frame(query), resolver: resolver, timeout: timeout)
        let response = try DNSMessage.parseResponse(data, expecting: identifier)
        if response.truncated { throw DNSClientError.truncated }
        return DNSLookupResult(
            host: host, resolver: resolver.name, records: response.records,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    private static func exchange(
        _ framed: Data, resolver: DoQResolver, timeout: TimeInterval
    ) async throws -> Data {
        // The exchange must outlive this closure: its handlers hold it weakly,
        // so without a strong reference here it can be deallocated before the
        // handshake finishes and the continuation never resumes.
        var exchange: DoQExchange?
        let data = try await withCheckedThrowingContinuation { continuation in
            let session = DoQExchange(
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

/// One QUIC connection, one question and one answer. Everything that can end
/// the exchange — ready, failure, cancellation, timeout — funnels into
/// `finish`, so the continuation is resumed exactly once.
private final class DoQExchange: @unchecked Sendable {
    private let framed: Data
    private let completion: (Result<Data, Error>) -> Void
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ru.zheltukheen.LanFi.doq")
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false

    init(
        framed: Data, resolver: DoQResolver, timeout: TimeInterval,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.framed = framed
        self.completion = completion

        let quic = NWProtocolQUIC.Options(alpn: ["doq"])
        // SNI must name the resolver even when the connection is made by
        // address, otherwise the certificate check has nothing to match.
        sec_protocol_options_set_tls_server_name(quic.securityProtocolOptions, resolver.host)
        let parameters = NWParameters(quic: quic)
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
                self.finish(
                    .failure(
                        DNSClientError.invalidResponse(
                            "The DoQ server closed the stream.")))
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
