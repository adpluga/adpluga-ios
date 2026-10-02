#if canImport(UIKit)
import UIKit
import XCTest
@testable import AdPluga

// Regression: inside another SDK's waterfall the view drew the unpaid house
// creative, taking the slot from the networks below it.
@MainActor
final class MediatedViewTests: XCTestCase, AdPlugaViewDelegate {
    private var errors: [Error] = []
    private var loaded = false

    override func setUp() async throws {
        MockURLProtocol.reset()
        AdPluga.maybeInstance?.destroy()
    }

    override func tearDown() async throws {
        AdPluga.maybeInstance?.destroy()
        MockURLProtocol.reset()
    }

    func testMediatedViewReportsTheHouseFallbackAsNoFill() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Self.houseResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }
        try AdPluga.initialize(publisherKey: "pk_test_abcdefghij", endpoint: "http://mock.local", sessionOverride: MockURLProtocol.makeSession())

        let view = AdPlugaView(frame: CGRect(x: 0, y: 0, width: 320, height: 50))
        view.mediated = true
        view.delegate = self
        view.load(slotId: "slot_1")

        let deadline = Date().addingTimeInterval(5)
        while errors.isEmpty && !loaded && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(loaded)
        XCTAssertEqual(errors.first as? AdPlugaError, .noFill)
    }

    nonisolated static let houseResponse = """
    {"ad":{"id":"h1","type":"image","asset_url":"https://cdn.example/h.png","width":320,"height":50},
     "click_url":"https://edge.example/c","track_token":"t","source":"house","refresh_after_seconds":30}
    """

    nonisolated func adPlugaView(_ view: AdPlugaView, didLoad ad: Ad) {
        MainActor.assumeIsolated { loaded = true }
    }

    nonisolated func adPlugaView(_ view: AdPlugaView, didFailWith error: Error) {
        MainActor.assumeIsolated { errors.append(error) }
    }
}
#endif
