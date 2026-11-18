import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class EventJsonTests: XCTestCase {

    private let sample = """
    {
      "timestamp": "2024-05-01T04:30:00",
      "city": "上海市",
      "est_lat": "31.2304",
      "est_lon": "121.4737",
      "reason": "sentry_aware_object_detection",
      "camera": "0"
    }
    """

    func testParsesKnownFields() {
        let info = TeslaEventInfo.parse(sample)
        XCTAssertEqual("2024-05-01T04:30:00", info.timestampIso)
        XCTAssertEqual("上海市", info.city)
        XCTAssertEqual(31.2304, info.estLat ?? 0.0, accuracy: 0.00001)
        XCTAssertEqual(121.4737, info.estLon ?? 0.0, accuracy: 0.00001)
        XCTAssertEqual("哨兵事件", info.reasonLabel())
    }

    func testBuildsReferenceLine() throws {
        let line = try XCTUnwrap(TeslaEventInfo.parse(sample).referenceLine())
        XCTAssertTrue(line.contains("上海市"))
        XCTAssertTrue(line.contains("31.23040"))
    }

    func testHandlesMissingFields() {
        let info = TeslaEventInfo.parse("{}")
        XCTAssertNil(info.timestampIso)
        XCTAssertNil(info.city)
        XCTAssertNil(info.estLat)
        XCTAssertNil(info.referenceLine())
    }

    func testHandlesNumericCoordinates() {
        let info = TeslaEventInfo.parse(#"{"est_lat": -33.86, "est_lon": 151.21}"#)
        XCTAssertEqual(-33.86, info.estLat ?? 0.0, accuracy: 0.00001)
        XCTAssertEqual(151.21, info.estLon ?? 0.0, accuracy: 0.00001)
    }

    func testMapsUserInteractionReason() {
        let info = TeslaEventInfo.parse(#"{"reason": "user_interaction_honk"}"#)
        XCTAssertEqual("鸣笛保存", info.reasonLabel())
    }
}
