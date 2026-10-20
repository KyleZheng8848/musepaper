import AppKit
import Foundation

struct WallpaperImageAdapter: Sendable {
    func adapt(_ sourceURL: URL, to display: DisplayProfile, index: Int) throws -> URL {
        guard let source = NSImage(contentsOf: sourceURL), source.size.width > 0, source.size.height > 0 else {
            throw MusepaperError.invalidResponse("生成结果不是可读取的图片")
        }
        let prepared = DesktopChromeCropper().cropIfNeeded(source)
        let targetWidth = min(max(display.width, 1280), 7680)
        let targetHeight = min(max(display.height, 720), 4320)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetWidth, pixelsHigh: targetHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw MusepaperError.generationFailed("无法创建屏幕适配画布") }

        let scale = max(CGFloat(targetWidth) / prepared.size.width, CGFloat(targetHeight) / prepared.size.height)
        let drawSize = NSSize(width: prepared.size.width * scale, height: prepared.size.height * scale)
        let drawRect = NSRect(
            x: (CGFloat(targetWidth) - drawSize.width) / 2,
            y: (CGFloat(targetHeight) - drawSize.height) / 2,
            width: drawSize.width, height: drawSize.height
        )
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw MusepaperError.generationFailed("无法创建屏幕适配上下文") }
        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
        prepared.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw MusepaperError.generationFailed("屏幕适配 PNG 编码失败") }
        let destination = sourceURL.deletingPathExtension().appendingPathExtension("wallpaper-\(index).png")
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
