import XCTest
@testable import AdPluga

final class MediationTrackersTests: XCTestCase {
    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    private func transport() -> HttpTransport {
        HttpTransport(
            publisherKey: "pk_test_abcdefghij",
            endpoint: URL(string: "https://edge.adpluga.test/")!,
            session: MockURLProtocol.makeSession(),
            consent: ConsentStore(initial: ConsentState()),
            userAgent: ua
        )
    }

    func testServeSendsTheDeviceUserAgent() throws {
        let request = try transport().makeServeRequest(slotId: "slot_1", format: nil, userHash: nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-User-Agent"), ua)
    }

    func testThirdPartyPixelGetsTheDeviceUAAndNoSDKHeaders() throws {
        let request = try XCTUnwrap(transport().makeBeaconRequest(url: "https://ssp.example/imp?p=1"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), ua)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Adpluga-Sdk-Platform"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-AdPluga-Key"))
    }

    func testFirstPartyBeaconKeepsTheSDKHeaders() throws {
        let request = try XCTUnwrap(transport().makeBeaconRequest(url: "/v1/imp?t=x"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Adpluga-Sdk-Platform"))
    }

    func testTrackersAreDecodedAndDefaultToEmpty() throws {
        let json = #"{"ad":{"id":"m","type":"video","impression_trackers":["https://ssp/imp"],"click_trackers":["https://ssp/clk"]},"track_token":"","source":"mediation"}"#
        let model = try adPlugaJsonDecoder.decode(ServeResponseDto.self, from: Data(json.utf8)).toModel()
        XCTAssertEqual(model.ad.impressionTrackers, ["https://ssp/imp"])
        XCTAssertEqual(model.ad.clickTrackers, ["https://ssp/clk"])

        let bare = #"{"ad":{"id":"h","type":"image"},"track_token":"t","source":"house"}"#
        let plain = try adPlugaJsonDecoder.decode(ServeResponseDto.self, from: Data(bare.utf8)).toModel()
        XCTAssertTrue(plain.ad.impressionTrackers.isEmpty)
        XCTAssertTrue(plain.ad.clickTrackers.isEmpty)
    }

    func testDeviceUserAgentFollowsWebKitFormat() {
        let phone = DeviceUserAgent.make(machine: "iPhone15,2", version: OperatingSystemVersion(majorVersion: 17, minorVersion: 4, patchVersion: 0))
        XCTAssertEqual(phone, ua)
        let pad = DeviceUserAgent.make(machine: "iPad13,1", version: OperatingSystemVersion(majorVersion: 16, minorVersion: 6, patchVersion: 1))
        XCTAssertTrue(pad.hasPrefix("Mozilla/5.0 (iPad; CPU OS 16_6_1 like Mac OS X)"))
    }
}
