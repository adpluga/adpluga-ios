import XCTest
@testable import AdPluga

final class MediationSlotTests: XCTestCase {
    func testWaterfallParameterIsParsedInBothShapes() {
        let cases: [(String?, MediationSlot?)] = [
            ("slot_abc", MediationSlot(slotId: "slot_abc")),
            ("  slot_abc  ", MediationSlot(slotId: "slot_abc")),
            (#"{"publisher_key":"pk_live_abcdefgh","slot_id":"s1"}"#, MediationSlot(slotId: "s1", publisherKey: "pk_live_abcdefgh")),
            (#"{"slot_id":"s1","extra":true}"#, MediationSlot(slotId: "s1")),
            (#"{"publisher_key":"pk_live_abcdefgh"}"#, nil),
            (#"{"slot_id":""}"#, nil),
            ("{not json", nil),
            ("", nil),
            (nil, nil),
        ]
        for (raw, want) in cases {
            XCTAssertEqual(MediationSlot.parse(raw), want, "raw=\(raw ?? "nil")")
        }
    }

    func testFallbackKeyOnlyFillsAMissingKey() {
        XCTAssertEqual(MediationSlot(slotId: "s").keyed(by: " pk_test_x "), MediationSlot(slotId: "s", publisherKey: "pk_test_x"))
        XCTAssertEqual(MediationSlot(slotId: "s", publisherKey: "pk_a").keyed(by: "pk_b").publisherKey, "pk_a")
        XCTAssertNil(MediationSlot(slotId: "s").keyed(by: "  ").publisherKey)
    }

    // Regression: platform_mediation fell back to house, so an adapter threw
    // away paid demand as if it were the unpaid fallback.
    func testPlatformMediationIsPaidDemand() {
        XCTAssertEqual(AdSource.fromWire("platform_mediation"), .platformMediation)
        XCTAssertEqual(AdSource.fromWire("nonsense"), .house)
    }
}
