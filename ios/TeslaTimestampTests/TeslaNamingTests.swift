import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class TeslaNamingTests: XCTestCase {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    // 2024-05-01T04:30:00Z == 2024-05-01 12:30:00+08:00 -> 1_714_537_800_000 ms
    private let expectedEpochMs: Int64 = 1_714_537_800_000

    func testParsesRecentClipTimestamp() {
        XCTAssertEqual(
            expectedEpochMs,
            TeslaNaming.parseTimestamp("2024-05-01_12-30-00-front.mp4", timeZone: shanghai)
        )
    }

    func testCameraNameIsExtractedFromFileName() {
        XCTAssertEqual("front", TeslaNaming.cameraOf("2024-05-01_12-30-00-front.mp4"))
        XCTAssertEqual("left_repeater", TeslaNaming.cameraOf("2024-05-01_12-30-00-left_repeater.mp4"))
    }

    func testCameraNameIsExtractedFromEventFile() {
        XCTAssertEqual("back", TeslaNaming.cameraOf("back.mp4"))
        XCTAssertEqual("right_pillar", TeslaNaming.cameraOf("right_pillar.mp4"))
    }

    func testUnknownFilesHaveNoCamera() {
        XCTAssertNil(TeslaNaming.cameraOf("notes.txt"))
    }

    func testClipDirectoryIsRecognised() {
        XCTAssertEqual(
            expectedEpochMs,
            TeslaNaming.parseClipDirectory("2024-05-01_12-30-00", timeZone: shanghai)
        )
        XCTAssertFalse(TeslaNaming.isClipDirectoryName("2024-05-01"))
        XCTAssertNil(TeslaNaming.parseClipDirectory("RecentClips", timeZone: shanghai))
    }

    func testCameraLabelsAreFriendly() {
        XCTAssertEqual("前视", TeslaNaming.cameraLabel("front"))
        XCTAssertEqual("后视", TeslaNaming.cameraLabel("back"))
        XCTAssertEqual("左后", TeslaNaming.cameraLabel("left_repeater"))
        XCTAssertEqual("右后", TeslaNaming.cameraLabel("right_repeater"))
        XCTAssertEqual("左柱", TeslaNaming.cameraLabel("left_pillar"))
        XCTAssertEqual("右柱", TeslaNaming.cameraLabel("right_pillar"))
        XCTAssertEqual("视频", TeslaNaming.cameraLabel(nil))
        XCTAssertEqual("cabin", TeslaNaming.cameraLabel("cabin"))
    }

    func testLegacyNameWithoutCameraStillParses() {
        XCTAssertEqual(
            expectedEpochMs,
            TeslaNaming.parseTimestamp("2024-05-01_12-30-00.mp4", timeZone: shanghai)
        )
    }

    func testInvalidTimestampsReturnNil() {
        XCTAssertNil(TeslaNaming.parseTimestamp("movie.mp4", timeZone: shanghai))
        XCTAssertNil(TeslaNaming.parseTimestamp("2024-13-45_99-99-99-front.mp4", timeZone: shanghai))
        XCTAssertNil(TeslaNaming.parseTimestamp("2024-02-30_12-00-00-front.mp4", timeZone: shanghai))
    }
}
