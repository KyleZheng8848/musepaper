import AppKit
import QuartzCore

/// Extra holographic foil on the living wallpaper.
/// Rainbow phase follows view angle — same pink/yellow/blue/white knots as
/// holo-card-studio. This is a film on top of the photo, not a new motion style.
enum LivingHoloFoil: String, Codable, CaseIterable, Identifiable, Sendable {
    case off = "关闭"
    case iris = "虹膜镭射"
    case sparkle = "星光闪钻"
    case full = "幻光全开"

    var id: String { rawValue }
    var isOn: Bool { self != .off }
    var irisAmount: Float { (self == .iris || self == .full) ? 1 : 0 }
    var sparkleAmount: Float { (self == .sparkle || self == .full) ? 1 : 0 }

    /// Pink → yellow → blue → white. Same knots as holo-card-studio.
    static func spectrum(_ t: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var x = t - t.rounded(.down)
        if x < 0 { x += 1 }
        if x < 0.35 {
            let u = x / 0.35
            return (1, 0.32 + 0.53 * u, 0.62 - 0.30 * u)
        }
        if x < 0.70 {
            let u = (x - 0.35) / 0.35
            return (1 - 0.78 * u, 0.85 - 0.23 * u, 0.32 + 0.68 * u)
        }
        let u = (x - 0.70) / 0.30
        return (0.22 + 0.78 * u, 0.62 + 0.38 * u, 1)
    }

    static func spectrumColor(_ t: CGFloat, alpha: CGFloat = 1) -> NSColor {
        let c = spectrum(t)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
}

@MainActor
final class HoloFoilOverlay {
    let layer = CALayer()
    private let film = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let sparkles = CAEmitterLayer()
    private var foil: LivingHoloFoil = .off
    private var strength: Float = 1

    init() {
        layer.masksToBounds = true
        layer.isHidden = true

        film.type = .axial
        film.compositingFilter = "screenBlendMode"
        film.colors = (0...8).map { i in
            LivingHoloFoil.spectrumColor(CGFloat(i) / 8).cgColor
        }

        sheen.compositingFilter = "plusLighter"
        sheen.colors = [
            NSColor.clear.cgColor,
            LivingHoloFoil.spectrumColor(0.12, alpha: 0.95).cgColor,
            NSColor.white.withAlphaComponent(0.85).cgColor,
            LivingHoloFoil.spectrumColor(0.55, alpha: 0.9).cgColor,
            NSColor.clear.cgColor
        ]
        sheen.startPoint = CGPoint(x: 0, y: 0)
        sheen.endPoint = CGPoint(x: 1, y: 1)

        sparkles.emitterShape = .rectangle
        sparkles.compositingFilter = "plusLighter"
        let cell = CAEmitterCell()
        cell.contents = Self.sparkleImage()
        cell.birthRate = 18
        cell.lifetime = 1.6
        cell.velocity = 4
        cell.scale = 0.045
        cell.scaleRange = 0.03
        cell.alphaSpeed = -0.45
        cell.emissionRange = .pi * 2
        cell.color = NSColor(srgbRed: 0.75, green: 0.9, blue: 1, alpha: 1).cgColor
        sparkles.emitterCells = [cell]

        layer.addSublayer(film)
        layer.addSublayer(sheen)
        layer.addSublayer(sparkles)
    }

    func attach(to host: CALayer, bounds: CGRect) {
        if layer.superlayer !== host {
            layer.removeFromSuperlayer()
            host.addSublayer(layer)
        }
        layout(bounds)
    }

    func setFoil(_ foil: LivingHoloFoil, strength: Float) {
        self.foil = foil
        self.strength = max(strength, 0)
        let on = foil.isOn
        layer.isHidden = !on
        layer.opacity = on ? 1 : 0
        let gain = self.strength
        film.isHidden = foil.irisAmount < 0.5
        film.opacity = 0.62 * gain
        sheen.isHidden = foil.irisAmount < 0.5
        sheen.opacity = 0.8 * gain
        sparkles.isHidden = foil.sparkleAmount < 0.5
        sparkles.opacity = 0.95 * gain
        sparkles.birthRate = foil.sparkleAmount < 0.5 ? 0 : 1
        if on {
            restartAnimations()
        } else {
            film.removeAllAnimations()
            sheen.removeAllAnimations()
        }
    }

    func setPointer(nx: Float, ny: Float, idle: Bool) {
        let ox = CGFloat(nx) * 0.42
        let oy = CGFloat(ny) * 0.28
        CATransaction.begin()
        CATransaction.setDisableActions(idle)
        CATransaction.setAnimationDuration(idle ? 0 : 0.18)
        film.startPoint = CGPoint(x: ox, y: oy)
        film.endPoint = CGPoint(x: 1 + ox, y: 0.72 + oy)
        CATransaction.commit()
        if idle {
            restartFilmCrawl()
        } else {
            film.removeAnimation(forKey: "crawl")
        }
    }

    func layout(_ bounds: CGRect) {
        layer.frame = bounds
        film.frame = bounds
        sheen.frame = bounds
        sparkles.frame = bounds
        sparkles.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        sparkles.emitterSize = bounds.size
        if foil.isOn { restartAnimations() }
    }

    private func restartAnimations() {
        restartFilmCrawl()
        restartSheen()
    }

    private func restartFilmCrawl() {
        film.removeAnimation(forKey: "crawl")
        guard foil.irisAmount > 0.5 else { return }
        let start = CABasicAnimation(keyPath: "startPoint")
        start.fromValue = CGPoint(x: -0.25, y: -0.1)
        start.toValue = CGPoint(x: 0.28, y: 0.22)
        let end = CABasicAnimation(keyPath: "endPoint")
        end.fromValue = CGPoint(x: 0.75, y: 0.55)
        end.toValue = CGPoint(x: 1.28, y: 0.95)
        let group = CAAnimationGroup()
        group.animations = [start, end]
        group.duration = 7.5
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        film.add(group, forKey: "crawl")
    }

    private func restartSheen() {
        sheen.removeAnimation(forKey: "sweep")
        sheen.removeAnimation(forKey: "bloom")
        guard foil.irisAmount > 0.5 else { return }
        sheen.startPoint = CGPoint(x: 0.15, y: 0.1)
        sheen.endPoint = CGPoint(x: 0.85, y: 0.9)
        sheen.add(LivingMotion.pingPong("opacity", from: 0.18, to: 0.62, period: 7.2), forKey: "bloom")
    }

    private static func sparkleImage() -> CGImage {
        let size = 12
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 8, height: 8))
        return ctx.makeImage()!
    }
}
