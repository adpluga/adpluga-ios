import Foundation

enum FeaturesResult {
    case notModified
    case updated(view: FeaturesView, etag: String?)
}

final class HttpTransport {
    private let publisherKey: String
    private let endpoint: URL
    private let session: URLSession
    private let consent: ConsentStore

    init(publisherKey: String, endpoint: URL, session: URLSession, consent: ConsentStore) {
        self.publisherKey = publisherKey
        self.endpoint = endpoint
        self.session = session
        self.consent = consent
    }

    func serve(slotId: String, format: String?, userHash: String?) async throws -> ServeResponse {
        let base = endpoint.appendingPathComponent("v1/serve")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw AdPlugaError.network(statusCode: -1, detail: "invalid endpoint")
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "slot", value: slotId)]
        if let fmt = format { items.append(URLQueryItem(name: "format", value: fmt)) }
        if let hash = userHash { items.append(URLQueryItem(name: "user_hash", value: hash)) }
        if !consent.state.isPersonalized {
            items.append(URLQueryItem(name: "non_personalized", value: "true"))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw AdPlugaError.network(statusCode: -1, detail: "invalid url")
        }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(Constants.networkServeTimeoutMs) / 1000.0)
        request.httpMethod = "GET"
        applyStandardHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await sendWithRetry(request: request)
        let dto = try adPlugaJsonDecoder.decode(ServeResponseDto.self, from: data)
        return dto.toModel()
    }

    func fetchFeatures(etag: String?) async throws -> FeaturesResult {
        let url = endpoint.appendingPathComponent("v1/features")
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(Constants.networkServeTimeoutMs) / 1000.0)
        request.httpMethod = "GET"
        applyStandardHeaders(&request)
        if let etag = etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await sendWithRetry(request: request, allowStatuses: [200, 304])
        guard let http = response as? HTTPURLResponse else {
            throw AdPlugaError.network(statusCode: -1, detail: "no response")
        }
        if http.statusCode == 304 {
            return .notModified
        }
        let dto = try adPlugaJsonDecoder.decode(FeaturesDto.self, from: data)
        let newEtag = http.value(forHTTPHeaderField: "ETag") ?? dto.etag
        return .updated(view: FeaturesView(flags: dto.flags ?? [:]), etag: newEtag)
    }

    func postTrack(kind: String, payload: [String: Any]) async {
        var full = payload
        full["kind"] = kind
        let url = endpoint.appendingPathComponent("v1/track")
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(Constants.networkTrackTimeoutMs) / 1000.0)
        request.httpMethod = "POST"
        applyStandardHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = try JSONSerialization.data(withJSONObject: full, options: [])
            request.httpBody = body
            _ = try await sendWithRetry(request: request)
        } catch {
            AdPlugaLogger.debug("track post failed", error: error)
        }
    }

    func beacon(url urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(Constants.networkTrackTimeoutMs) / 1000.0)
        request.httpMethod = "GET"
        request.setValue(Constants.sdkPlatform, forHTTPHeaderField: Constants.platformHeader)
        request.setValue(Constants.sdkVersion, forHTTPHeaderField: Constants.versionHeader)
        do {
            _ = try await sendWithRetry(request: request)
        } catch {
            AdPlugaLogger.debug("beacon failed", error: error)
        }
    }

    func postTelemetry(body: Data) async throws {
        let url = endpoint.appendingPathComponent("v1/sdk/telemetry")
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(Constants.networkTrackTimeoutMs) / 1000.0)
        request.httpMethod = "POST"
        applyStandardHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await sendWithRetry(request: request)
    }

    private func applyStandardHeaders(_ request: inout URLRequest) {
        request.setValue(publisherKey, forHTTPHeaderField: Constants.keyHeader)
        request.setValue(Constants.sdkPlatform, forHTTPHeaderField: Constants.platformHeader)
        request.setValue(Constants.sdkVersion, forHTTPHeaderField: Constants.versionHeader)
    }

    private func sendWithRetry(request: URLRequest, allowStatuses: Set<Int> = []) async throws -> (Data, URLResponse) {
        let maxAttempts = Constants.networkRetryMaxAttempts
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AdPlugaError.network(statusCode: -1, detail: "no response")
                }
                if http.statusCode == 426 {
                    let min = http.value(forHTTPHeaderField: Constants.upgradeHeader)
                    throw AdPlugaError.upgradeRequired(minVersion: min)
                }
                if allowStatuses.contains(http.statusCode) {
                    return (data, response)
                }
                if shouldRetry(status: http.statusCode) && attempt < maxAttempts {
                    try await sleepBackoff(attempt: attempt)
                    attempt += 1
                    continue
                }
                if !(200..<300).contains(http.statusCode) {
                    let detail = String(data: data, encoding: .utf8)
                    throw AdPlugaError.network(statusCode: http.statusCode, detail: detail)
                }
                return (data, response)
            } catch let err as AdPlugaError {
                if case .upgradeRequired = err { throw err }
                if attempt < maxAttempts {
                    try? await sleepBackoff(attempt: attempt)
                    attempt += 1
                    continue
                }
                throw err
            } catch {
                if attempt < maxAttempts {
                    try? await sleepBackoff(attempt: attempt)
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    private func shouldRetry(status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    private func sleepBackoff(attempt: Int) async throws {
        let base = Constants.networkRetryBaseBackoffMs
        let exp = base << attempt
        let jitter = Int.random(in: 0..<base)
        let totalMs = exp + jitter
        try await Task.sleep(nanoseconds: UInt64(totalMs) * 1_000_000)
    }
}
