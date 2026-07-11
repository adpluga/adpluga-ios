import XCTest
@testable import AdPluga

final class TelemetryBatcherTests: XCTestCase {
    private var session: URLSession!
    private let publisherKey = "pk_test_abcdefghij"
    private let endpoint = URL(string: "http://mock.local")!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testReservoirSamplingKeepsFootprintBounded() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            return MockURLProtocol.emptyResponse(url: url)
        }

        let consent = ConsentStore(initial: .default)
        let transport = HttpTransport(
            publisherKey: publisherKey,
            endpoint: endpoint,
            session: session,
            consent: consent
        )
        let batcher = TelemetryBatcher(transport: transport, enabled: true)
        for latency in 0..<1000 {
            await batcher.record(type: .serveRequest, latencyMs: latency)
        }
        try await batcher.flush()

        let telemetryRequests = MockURLProtocol.recorded().filter { $0.path == "/v1/sdk/telemetry" }
        XCTAssertEqual(telemetryRequests.count, 1)
        let bodyString = String(data: telemetryRequests[0].body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("\"count\":1000"), "unexpected body: \(bodyString)")
        XCTAssertTrue(bodyString.contains("\"p50\""))
        XCTAssertTrue(bodyString.contains("\"p95\""))
        XCTAssertTrue(bodyString.contains("\"p99\""))
    }

    func testSetEnabledFalseSkipsNetworkFlush() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            return MockURLProtocol.emptyResponse(url: url)
        }

        let consent = ConsentStore(initial: .default)
        let transport = HttpTransport(
            publisherKey: publisherKey,
            endpoint: endpoint,
            session: session,
            consent: consent
        )
        let batcher = TelemetryBatcher(transport: transport, enabled: false)
        for _ in 0..<10 {
            await batcher.record(type: .serveRequest, latencyMs: 42)
        }
        try await batcher.flush()

        let telemetryRequests = MockURLProtocol.recorded().filter { $0.path == "/v1/sdk/telemetry" }
        XCTAssertEqual(telemetryRequests.count, 0)
    }
}
