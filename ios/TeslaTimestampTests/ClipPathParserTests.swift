import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class ClipPathParserTests: XCTestCase {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let fiveAmUTC: Int64 = 1_714_537_800_000 // 2024-05-01T04:30:00Z

    func testParsesRecentClipsFile() throws {
        let identity = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4", timeZone: shanghai)
        )
        XCTAssertEqual(.recent, identity.category)
        XCTAssertEqual("front", identity.camera)
        XCTAssertEqual(fiveAmUTC, identity.clipStartMillis)
        XCTAssertTrue(identity.timestampFromName)
    }

    func testParsesSavedClipsDirectoryLayout() throws {
        let identity = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/back.mp4", timeZone: shanghai)
        )
        XCTAssertEqual(.saved, identity.category)
        XCTAssertEqual("back", identity.camera)
        XCTAssertEqual(fiveAmUTC, identity.clipStartMillis)
    }

    func testParsesSentryClipsDirectoryLayout() throws {
        let identity = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/SentryClips/2024-05-01_12-30-00/left_repeater.mp4", timeZone: shanghai)
        )
        XCTAssertEqual(.sentry, identity.category)
        XCTAssertEqual("left_repeater", identity.camera)
    }

    func testIgnoresEventJson() {
        XCTAssertNil(ClipPathParser.parse("TeslaCam/SentryClips/2024-05-01_12-30-00/event.json", timeZone: shanghai))
    }

    func testIgnoresFilesWithoutTimestamp() {
        XCTAssertNil(ClipPathParser.parse("Download/movie.mp4", timeZone: shanghai))
    }

    func testSameClipGroupForDifferentCameras() throws {
        let front = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/front.mp4", timeZone: shanghai)
        )
        let back = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/SavedClips/2024-05-01_12-30-00/back.mp4", timeZone: shanghai)
        )
        XCTAssertEqual(front.groupId, back.groupId)
        XCTAssertNotEqual(front.camera, back.camera)
    }

    func testDifferentMinutesAreDifferentGroups() throws {
        let first = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-30-00-front.mp4", timeZone: shanghai)
        )
        let second = try XCTUnwrap(
            ClipPathParser.parse("TeslaCam/RecentClips/2024-05-01_12-31-00-front.mp4", timeZone: shanghai)
        )
        XCTAssertNotEqual(first.groupId, second.groupId)
    }

    func testHandlesWindowsSeparatorsAndLeadingSlash() throws {
        let identity = try XCTUnwrap(
            ClipPathParser.parse(#"\TeslaCam\RecentClips\2024-05-01_12-30-00-back.mp4"#, timeZone: shanghai)
        )
        XCTAssertEqual("back", identity.camera)
    }

    func testUnknownCategoryWhenNoTeslaCamFolder() throws {
        let identity = try XCTUnwrap(
            ClipPathParser.parse("2024-05-01_12-30-00-front.mp4", timeZone: shanghai)
        )
        XCTAssertEqual(.recent, identity.category)
    }
}
