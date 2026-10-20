import AppKit
import CoreGraphics
import Foundation

struct DemoImageProvider: ImageProvider {
    let name = "Musepaper Demo Renderer"

    func generate(_ request: GenerationRequest, outputDirectory: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let width = min(max(request.display.width, 1280), 3840)
        let height = min(max(request.display.height, 720), 2160)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw MusepaperError.generationFailed("无法创建画布") }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw MusepaperError.generationFailed("无法创建绘图上下文")
        }
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let hash = abs(request.resolvedPrompt.hashValue)
        let hue = CGFloat(hash % 360) / 360
        let top = NSColor(calibratedHue: hue, saturation: 0.42, brightness: 0.22, alpha: 1)
        let bottom = NSColor(calibratedHue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.06, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -28)

        for index in 0..<18 {
            let radius = CGFloat(60 + (hash + index * 31) % 380)
            let x = CGFloat((hash / (index + 1) + index * 191) % width)
            let y = CGFloat((hash / (index + 3) + index * 127) % height)
            NSColor.white.withAlphaComponent(index % 3 == 0 ? 0.07 : 0.025).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw MusepaperError.generationFailed("PNG 编码失败")
        }
        let url = outputDirectory.appendingPathComponent("\(request.id.uuidString).png")
        try data.write(to: url, options: .atomic)
        return [url]
    }
}
