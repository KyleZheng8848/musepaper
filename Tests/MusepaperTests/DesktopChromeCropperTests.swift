import AppKit
import XCTest
@testable import Musepaper

final class DesktopChromeCropperTests: XCTestCase {
    let cropper = DesktopChromeCropper()

    func testCropsSyntheticMenuBarAndDock() {
        let image = makeChromeMockup(width: 400, height: 280)
        let insets = cropper.insets(of: image)
        XCTAssertGreaterThanOrEqual(insets.top, 10, "top=\(insets.top)")
        XCTAssertGreaterThanOrEqual(insets.bottom, 24, "bottom=\(insets.bottom)")
        XCTAssertGreaterThanOrEqual(insets.left, 6, "left=\(insets.left)")
        XCTAssertGreaterThanOrEqual(insets.right, 6, "right=\(insets.right)")
        let cropped = cropper.cropIfNeeded(image)
        XCTAssertLessThan(cropped.size.height, image.size.height)
        XCTAssertLessThan(cropped.size.width, image.size.width)
    }

    func testDoesNotCropPlainLandscape() {
        let image = makeLandscape(width: 400, height: 280)
        let insets = cropper.insets(of: image)
        XCTAssertEqual(insets, ChromeInsets(top: 0, left: 0, bottom: 0, right: 0))
        let cropped = cropper.cropIfNeeded(image)
        XCTAssertEqual(cropped.size, image.size)
    }

    func testCropsBottomOnlyInstructionPlate() {
        let image = makeBottomTextSheet(width: 400, height: 280)
        let insets = cropper.insets(of: image)
        XCTAssertGreaterThanOrEqual(insets.bottom, 80, "bottom=\(insets.bottom)")
        XCTAssertLessThan(cropper.cropIfNeeded(image).size.height, image.size.height)
    }

    func testCropsInstructionTextPlates() {
        let image = makeTextSpecSheet(width: 400, height: 280)
        let insets = cropper.insets(of: image)
        XCTAssertGreaterThanOrEqual(insets.top, 20, "top=\(insets.top)")
        XCTAssertGreaterThanOrEqual(insets.bottom, 20, "bottom=\(insets.bottom)")
        let cropped = cropper.cropIfNeeded(image)
        XCTAssertLessThan(cropped.size.height, image.size.height)
    }

    func testDoesNotCropNightSky() {
        let image = makeNightSky(width: 400, height: 280)
        let insets = cropper.insets(of: image)
        XCTAssertEqual(insets.top, 0, "night sky must not look like a menu bar")
        XCTAssertEqual(insets.bottom, 0, "starfield must not look like a dock")
        XCTAssertEqual(cropper.cropIfNeeded(image).size, image.size)
    }

    private func makeChromeMockup(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { bounds in
            NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.58, alpha: 1).setFill()
            bounds.fill()
            NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.32, alpha: 1).setFill()
            NSRect(x: 40, y: 70, width: 320, height: 90).fill()

            NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 10, height: bounds.height).fill()
            NSRect(x: bounds.width - 10, y: 0, width: 10, height: bounds.height).fill()

            NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.102, alpha: 1).setFill()
            NSRect(x: 0, y: bounds.height - 16, width: bounds.width, height: 16).fill()

            NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.102, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 40).fill()
            let iconColors: [NSColor] = [
                NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.28, alpha: 1),
                NSColor(calibratedRed: 0.38, green: 0.86, blue: 0.40, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.22, alpha: 1),
                NSColor(calibratedRed: 0.72, green: 0.48, blue: 0.98, alpha: 1)
            ]
            for (index, color) in iconColors.enumerated() {
                color.setFill()
                NSRect(x: 70 + CGFloat(index) * 52, y: 8, width: 22, height: 22).fill()
            }
        }
    }

    private func makeLandscape(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { bounds in
            NSGradient(
                starting: NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.28, alpha: 1),
                ending: NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.62, alpha: 1)
            )?.draw(in: bounds, angle: -18)
            NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.28, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 40, y: 30, width: 180, height: 90)).fill()
        }
    }

    private func makeTextSpecSheet(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { bounds in
            NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.58, alpha: 1).setFill()
            bounds.fill()
            NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1).setFill()
            NSRect(x: 0, y: bounds.height - 72, width: bounds.width, height: 72).fill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 72).fill()
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            for row in 0..<6 {
                for col in 0..<16 {
                    NSRect(x: 14 + CGFloat(col) * 22, y: bounds.height - 18 - CGFloat(row) * 10, width: 9, height: 4).fill()
                    NSRect(x: 14 + CGFloat(col) * 22, y: 14 + CGFloat(row) * 10, width: 8, height: 4).fill()
                }
            }
        }
    }

    private func makeBottomTextSheet(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { bounds in
            NSColor(calibratedRed: 0.42, green: 0.58, blue: 0.38, alpha: 1).setFill()
            bounds.fill()
            NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 30, y: 150, width: 200, height: 80)).fill()
            NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 120).fill()
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            for row in 0..<10 {
                for col in 0..<16 {
                    NSRect(x: 14 + CGFloat(col) * 22, y: 12 + CGFloat(row) * 10, width: 9, height: 4).fill()
                }
            }
        }
    }

    private func makeNightSky(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { bounds in
            NSColor(calibratedRed: 0.043, green: 0.094, blue: 0.188, alpha: 1).setFill()
            bounds.fill()
            NSColor(calibratedRed: 0.10, green: 0.19, blue: 0.31, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 50).fill()
            NSColor.white.setFill()
            var seed = 17
            for _ in 0..<90 {
                seed = seed &* 1103515245 &+ 12345
                let x = CGFloat(abs(seed) % width)
                seed = seed &* 1103515245 &+ 12345
                let y = CGFloat(abs(seed) % height)
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
    }

    private func makeImage(width: Int, height: Int, draw: (NSRect) -> Void) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        draw(NSRect(x: 0, y: 0, width: width, height: height))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}
