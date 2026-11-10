import Foundation
import Security

enum TLSCertificateError: Error, Equatable, LocalizedError {
    case noCertificates
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noCertificates:
            return "The server did not present a certificate chain."
        case .timedOut:
            return "The TLS handshake did not finish in time."
        }
    }
}

protocol TLSCertificateInspecting: Sendable {
    func inspect(host: String, port: UInt16, timeout: TimeInterval) async throws
        -> TLSCertificateReport
}

struct URLSessionTLSCertificateInspector: TLSCertificateInspecting {
    func inspect(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 10
    ) async throws -> TLSCertificateReport {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = Int(port)
        guard let url = components.url else { throw TLSCertificateError.noCertificates }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<TLSCertificateReport, Error>) in
            let delegate = TLSSessionDelegate(
                host: host, port: port, continuation: continuation)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            let session = URLSession(
                configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            let task = session.dataTask(with: url) { [weak delegate] _, _, error in
                if let error {
                    delegate?.finish(.failure(error))
                }
            }
            delegate.task = task
            task.resume()

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1) {
                [weak delegate] in
                delegate?.finish(.failure(TLSCertificateError.timedOut))
            }
        }
    }
}

private final class TLSSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let continuation: CheckedContinuation<TLSCertificateReport, Error>
    private let once = OnceFlag()
    weak var session: URLSession?
    var task: URLSessionDataTask?

    init(
        host: String,
        port: UInt16,
        continuation: CheckedContinuation<TLSCertificateReport, Error>
    ) {
        self.host = host
        self.port = port
        self.continuation = continuation
    }

    func finish(_ result: Result<TLSCertificateReport, Error>) {
        guard once.claim() else { return }
        task?.cancel()
        session?.invalidateAndCancel()
        continuation.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        guard !chain.isEmpty else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            finish(.failure(TLSCertificateError.noCertificates))
            return
        }

        let certificates = chain.map { certificate(from: $0) }
        let trusted = trustResult(trust)
        completionHandler(.cancelAuthenticationChallenge, nil)
        finish(
            .success(
                TLSCertificateReport(
                    host: host,
                    port: port,
                    certificates: certificates,
                    trusted: trusted,
                    checkedAt: Date()
                )))
    }

    private func trustResult(_ trust: SecTrust) -> Bool {
        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, policy)
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    private func certificate(from certificate: SecCertificate) -> TLSCertificate {
        let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
        let keys =
            [
                kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotBefore,
                kSecOIDX509V1ValidityNotAfter,
            ] as CFArray
        let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any]
        return TLSCertificate(
            subject: subject,
            issuer: issuerName(from: values?[kSecOIDX509V1IssuerName as String]),
            notBefore: date(from: values?[kSecOIDX509V1ValidityNotBefore as String]),
            notAfter: date(from: values?[kSecOIDX509V1ValidityNotAfter as String])
        )
    }

    private func issuerName(from value: Any?) -> String {
        guard
            let dictionary = value as? [String: Any],
            let items = dictionary["value"] as? [[String: Any]]
        else { return "Unknown" }
        if let commonName = items.first(where: { $0["label"] as? String == "2.5.4.3" })?["value"]
            as? String
        {
            return commonName
        }
        let strings = items.compactMap { $0["value"] as? String }
        return strings.isEmpty ? "Unknown" : strings.joined(separator: ", ")
    }

    private func date(from value: Any?) -> Date? {
        guard
            let dictionary = value as? [String: Any],
            let number = dictionary["value"] as? NSNumber
        else { return nil }
        return Date(timeIntervalSinceReferenceDate: number.doubleValue)
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
