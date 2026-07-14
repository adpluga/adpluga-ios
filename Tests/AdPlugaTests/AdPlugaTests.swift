import XCTest
@testable import AdPluga

final class AdPlugaTests: XCTestCase {
    private let publisherKey = "pk_test_abcdefghij"
    private var session: URLSession!
    private let endpoint = "http://mock.local"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        AdPluga.maybeInstance?.destroy()
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testInvalidKeyThrows() {
        XCTAssertThrowsError(try AdPluga.initialize(publisherKey: "bad-key")) { error in
            guard case AdPlugaError.invalidKey = error else {
                XCTFail("expected invalidKey, got \(error)")
                return
            }
        }
    }

    func testServeReturnsParsedResponse() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Fixtures.serveResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        let pluga = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        let response = await pluga.serve(slotId: "slot_1")
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.ad.id, "ad_1")
        XCTAssertEqual(response?.ad.kind, .image)
        XCTAssertEqual(response?.ad.source, .house)

        let serveRequests = MockURLProtocol.recorded().filter { $0.path == "/v1/serve" }
        XCTAssertEqual(serveRequests.count, 1)
        XCTAssertEqual(serveRequests.first?.header(Constants.keyHeader), publisherKey)
        XCTAssertEqual(serveRequests.first?.header(Constants.platformHeader), "ios")
    }

    func testServeShortCircuitsAfter426() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                let http = HTTPURLResponse(
                    url: url,
                    statusCode: 426,
                    httpVersion: "HTTP/1.1",
                    headerFields: [Constants.upgradeHeader: "0.9.0"]
                )!
                return (http, Data())
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        let pluga = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        let first = await pluga.serve(slotId: "slot_1")
        let second = await pluga.serve(slotId: "slot_1")
        XCTAssertNil(first)
        XCTAssertNil(second)

        let serveCount = MockURLProtocol.recorded().filter { $0.path == "/v1/serve" }.count
        XCTAssertEqual(serveCount, 1)
    }

    func testConsentFlipAddsNonPersonalized() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Fixtures.serveResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        let pluga = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        _ = await pluga.serve(slotId: "slot_1")
        pluga.setConsent(ConsentState(gdpr: true, adPersonalization: false))
        _ = await pluga.serve(slotId: "slot_1")

        let servePaths = MockURLProtocol.recorded()
            .filter { $0.path == "/v1/serve" }
            .map { $0.query }
        XCTAssertEqual(servePaths.count, 2)
        XCTAssertFalse(servePaths[0].contains("non_personalized"), "first query: \(servePaths[0])")
        XCTAssertTrue(servePaths[1].contains("non_personalized=true"), "second query: \(servePaths[1])")
    }

    func testEnsureFeaturesReflectsRemoteFlag() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/features" {
                return MockURLProtocol.jsonResponse(
                    url: url,
                    body: "{\"flags\":{\"sdk_telemetry\":true}}",
                    headers: ["ETag": "v1"]
                )
            }
            return MockURLProtocol.jsonResponse(url: url, body: Fixtures.serveResponse)
        }

        let pluga = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        await pluga.ensureFeatures()
        let view = await pluga.featuresView
        XCTAssertTrue(view.flag("sdk_telemetry"))
    }

    #if canImport(UIKit)
    func testInterstitialAcceptsHtmlFormat() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Fixtures.htmlServeResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        _ = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        let interstitial = try await InterstitialAd.load(slotId: "slot_html")
        XCTAssertEqual(interstitial.ad.kind, .html)
        XCTAssertNotNil(interstitial.ad.html)
    }

    func testInterstitialAcceptsVideoFormatWithQuartilePings() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Fixtures.videoServeResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        _ = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        let interstitial = try await InterstitialAd.load(slotId: "slot_video")
        XCTAssertEqual(interstitial.ad.kind, .video)
        XCTAssertEqual(interstitial.ad.assetUrl, "https://cdn.adpluga.example/creatives/ad.mp4")
        XCTAssertEqual(interstitial.ad.durationMs, 15000)
    }

    func testRewardedAcceptsVideoRewardedFormatWithSkippableWindow() async throws {
        MockURLProtocol.setHandler { request, _ in
            let url = request.url!
            if url.path == "/v1/serve" {
                return MockURLProtocol.jsonResponse(url: url, body: Fixtures.videoRewardedServeResponse)
            }
            return MockURLProtocol.jsonResponse(url: url, body: "{\"flags\":{}}")
        }

        _ = try AdPluga.initialize(
            publisherKey: publisherKey,
            endpoint: endpoint,
            sessionOverride: session
        )
        let rewarded = try await RewardedAd.load(slotId: "slot_rw")
        XCTAssertEqual(rewarded.ad.kind, .videoRewarded)
        XCTAssertEqual(rewarded.ad.durationMs, 30000)
        XCTAssertEqual(rewarded.ad.skippableAfterMs, 5000)
        XCTAssertEqual(rewarded.ad.rewardAmount, 10)
        XCTAssertEqual(rewarded.ad.rewardCurrency, "COIN")
    }
    #endif
}

