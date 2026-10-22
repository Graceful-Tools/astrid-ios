import Foundation

/// A `URLProtocol` that answers instead of the server and records what was sent (AITD-535).
///
/// Hand `StubURLProtocol.session()` to a client that takes a `URLSession`
/// (`AstridAPIClient(session:)`); set `respond` to choose the answer, and read `requests` for what
/// went out. The state is process-wide, so call `reset()` in `setUp` — test cases run serially.
final class StubURLProtocol: URLProtocol {
    /// What the stub answers: a status and body, or an error to fail the transport with.
    enum Answer {
        case http(status: Int, body: Data, headers: [String: String] = [:])
        case failure(Error)

        static func json(_ text: String, status: Int = 200) -> Answer {
            .http(status: status, body: Data(text.utf8), headers: ["Content-Type": "application/json"])
        }
    }

    /// A request as sent, with its body read back out of the stream URLSession moves it to.
    struct Recorded {
        let request: URLRequest
        let body: Data?

        var method: String? { request.httpMethod }
        var path: String? { request.url?.path }
        var query: [String: String] {
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
        }
        var jsonBody: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _respond: (URLRequest) -> Answer = { _ in .json("{}") }
    nonisolated(unsafe) private static var _requests: [Recorded] = []

    static var respond: (URLRequest) -> Answer {
        get { lock.withLock { _respond } }
        set { lock.withLock { _respond = newValue } }
    }

    static var requests: [Recorded] { lock.withLock { _requests } }

    static func reset() {
        lock.withLock {
            _respond = { _ in .json("{}") }
            _requests = []
        }
    }

    /// An ephemeral session — no cookie jar, no cache — that sends only to this stub.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = Recorded(request: request, body: request.httpBody ?? Self.read(request.httpBodyStream))
        let answer = Self.lock.withLock { () -> Answer in
            Self._requests.append(recorded)
            return Self._respond(request)
        }
        switch answer {
        case let .http(status, body, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
