import AppKit
import XCTest
@testable import Musepaper

final class WallpaperControllerTests: XCTestCase {
    func testWallpaperUsesFullBleedScaling() {
        XCTAssertEqual(
            WallpaperController.fillOptions[.imageScaling] as? Int,
            NSImageScaling.scaleAxesIndependently.rawValue
        )
        XCTAssertEqual(WallpaperController.fillOptions[.allowClipping] as? Bool, true)
        XCTAssertNotNil(WallpaperController.fillOptions[.fillColor] as? NSColor)
    }

    func testWallpaperOverlayLevelDoesNotTrap() {
        // Regression: averaging two Int32 desktop levels overflowed and crashed on every switch.
        let level = WallpaperController.wallpaperOverlayLevel
        XCTAssertLessThan(level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertEqual(
            level.rawValue,
            Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        )
    }

    func testSystemWallpaperCachePrunerKeepsNewestWithinBudget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-wallpaper-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        for index in 0..<8 {
            let url = root.appendingPathComponent("file-\(index).bmp")
            let data = Data(repeating: UInt8(index), count: 1024 * 100) // 100 KB
            try data.write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }

        let deleted = SystemWallpaperCachePruner.prune(
            root: root,
            keepNewest: 3,
            maxTotalBytes: 1024 * 400 // enough for three 100KB files
        )
        XCTAssertEqual(deleted, 5)
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(remaining, ["file-5.bmp", "file-6.bmp", "file-7.bmp"])
    }

    func testSystemWallpaperCachePrunerTrimsToBudgetButKeepsTwo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-wallpaper-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        for index in 0..<5 {
            let url = root.appendingPathComponent("file-\(index).bmp")
            try Data(repeating: 1, count: 1024 * 100).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }

        let deleted = SystemWallpaperCachePruner.prune(
            root: root,
            keepNewest: 4,
            maxTotalBytes: 1024 * 150 // forces drop below keepNewest, floor at 2
        )
        XCTAssertEqual(deleted, 3)
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertEqual(remaining, ["file-3.bmp", "file-4.bmp"])
    }

    func testSystemWallpaperCachePrunerSkipsZeroByteInFlightFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-wallpaper-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        for index in 0..<3 {
            let url = root.appendingPathComponent("file-\(index).bmp")
            try Data(repeating: 1, count: index == 2 ? 0 : 1024).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }

        let deleted = SystemWallpaperCachePruner.prune(root: root, keepNewest: 1, maxTotalBytes: 1024 * 10)
        XCTAssertEqual(deleted, 1)
        let remaining = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        // Newest zero-byte is ignored for keep ranking; keep file-1, delete file-0, leave empty file-2 alone.
        XCTAssertEqual(remaining, ["file-1.bmp", "file-2.bmp"])
    }
}
