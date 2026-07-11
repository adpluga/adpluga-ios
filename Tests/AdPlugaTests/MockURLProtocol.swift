import Foundation

final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest, Data) -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _recorded: [RecordedRequest] = []

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        _handler = handler
        lock.unlock()
    }

    static func recorded() -> [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _recorded = []
        lock.unlock()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.lock.lock()
        let handler = Self._handler
        Self._recorded.append(RecordedRequest(request: request, body: body))
        Self.lock.unlock()

        let fallbackURL = request.url ?? URL(string: "http://localhost")!
        let fallback = HTTPURLResponse(url: fallbackURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
        let (response, data) = handler?(request, body) ?? (fallback, Data())
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

struct RecordedRequest {
    let request: URLRequest
    let body: Data
    var url: URL? { request.url }
    var path: String { request.url?.path ?? "" }
    var query: String { request.url?.query ?? "" }
    var method: String { request.httpMethod ?? "" }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
}

extension MockURLProtocol {
    static func jsonResponse(url: URL, statusCode: Int = 200, body: String = "{}", headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        var merged = headers
        if merged["Content-Type"] == nil { merged["Content-Type"] = "application/json" }
        let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: merged)!
        return (http, body.data(using: .utf8) ?? Data())
    }

    static func emptyResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (http, Data())
    }
}
