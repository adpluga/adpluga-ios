import XCTest
@testable import AdPluga

final class ConsentSignalsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "adpluga.tests.tcf.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func serveRequest(_ state: ConsentState) throws -> URLRequest {
        let transport = HttpTransport(
            publisherKey: "pk_test_abcdefghij",
            endpoint: URL(string: "http://mock.local")!,
            session: MockURLProtocol.makeSession(),
            consent: ConsentStore(initial: state),
            tcf: UserDefaultsTCFStorage(defaults: defaults)
        )
        return try transport.makeServeRequest(slotId: "slot_1", format: nil, userHash: nil)
    }

    private func queryValue(_ request: URLRequest, _ name: String) -> String? {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first { $0.name == name }?.value
    }

    private func hasQueryItem(_ request: URLRequest, _ name: String) -> Bool {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains { $0.name == name } ?? false
    }

    func testExplicitConsentWinsOverStoredTCF() throws {
        defaults.set(0, forKey: "IABTCF_gdprApplies")
        defaults.set("STORED_TC", forKey: "IABTCF_TCString")

        let request = try serveRequest(ConsentState(gdpr: true, tcfString: "EXPLICIT_TC"))

        XCTAssertEqual(queryValue(request, "gdpr"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Consent-String"), "EXPLICIT_TC")
    }

    func testStoredTCFIsReadWhenTheAppStatesNothing() throws {
        defaults.set(0, forKey: "IABTCF_gdprApplies")
        defaults.set("STORED_TC", forKey: "IABTCF_TCString")

        let request = try serveRequest(ConsentState())

        XCTAssertEqual(queryValue(request, "gdpr"), "0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Consent-String"), "STORED_TC")
    }

    func testNothingKnownOmitsGdprAndHeader() throws {
        let request = try serveRequest(ConsentState())

        XCTAssertFalse(hasQueryItem(request, "gdpr"), "query: \(request.url!.query ?? "")")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Consent-String"))
    }

    func testBlankStringsAreIgnored() throws {
        let explicitBlank = try serveRequest(ConsentState(tcfString: "   "))
        XCTAssertNil(explicitBlank.value(forHTTPHeaderField: "X-Consent-String"))

        defaults.set("", forKey: "IABTCF_TCString")
        let bothBlank = try serveRequest(ConsentState(tcfString: ""))
        XCTAssertNil(bothBlank.value(forHTTPHeaderField: "X-Consent-String"))

        defaults.set("STORED_TC", forKey: "IABTCF_TCString")
        let fallsThrough = try serveRequest(ConsentState(tcfString: " "))
        XCTAssertEqual(fallsThrough.value(forHTTPHeaderField: "X-Consent-String"), "STORED_TC")
    }

    func testStringTypedGdprAppliesIsUnderstood() throws {
        defaults.set("1", forKey: "IABTCF_gdprApplies")
        XCTAssertEqual(queryValue(try serveRequest(ConsentState()), "gdpr"), "1")

        defaults.set("0", forKey: "IABTCF_gdprApplies")
        XCTAssertEqual(queryValue(try serveRequest(ConsentState()), "gdpr"), "0")
    }

    func testUnrecognisedGdprAppliesIsTreatedAsUnknown() throws {
        defaults.set("yes", forKey: "IABTCF_gdprApplies")
        XCTAssertFalse(hasQueryItem(try serveRequest(ConsentState()), "gdpr"))
    }
}
