import XCTest
@testable import Musepaper

final class DisplayServiceTests: XCTestCase {
    func testMapsMultipleScreensWithMainFirst() {
        let profiles = DisplayService.profiles(from: [
            DisplayProbe(width: 3600, height: 2338, scale: 2),
            DisplayProbe(width: 1920, height: 1080, scale: 1)
        ])

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].id, "screen-0")
        XCTAssertEqual(profiles[0].name, "主显示器")
        XCTAssertEqual(profiles[0].width, 3600)
        XCTAssertEqual(profiles[0].height, 2338)
        XCTAssertEqual(profiles[1].id, "screen-1")
        XCTAssertEqual(profiles[1].name, "显示器 2")
        XCTAssertEqual(profiles[1].width, 1920)
    }

    func testSingleScreenIsMainOnly() {
        let profiles = DisplayService.profiles(from: [
            DisplayProbe(width: 1512, height: 982, scale: 2)
        ])

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].name, "主显示器")
        XCTAssertEqual(profiles[0].id, "screen-0")
    }

    func testDisplayIDUsesTheScreenThatContainsThePoint() {
        let left = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let right = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let frames = [left, right]

        XCTAssertEqual(DisplayService.displayID(containing: NSPoint(x: 100, y: 100), frames: frames), "screen-0")
        XCTAssertEqual(DisplayService.displayID(containing: NSPoint(x: 2000, y: 10), frames: frames), "screen-1")
        XCTAssertEqual(DisplayService.displayID(containing: NSPoint(x: -50, y: 0), frames: frames), "screen-0")
    }

    func testLiveServiceFindsAtLeastTheMainDisplay() {
        let profiles = DisplayService().profiles()
        XCTAssertFalse(profiles.isEmpty)
        XCTAssertEqual(profiles[0].name, "主显示器")
        XCTAssertEqual(profiles[0].id, "screen-0")
    }
}
