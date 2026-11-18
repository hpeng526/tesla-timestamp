import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class TeslaCamScannerTests: XCTestCase {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testScansRecentSavedSentryAndHW4PillarCameras() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeslaCamTest_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recentDir = root.appendingPathComponent("RecentClips", isDirectory: true)
        let savedClipDir = root
            .appendingPathComponent("SavedClips", isDirectory: true)
            .appendingPathComponent("2024-05-01_13-00-00", isDirectory: true)
        let sentryClipDir = root
            .appendingPathComponent("SentryClips", isDirectory: true)
            .appendingPathComponent("2024-05-01_11-00-00", isDirectory: true)

        try FileManager.default.createDirectory(at: recentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: savedClipDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sentryClipDir, withIntermediateDirectories: true)

        // HW4 6-camera recent clip
        let hw4Cameras = ["right_pillar", "left_pillar", "right_repeater", "left_repeater", "back", "front"]
        for cam in hw4Cameras {
            try Data("video".utf8).write(
                to: recentDir.appendingPathComponent("2024-05-01_12-30-00-\(cam).mp4")
            )
        }

        // Saved clip with event.json
        try Data("video_front".utf8).write(to: savedClipDir.appendingPathComponent("front.mp4"))
        try Data("video_back".utf8).write(to: savedClipDir.appendingPathComponent("back.mp4"))
        let eventJson = """
        {"timestamp":"2024-05-01T13:00:00","city":"杭州市","est_lat":30.2741,"est_lon":120.1551,"reason":"user_interaction_honk"}
        """
        try Data(eventJson.utf8).write(to: savedClipDir.appendingPathComponent("event.json"))

        // Sentry clip
        try Data("sentry_front".utf8).write(to: sentryClipDir.appendingPathComponent("front.mp4"))

        let scanner = TeslaCamScanner()
        let result = try scanner.scanFolder(url: root, securityScoped: false, timeZone: shanghai)

        XCTAssertEqual(9, result.fileCount)
        XCTAssertEqual(3, result.groups.count)
        XCTAssertTrue(result.warnings.isEmpty)

        // Sorted descending by timestamp: 13:00 (Saved) -> 12:30 (Recent) -> 11:00 (Sentry)
        XCTAssertEqual(.saved, result.groups[0].category)
        XCTAssertEqual("杭州市", result.groups[0].eventInfo?.city)
        XCTAssertEqual("鸣笛保存", result.groups[0].eventInfo?.reasonLabel())
        XCTAssertEqual(["front", "back"], result.groups[0].files.compactMap(\.camera))

        XCTAssertEqual(.recent, result.groups[1].category)
        XCTAssertEqual(
            ["front", "back", "left_repeater", "right_repeater", "left_pillar", "right_pillar"],
            result.groups[1].files.compactMap(\.camera)
        )

        XCTAssertEqual(.sentry, result.groups[2].category)
    }

    func testWarnsWhenClipHasNoTeslaTimestamp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TeslaCamFallback_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("plain".utf8).write(to: root.appendingPathComponent("random_clip.mp4"))

        let scanner = TeslaCamScanner()
        let result = try scanner.scanFolder(url: root, securityScoped: false, timeZone: shanghai)

        XCTAssertEqual(1, result.groups.count)
        XCTAssertEqual(.unknown, result.groups[0].category)
        XCTAssertEqual(1, result.warnings.count)
        XCTAssertTrue(result.warnings[0].contains("没有 Tesla 时间戳"))
    }
}
