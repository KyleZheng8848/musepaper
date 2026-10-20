import AppKit
import CoreGraphics
import Foundation

struct ChromeInsets: Equatable, Sendable {
    var top: Int
    var left: Int
    var bottom: Int
    var right: Int

    var shouldCrop: Bool { top > 0 || left > 0 || bottom > 0 || right > 0 }
}

struct DesktopChromeCropper: Sendable {
    func cropIfNeeded(_ image: NSImage) -> NSImage {
        guard let raster = rasterize(image) else { return image }
        let insets = analyze(width: raster.width, height: raster.height, pixels: raster.pixels)
        guard insets.shouldCrop else { return image }
        let rect = CGRect(
            x: insets.left,
            y: insets.top,
            width: raster.width - insets.left - insets.right,
            height: raster.height - insets.top - insets.bottom
        )
        guard rect.width >= 32, rect.height >= 32,
              let cropped = raster.image.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    func insets(of image: NSImage) -> ChromeInsets {
        guard let raster = rasterize(image) else {
            return ChromeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        return analyze(width: raster.width, height: raster.height, pixels: raster.pixels)
    }

    private func analyze(width: Int, height: Int, pixels: [UInt8]) -> ChromeInsets {
        guard width >= 64, height >= 64, pixels.count >= width * height * 4 else {
            return ChromeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        let buffer = PixelBuffer(width: width, height: height, pixels: pixels)
        let topBar = topBarHeight(buffer)
        let dock = dockHeight(buffer)
        let topText = textPlateHeight(buffer, fromStart: true)
        let bottomText = textPlateHeight(buffer, fromStart: false)
        let scenic = scenicBandInsets(buffer)
        let top = max(topBar, topText, scenic.top)
        let bottom = max(dock, bottomText, scenic.bottom)
        let thinTop = topBar > 0 && topBar <= max(3, Int(Double(height) * 0.045))
        let textPair = topText > Int(Double(height) * 0.06) && bottomText > Int(Double(height) * 0.06)
        let largeText = topText > Int(Double(height) * 0.10) || bottomText > Int(Double(height) * 0.10)
        let scenicCrop = scenic.top > Int(Double(height) * 0.08) || scenic.bottom > Int(Double(height) * 0.08)
        let confident = (top > 0 && bottom > 0) || thinTop || textPair || largeText || scenicCrop
        guard confident else {
            return ChromeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }

        let y0 = top
        let y1 = height - bottom
        let left = sideBezel(buffer, fromLeading: true, y0: y0, y1: y1)
        let right = sideBezel(buffer, fromLeading: false, y0: y0, y1: y1)
        let remainW = width - left - right
        let remainH = height - top - bottom
        if remainW < width / 2 || remainH < height / 3 {
            return ChromeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        return ChromeInsets(top: top, left: left, bottom: bottom, right: right)
    }

    private func topBarHeight(_ buffer: PixelBuffer) -> Int {
        let maxH = max(3, Int(Double(buffer.height) * 0.08))
        var height = 0
        for y in 0..<maxH {
            let row = buffer.rowStats(y)
            if row.looksLikeNightSky { break }
            if row.isFlatDarkChrome {
                height = y + 1
            } else {
                break
            }
        }
        if height < 3 { return 0 }
        if buffer.bandLooksLikeNightSky(y0: 0, y1: height) { return 0 }
        if height < buffer.height {
            let next = buffer.rowStats(height)
            let sharp = next.variance > 0.01 || next.meanLuma > 0.30 || next.darkRatio < 0.55
            if !sharp && height > Int(Double(buffer.height) * 0.04) { return 0 }
        }
        return height
    }

    private func dockHeight(_ buffer: PixelBuffer) -> Int {
        let maxH = max(6, Int(Double(buffer.height) * 0.16))
        var height = 0
        var iconRows = 0
        for y in stride(from: buffer.height - 1, through: buffer.height - maxH, by: -1) {
            let row = buffer.rowStats(y)
            if row.isDockLike || row.isFlatDarkChrome {
                height = buffer.height - y
                if row.isDockLike { iconRows += 1 }
            } else {
                break
            }
        }
        if height < 6 || iconRows < 2 { return 0 }
        return height
    }

    private func textPlateHeight(_ buffer: PixelBuffer, fromStart: Bool) -> Int {
        let maxH = max(12, Int(Double(buffer.height) * 0.58))
        var height = 0
        var textRows = 0
        var seenText = false
        for offset in 0..<maxH {
            let y = fromStart ? offset : buffer.height - 1 - offset
            let row = buffer.rowStats(y)
            if row.isTextPlate {
                height = offset + 1
                textRows += 1
                seenText = true
            } else if row.meanLuma < 0.42, row.saturation < 0.30, row.darkRatio > 0.50 {
                if seenText { height = offset + 1 }
            } else {
                break
            }
        }
        if height < 12 || textRows < 4 { return 0 }
        return height
    }

    private func scenicBandInsets(_ buffer: PixelBuffer) -> (top: Int, bottom: Int) {
        let height = buffer.height
        let step = max(height / 90, 1)
        var scenic: [Bool] = []
        var y = 0
        while y < height {
            scenic.append(buffer.rowStats(y).isScenicContent)
            y += step
        }
        guard !scenic.isEmpty else { return (0, 0) }
        var bestStart = 0
        var bestLength = 0
        var runStart = 0
        var runLength = 0
        for (index, isScenic) in scenic.enumerated() {
            if isScenic {
                if runLength == 0 { runStart = index }
                runLength += 1
                if runLength > bestLength {
                    bestStart = runStart
                    bestLength = runLength
                }
            } else {
                runLength = 0
            }
        }
        let bandHeight = bestLength * step
        guard bandHeight >= Int(Double(height) * 0.34) else { return (0, 0) }
        let top = bestStart * step
        let bottom = max(height - (bestStart + bestLength) * step, 0)
        if top < Int(Double(height) * 0.08) && bottom < Int(Double(height) * 0.08) {
            return (0, 0)
        }
        return (top, bottom)
    }

    private func sideBezel(_ buffer: PixelBuffer, fromLeading: Bool, y0: Int, y1: Int) -> Int {
        let maxW = max(2, Int(Double(buffer.width) * 0.12))
        var width = 0
        for offset in 0..<maxW {
            let x = fromLeading ? offset : buffer.width - 1 - offset
            let column = buffer.columnStats(x, y0: y0, y1: y1)
            if column.isFlatDarkChrome {
                width = offset + 1
            } else {
                break
            }
        }
        return width >= 2 ? width : 0
    }

    private func rasterize(_ image: NSImage) -> (width: Int, height: Int, pixels: [UInt8], image: CGImage)? {
        let pixelWidth: Int
        let pixelHeight: Int
        if let rep = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh })
        {
            pixelWidth = rep.pixelsWide
            pixelHeight = rep.pixelsHigh
        } else {
            pixelWidth = max(Int(round(image.size.width)), 1)
            pixelHeight = max(Int(round(image.size.height)), 1)
        }
        guard pixelWidth >= 32, pixelHeight >= 32 else { return nil }

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rendered: CGImage? = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            } else {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                image.draw(
                    in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
                    from: .zero, operation: .copy, fraction: 1
                )
                NSGraphicsContext.restoreGraphicsState()
            }
            return ctx.makeImage()
        }
        guard let rendered else { return nil }
        return (pixelWidth, pixelHeight, pixels, rendered)
    }
}

