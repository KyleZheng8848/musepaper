import CoreImage

/// Static bas-relief lighting from a mask. No motion — just a pressed edge.
enum LivingReliefStamp: Sendable {
    static func plate(mask: CGImage, strength: CGFloat = 1) -> CGImage? {
        let amount = min(max(strength, 0.35), 1.6)
        let ci = CIImage(cgImage: mask)
        let extent = ci.extent
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(ci, forKey: kCIInputImageKey)
        blur.setValue(5.5, forKey: kCIInputRadiusKey)
        guard let soft = blur.outputImage?.cropped(to: extent) else { return nil }

        guard let conv = CIFilter(name: "CIConvolution3X3") else { return nil }
        conv.setValue(soft, forKey: kCIInputImageKey)
        conv.setValue(
            CIVector(values: [
                1.4 * amount, 0.9 * amount, 0,
                0.9 * amount, 1, -0.9 * amount,
                0, -0.9 * amount, -1.4 * amount
            ], count: 9),
            forKey: "inputWeights"
        )
        conv.setValue(0.5, forKey: "inputBias")
        guard let emboss = conv.outputImage?.cropped(to: extent) else { return nil }
        return context.createCGImage(emboss, from: extent)
    }

    // CIContext supports concurrent rendering; older SDKs omit its Sendable annotation.
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])
}
