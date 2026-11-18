import CoreGraphics
import Foundation
import XCTest
#if canImport(TeslaTimestampCore)
import TeslaTimestampCore
#else
@testable import TeslaTimestamp
#endif

final class OverlayStyleTests: XCTestCase {

    // 2024-05-01T04:30:05Z -> 1_714_537_805_000 ms
    private let epoch: Int64 = 1_714_537_805_000
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    func testFormatsFullTimestamp() {
        XCTAssertEqual("2024-05-01 12:30:05", OverlayText.timeLine(epoch, timeZone: shanghai))
    }

    func testClockOnlyWhenDateIsHidden() {
        let style = OverlayStyle(showDate: false)
        XCTAssertEqual("12:30:05", OverlayText.firstLine(epoch, style: style, timeZone: shanghai))
    }

    func testUtcZoneFormatsDifferently() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual("2024-05-01 04:30:05", OverlayText.timeLine(epoch, timeZone: utc))
    }

    func testTextSizeScalesWithVideoHeight() {
        let medium = OverlayStyle(textScale: 1.0)
        let small = OverlayStyle(textScale: 0.7)
        XCTAssertEqual(1080.0 * 0.055, 1080.0 * medium.textFraction, accuracy: 0.001)
        XCTAssertGreaterThan(medium.textFraction, small.textFraction)
    }

    func testDetailLineContainsCameraAndCity() throws {
        let info = TeslaEventInfo(city: "上海市", estLat: 31.2304, estLon: 121.4737)
        let line = try XCTUnwrap(OverlayText.detailLine(cameraLabel: "前视", eventInfo: info))
        XCTAssertTrue(line.contains("前视"))
        XCTAssertTrue(line.contains("上海市"))
        XCTAssertTrue(line.contains("31.23040"))
    }

    func testDetailLineWithoutMetadata() {
        XCTAssertNil(OverlayText.detailLine(cameraLabel: nil, eventInfo: nil))
        XCTAssertEqual("前视", OverlayText.detailLine(cameraLabel: "前视", eventInfo: nil))
    }

    func testOverlayBitmapFactoryRendersSingleAndMultiLineBitmaps() throws {
        let style = OverlayStyle(position: .topLeft, textScale: 1.0, showDate: true, showDetails: true)
        let single = try XCTUnwrap(
            OverlayBitmapFactory.create(lines: ["2024-05-01 12:30:05"], textSizePx: 40, style: style)
        )
        let doubleLine = try XCTUnwrap(
            OverlayBitmapFactory.create(
                lines: ["2024-05-01 12:30:05", "前视 · 上海市 · 31.23040, 121.47370 · 手动保存"],
                textSizePx: 40,
                style: style
            )
        )
        XCTAssertGreaterThan(single.width, 100)
        XCTAssertGreaterThan(single.height, 40)
        XCTAssertGreaterThan(doubleLine.height, single.height)
        XCTAssertGreaterThan(doubleLine.width, single.width)
    }

    func testTimeFormatsFileSizeAndDuration() {
        XCTAssertEqual("-", TimeFormats.fileSize(0))
        XCTAssertEqual("512 B", TimeFormats.fileSize(512))
        XCTAssertEqual("2 KB", TimeFormats.fileSize(2048))
        XCTAssertEqual("1.5 MB", TimeFormats.fileSize(1_572_864))
        XCTAssertEqual("00:55", TimeFormats.duration(55))
        XCTAssertEqual("1:02:03", TimeFormats.duration(3723))
    }
}
