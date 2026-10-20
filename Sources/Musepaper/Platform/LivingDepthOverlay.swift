import AppKit
import QuartzCore

/// Optional relief film on the wallpaper photo.
/// Uses a mask to press a cameo edge. The photo and atmosphere stay as they were.
enum LivingDepthStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case off = "关闭"
    case relief = "浮雕"

    var id: String { rawValue }
    var isOn: Bool { self != .off }
}

@MainActor
final class LivingDepthOverlay {
    let layer = CALayer()
    var front: CALayer { layer }

    private let maskLayer = CALayer()
    private weak var imageLayer: CALayer?
    private var style: LivingDepthStyle = .off
    private var gain: CGFloat = 1
    private var lastCacheKey: String?
    private var lastImage: CGImage?
    private var stampToken: UInt64 = 0

    init() {
        layer.contentsGravity = .resizeAspectFill
        layer.compositingFilter = "overlayBlendMode"
        layer.mask = maskLayer
        layer.opacity = 0
        layer.isHidden = true
        maskLayer.contentsGravity = .resizeAspectFill
        setStyle(.off, gain: 1)
    }

    func attach(to host: CALayer, imageLayer: CALayer, bounds: CGRect) {
        _ = host
        self.imageLayer = imageLayer
        if layer.superlayer !== imageLayer {
            layer.removeFromSuperlayer()
            imageLayer.addSublayer(layer)
        }
        layout(bounds)
        applyVisibility()
    }

    func setStyle(_ style: LivingDepthStyle, gain: CGFloat) {
        self.style = style
        self.gain = max(gain, 0.2)
        applyVisibility()
        if style.isOn, let lastImage {
            requestStamp(for: lastImage, cacheKey: lastCacheKey)
        }
        if !style.isOn {
            layer.contents = nil
            maskLayer.contents = nil
        }
    }

    func setImage(_ image: CGImage?, cacheKey: String? = nil) {
        lastImage = image
        lastCacheKey = cacheKey ?? image.map { "\($0.width)x\($0.height)" }
        if let image, style.isOn {
            requestStamp(for: image, cacheKey: lastCacheKey)
        } else {
            layer.contents = nil
            maskLayer.contents = nil
            stampToken += 1
        }
    }

    func layout(_ bounds: CGRect) {
        layer.frame = bounds
        maskLayer.frame = bounds
        if layer.contents == nil, style.isOn {
            applyFallbackStamp(size: bounds.size)
        }
    }

    private func applyVisibility() {
        let on = style.isOn
        layer.isHidden = !on
        layer.opacity = on ? Float(min(0.78 * gain, 0.92)) : 0
        imageLayer?.isHidden = false
    }

    private func apply(_ pack: LivingCardCutout.Pack, plate: CGImage?) {
        let island = pack.usedSubject ? pack.subject : pack.mid
        maskLayer.contents = island
        layer.contents = plate ?? LivingReliefStamp.plate(mask: island, strength: gain)
    }

    private func applyFallbackStamp(size: CGSize) {
        let pack = LivingCardCutout.ovalPack(size: size)
        apply(pack, plate: LivingReliefStamp.plate(mask: pack.mid, strength: gain))
    }

    private func finishStamp(_ pack: LivingCardCutout.Pack, plate: CGImage?, token: UInt64) {
        guard stampToken == token, style.isOn else { return }
        apply(pack, plate: plate)
    }

    private func requestStamp(for image: CGImage, cacheKey: String?) {
        applyFallbackStamp(size: CGSize(width: 320, height: 200))
        stampToken += 1
        let token = stampToken
        let strength = gain
        Task.detached(priority: .utility) { [weak self] in
            let pack = LivingCardCutout.make(from: image)
            let island = pack.usedSubject ? pack.subject : pack.mid
            let plate = LivingReliefStamp.plate(mask: island, strength: strength)
            await self?.finishStamp(pack, plate: plate, token: token)
            _ = cacheKey
        }
    }
}