private struct BandStats {
    var meanLuma: Double
    var variance: Double
    var darkRatio: Double
    var brightRatio: Double
    var saturation: Double
    var meanR: Double
    var meanG: Double
    var meanB: Double
    var edgeEnergy: Double

    var isFlatDarkChrome: Bool {
        meanLuma < 0.26 && variance < 0.007 && darkRatio > 0.70 && saturation < 0.22
    }

    var isDockLike: Bool {
        meanLuma < 0.35 && darkRatio > 0.40 && brightRatio > 0.012 && variance > 0.005
    }

    var isTextPlate: Bool {
        meanLuma < 0.48 && saturation < 0.28 && darkRatio > 0.28
            && (edgeEnergy > 0.018 || variance > 0.012)
            && !looksLikeNightSky
    }

    var isScenicContent: Bool {
        if isTextPlate || isFlatDarkChrome { return false }
        if looksLikeNightSky { return true }
        return saturation > 0.16 || (meanLuma > 0.22 && meanLuma < 0.88 && edgeEnergy < 0.12 && darkRatio < 0.75)
    }

    var looksLikeNightSky: Bool {
        let bluish = meanB > meanR + 0.03 && meanB > meanG
        if bluish && saturation > 0.28 && variance > 0.002 { return true }
        return meanLuma < 0.18 && brightRatio > 0 && brightRatio < 0.04 && variance > 0.004 && saturation > 0.12
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func rowStats(_ y: Int) -> BandStats {
        stats(count: width) { x in (x, y) }
    }

    func columnStats(_ x: Int, y0: Int, y1: Int) -> BandStats {
        let start = max(y0, 0)
        let end = min(y1, height)
        let count = max(end - start, 1)
        return stats(count: count) { i in (x, start + i) }
    }

    func bandLooksLikeNightSky(y0: Int, y1: Int) -> Bool {
        var brightPoints = 0
        var samples = 0
        var lumaSum = 0.0
        var lumaSq = 0.0
        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        for y in y0..<y1 {
            for x in stride(from: 0, to: width, by: 2) {
                let color = rgba(x, y)
                let luma = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
                lumaSum += luma
                lumaSq += luma * luma
                rSum += color.r
                gSum += color.g
                bSum += color.b
                if luma > 0.55 { brightPoints += 1 }
                samples += 1
            }
        }
        guard samples > 0 else { return false }
        let mean = lumaSum / Double(samples)
        let variance = max(lumaSq / Double(samples) - mean * mean, 0)
        let bluish = (bSum / Double(samples)) > (rSum / Double(samples)) + 0.03
        let scatteredStars = brightPoints > 0 && Double(brightPoints) / Double(samples) < 0.04 && variance > 0.004
        return scatteredStars || (bluish && variance > 0.003)
    }

    private func stats(count: Int, point: (Int) -> (Int, Int)) -> BandStats {
        var lumaSum = 0.0
        var lumaSq = 0.0
        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        var dark = 0
        var bright = 0
        var edgeSum = 0.0
        var prevLuma: Double?
        let step = max(count / 160, 1)
        var samples = 0
        var i = 0
        while i < count {
            let (x, y) = point(i)
            let color = rgba(x, y)
            let luma = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
            lumaSum += luma
            lumaSq += luma * luma
            rSum += color.r
            gSum += color.g
            bSum += color.b
            if luma < 0.22 { dark += 1 }
            if luma > 0.45 { bright += 1 }
            if let prev = prevLuma { edgeSum += abs(luma - prev) }
            prevLuma = luma
            samples += 1
            i += step
        }
        let n = max(Double(samples), 1)
        let meanR = rSum / n
        let meanG = gSum / n
        let meanB = bSum / n
        let meanLuma = lumaSum / n
        let maxC = max(meanR, meanG, meanB)
        let minC = min(meanR, meanG, meanB)
        return BandStats(
            meanLuma: meanLuma,
            variance: max(lumaSq / n - meanLuma * meanLuma, 0),
            darkRatio: Double(dark) / n,
            brightRatio: Double(bright) / n,
            saturation: maxC < 0.01 ? 0 : (maxC - minC) / maxC,
            meanR: meanR,
            meanG: meanG,
            meanB: meanB,
            edgeEnergy: edgeSum / n
        )
    }

    private func rgba(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let offset = (clampedY * width + clampedX) * 4
        return (
            Double(pixels[offset]) / 255,
            Double(pixels[offset + 1]) / 255,
            Double(pixels[offset + 2]) / 255
        )
    }
}