private enum Fixtures {
    static let serveResponse = """
    {
      "slot_id": "slot_1",
      "ad": {
        "id": "ad_1",
        "kind": "image",
        "source": "house",
        "asset_url": "https://cdn.example.com/img.png",
        "width": 320,
        "height": 100,
        "reward_currency": "COIN"
      },
      "impression_token": "imp_tok",
      "click_token": "clk_tok",
      "impression_url": "https://track.example.com/imp?t=1",
      "click_url": "https://track.example.com/clk?t=1",
      "ttl_ms": 60000
    }
    """

    static let htmlServeResponse = """
    {
      "slot_id": "slot_html",
      "ad": {
        "id": "ad_html_1",
        "kind": "html",
        "source": "house",
        "html": "<html><body style='margin:0'><a href='https://landing.example/x'>promo</a></body></html>",
        "width": 320,
        "height": 250,
        "reward_currency": "COIN"
      },
      "impression_token": "imp_tok",
      "click_token": "clk_tok",
      "impression_url": "https://track.example.com/imp?t=1",
      "click_url": "https://track.example.com/clk?t=1",
      "ttl_ms": 60000
    }
    """

    static let videoServeResponse = """
    {
      "slot_id": "slot_video",
      "ad": {
        "id": "ad_video_1",
        "kind": "video",
        "source": "house",
        "asset_url": "https://cdn.adpluga.example/creatives/ad.mp4",
        "width": 640,
        "height": 360,
        "duration_ms": 15000,
        "reward_currency": "COIN"
      },
      "impression_token": "imp_tok",
      "click_token": "clk_tok",
      "impression_url": "https://track.example.com/imp?t=vid",
      "click_url": "https://track.example.com/clk?t=vid",
      "ttl_ms": 60000,
      "quartile_pings": {
        "start": "https://edge.adpluga.example/vast/start",
        "first_quartile": "https://edge.adpluga.example/vast/q1",
        "midpoint": "https://edge.adpluga.example/vast/q2",
        "third_quartile": "https://edge.adpluga.example/vast/q3",
        "complete": "https://edge.adpluga.example/vast/complete"
      }
    }
    """

    static let videoRewardedServeResponse = """
    {
      "slot_id": "slot_rw",
      "ad": {
        "id": "ad_video_rw_1",
        "kind": "video_rewarded",
        "source": "house",
        "asset_url": "https://cdn.adpluga.example/creatives/rw.mp4",
        "width": 640,
        "height": 360,
        "duration_ms": 30000,
        "skippable_after_ms": 5000,
        "reward_amount": 10,
        "reward_currency": "COIN"
      },
      "impression_token": "imp_tok",
      "click_token": "clk_tok",
      "impression_url": "https://track.example.com/imp?t=rw",
      "click_url": "https://track.example.com/clk?t=rw",
      "ttl_ms": 60000
    }
    """
}
