import CoreImage
import CoreVideo
import Vision

/// Greeting-card cutouts from one photo: subject sheet + a wider mid sheet.
/// Small masks only. Vision foreground in the background; ovals first.
enum LivingCardCutout: Sendable {
    struct Pack: Sendable {
        let subject: CGImage
        let lift: CGImage
        let mid: CGImage
        let usedSubject: Bool
    }

    static let maskMaxEdge: CGFloat = 320

    static func make(from image: CGImage) -> Pack {
        let work = downsampled(image, maxEdge: 512)
        if let mask = foregroundMask(work), isUsable(mask) {
            return pack(subject: mask, size: work.size)
        }
        return ovalPack(size: work.size)
    }

    static func ovalPack(size: CGSize) -> Pack {
        let fitted = fit(size, maxEdge: maskMaxEdge)
        let w = max(Int(fitted.width.rounded()), 8)
        let h = max(Int(fitted.height.rounded()), 8)
        return Pack(
            subject: oval(width: w, height: h, span: 0.46, feather: 16),
            lift: oval(width: w, height: h, span: 0.62, feather: 18),
            mid: oval(width: w, height: h, span: 0.78, feather: 22),
            usedSubject: false
        )
    }

    static func oval(width: Int, height: Int, span: CGFloat, feather: CGFloat) -> CGImage {
        let w = max(width, 8)
        let h = max(height, 8)
        var pixels = [UInt8](repeating: 0, count: w * h)
        let cx = CGFloat(w - 1) / 2
        let cy = CGFloat(h - 1) / 2
        let rx = max(span * CGFloat(w) * 0.5, 1)
        let ry = max(span * CGFloat(h) * 0.5, 1)
        let fade = min(max(feather, 0.8), min(rx, ry) * 0.22)
        for y in 0..<h {
            for x in 0..<w {
                let nx = (CGFloat(x) - cx) / rx
                let ny = (CGFloat(y) - cy) / ry
                let d = hypot(nx, ny)
                let extra = max(d - 1, 0) * min(rx, ry)
                let alpha = d <= 1 ? 1 : max(0, 1 - extra / fade)
                pixels[y * w + x] = UInt8(clamping: Int((alpha * 255).rounded()))
            }
        }
        return alphaImage(width: w, height: h, pixels: pixels)
    }

    static func opaqueFraction(_ image: CGImage) -> CGFloat {
        guard let data = grayscale(image), !data.pixels.isEmpty else { return 0 }
        let step = max(data.pixels.count / 8000, 1)
        var lit = 0
        var seen = 0
        var i = 0
        while i < data.pixels.count {
            if data.pixels[i] > 40 { lit += 1 }
            seen += 1
            i += step
        }
        return seen == 0 ? 0 : CGFloat(lit) / CGFloat(seen)
    }

    private static func pack(subject: CGImage, size: CGSize) -> Pack {
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        let lift = expand(subject, radius: 18) ?? oval(width: w, height: h, span: 0.62, feather: 18)
        let mid = expand(subject, radius: 40) ?? oval(width: w, height: h, span: 0.78, feather: 22)
        return Pack(
            subject: blur(subject, radius: 2) ?? subject,
            lift: blur(lift, radius: 4) ?? lift,
            mid: blur(mid, radius: 7) ?? mid,
            usedSubject: true
        )
    }

    private static func isUsable(_ mask: CGImage) -> Bool {
        let fraction = opaqueFraction(mask)
        return fraction >= 0.05 && fraction <= 0.74
    }

    private static func foregroundMask(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances,
                from: handler
            )
            return cgImage(from: buffer)
        } catch {
            return nil
        }
    }

    private static func fit(_ size: CGSize, maxEdge: CGFloat) -> CGSize {
        let longest = max(size.width, size.height, 1)
        let scale = min(1, maxEdge / longest)
        return CGSize(width: max(size.width * scale, 8), height: max(size.height * scale, 8))
    }

    private static func downsampled(_ image: CGImage, maxEdge: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let scale = min(1, maxEdge / max(w, h))
        guard scale < 1 else { return image }
        let ci = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(ci, from: ci.extent) ?? image
    }

    private static func expand(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIMorphologyMaximum") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    private static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return image }
        let crop = output.cropped(to: ci.extent)
        return context.createCGImage(crop, from: crop.extent)
    }

    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return context.createCGImage(ci, from: ci.extent)
    }

    private static func alphaImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    private static func grayscale(_ image: CGImage) -> (width: Int, height: Int, pixels: [UInt8])? {
        let w = image.width
        let h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, pixels)
    }

    // CIContext supports concurrent rendering; older SDKs omit its Sendable annotation.
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])
}

private extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}
