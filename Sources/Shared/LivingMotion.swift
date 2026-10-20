import AppKit
import ImageIO
import QuartzCore

/// CALayer motions shared by the desktop overlay and the system .saver module.
/// Each photo channel loops as a closed ping-pong, so the cycle never snaps back.
/// Light is a full-frame field that breathes in place — never a traveling bar.
enum LivingMotion {
    static func apply(styleRaw: String, to layer: CALayer, glow: CAGradientLayer?, gain: CGFloat) {
        glow?.removeAllAnimations()
        glow?.opacity = 0
        pinGlow(glow)
        layer.removeAnimation(forKey: "living.scale")
        layer.removeAnimation(forKey: "living.x")
        layer.removeAnimation(forKey: "living.y")
        layer.removeAnimation(forKey: "living.rot")
        layer.removeAnimation(forKey: "living.orbit")
        layer.removeAnimation(forKey: "living.opacity")
        layer.removeAnimation(forKey: "living")

        let style = styleRaw == "随机氛围" ? randomStyleRaw() : styleRaw
        let amp = max(gain, 0.35)
        let tempo = 1.0 / (0.56 + 0.44 * Double(min(amp, 2.4)))

        func lift(_ value: Double) -> Double { 1 + (value - 1) * Double(amp) }
        func beat(_ seconds: CFTimeInterval) -> CFTimeInterval { max(seconds * tempo, 0.2) }
        func slide(_ value: CGFloat) -> CGFloat { value * amp }

        switch style {
        case "缓缓推镜":
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.08), period: beat(32)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-22), to: slide(22), period: beat(28)), forKey: "living.x")
            layer.add(pingPong("transform.translation.y", from: slide(14), to: slide(-14), period: beat(36)), forKey: "living.y")
        case "呼吸缩放":
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.07), period: beat(12)), forKey: "living.scale")
        case "轻柔平移":
            layer.add(pingPong("transform.scale", from: lift(1.055), to: lift(1.08), period: beat(22)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-30), to: slide(30), period: beat(26), linear: true), forKey: "living.x")
        case "光影流转":
            layer.add(pingPong("transform.scale", from: lift(1.02), to: lift(1.075), period: beat(18)), forKey: "living.scale")
            bloomLight(glow, period: beat(16))
        case "电影横移":
            layer.add(pingPong("transform.scale", from: lift(1.1), to: lift(1.14), period: beat(36)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-48), to: slide(48), period: beat(40), linear: true), forKey: "living.x")
        case "悬浮动感":
            layer.add(pingPong("transform.scale", from: lift(1.04), to: lift(1.09), period: beat(22)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-20), to: slide(20), period: beat(20)), forKey: "living.x")
            layer.add(pingPong("transform.translation.y", from: slide(-14), to: slide(14), period: beat(26)), forKey: "living.y")
        case "薄雾呼吸":
            layer.add(pingPong("transform.scale", from: lift(1.03), to: lift(1.08), period: beat(16)), forKey: "living.scale")
            layer.add(pingPong("opacity", from: 0.88, to: 1.0, period: beat(14)), forKey: "living.opacity")
        case "微微倾侧":
            layer.add(pingPong("transform.rotation.z", from: -0.02, to: 0.02, period: beat(22)), forKey: "living.rot")
            layer.add(pingPong("transform.scale", from: lift(1.07), to: lift(1.11), period: beat(22)), forKey: "living.scale")
        case "追光扫过":
            layer.add(pingPong("transform.scale", from: lift(1.03), to: lift(1.07), period: beat(20)), forKey: "living.scale")
            bloomLight(glow, period: beat(18), amount: 0.2, center: CGPoint(x: 0.5, y: 0.28))
        case "环绕游移":
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: slide(-18), y: slide(-12), width: slide(36), height: slide(24)))
            let orbit = CAKeyframeAnimation(keyPath: "transform.translation")
            orbit.path = path
            orbit.duration = beat(24)
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            orbit.rotationMode = .none
            orbit.isRemovedOnCompletion = false
            orbit.fillMode = .forwards
            layer.add(orbit, forKey: "living.orbit")
            layer.add(pingPong("transform.scale", from: lift(1.06), to: lift(1.1), period: beat(24)), forKey: "living.scale")
        case "涟漪起伏":
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.08), period: beat(10)), forKey: "living.scale")
            layer.add(pingPong("opacity", from: 0.9, to: 1.0, period: beat(10)), forKey: "living.opacity")
        case "脉动推进":
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.1), period: beat(14)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.y", from: slide(6), to: slide(-12), period: beat(14)), forKey: "living.y")
        case "波纹视差":
            layer.add(pingPong("transform.scale", from: lift(1.04), to: lift(1.11), period: beat(20)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-26), to: slide(26), period: beat(16)), forKey: "living.x")
            layer.add(pingPong("transform.translation.y", from: slide(12), to: slide(-16), period: beat(22)), forKey: "living.y")
        case "对角缓移":
            layer.add(pingPong("transform.scale", from: lift(1.07), to: lift(1.12), period: beat(30)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-38), to: slide(38), period: beat(30), linear: true), forKey: "living.x")
            layer.add(pingPong("transform.translation.y", from: slide(-22), to: slide(22), period: beat(30), linear: true), forKey: "living.y")
        case "高光呼吸":
            layer.add(pingPong("transform.scale", from: lift(1.02), to: lift(1.09), period: beat(14)), forKey: "living.scale")
            layer.add(pingPong("opacity", from: 0.9, to: 1.0, period: beat(11)), forKey: "living.opacity")
            bloomLight(glow, period: beat(11), amount: 0.24)
        case "斜向扫光":
            layer.add(pingPong("transform.scale", from: lift(1.04), to: lift(1.08), period: beat(20)), forKey: "living.scale")
            skyGrade(glow, period: beat(18), diagonal: true)
        case "脉动漂移":
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.1), period: beat(15)), forKey: "living.scale")
            layer.add(pingPong("transform.translation.x", from: slide(-16), to: slide(28), period: beat(20)), forKey: "living.x")
            layer.add(pingPong("transform.translation.y", from: slide(8), to: slide(-14), period: beat(18)), forKey: "living.y")
        case "暗调微闪":
            layer.add(pingPong("transform.scale", from: lift(1.04), to: lift(1.08), period: beat(12)), forKey: "living.scale")
            layer.add(pingPong("opacity", from: 0.93, to: 1.0, period: beat(6)), forKey: "living.opacity")
        case "随机游走":
            let seed = UInt64.random(in: 1...UInt64.max)
            layer.add(
                wander("transform.scale", low: lift(1.055), high: lift(1.12), steps: 6, period: beat(38), seed: seed),
                forKey: "living.scale"
            )
            layer.add(
                wander("transform.translation.x", low: Double(slide(-28)), high: Double(slide(28)), steps: 7, period: beat(44), seed: seed &+ 17),
                forKey: "living.x"
            )
            layer.add(
                wander("transform.translation.y", low: Double(slide(-16)), high: Double(slide(16)), steps: 5, period: beat(31), seed: seed &+ 41),
                forKey: "living.y"
            )
        default:
            layer.add(pingPong("transform.scale", from: lift(1.0), to: lift(1.07), period: beat(12)), forKey: "living.scale")
        }
    }

    static func cgImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    private static func randomStyleRaw() -> String {
        [
            "缓缓推镜", "呼吸缩放", "轻柔平移", "光影流转", "电影横移", "悬浮动感",
            "薄雾呼吸", "微微倾侧", "追光扫过", "环绕游移", "涟漪起伏", "脉动推进",
            "波纹视差", "对角缓移", "高光呼吸", "斜向扫光", "脉动漂移", "暗调微闪", "随机游走"
        ].randomElement() ?? "缓缓推镜"
    }

    /// Light layer must cover the photo. A half-width bar is the traveling curtain.
    private static func pinGlow(_ glow: CAGradientLayer?) {
        guard let glow, let bounds = glow.superlayer?.bounds, bounds.width > 1, bounds.height > 1 else { return }
        glow.frame = bounds
        glow.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glow.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// Soft sun behind the scene. Radius and brightness change; the layer does not travel.
    private static func bloomLight(
        _ glow: CAGradientLayer?,
        period: CFTimeInterval,
        amount: CGFloat = 0.18,
        center: CGPoint = CGPoint(x: 0.52, y: 0.38)
    ) {
        guard let glow else { return }
        pinGlow(glow)
        glow.type = .radial
        glow.startPoint = center
        glow.endPoint = CGPoint(x: center.x + 0.62, y: center.y + 0.42)
        glow.colors = [
            NSColor.white.withAlphaComponent(amount).cgColor,
            NSColor.white.withAlphaComponent(amount * 0.28).cgColor,
            NSColor.clear.cgColor
        ]
        glow.locations = [0, 0.42, 1] as [NSNumber]
        glow.opacity = 1
        glow.add(pingPong("opacity", from: 0.28, to: 0.78, period: period), forKey: "bloom")
        let radius = CAKeyframeAnimation(keyPath: "endPoint")
        radius.values = [
            CGPoint(x: center.x + 0.52, y: center.y + 0.34),
            CGPoint(x: center.x + 0.74, y: center.y + 0.52),
            CGPoint(x: center.x + 0.52, y: center.y + 0.34)
        ]
        radius.keyTimes = [0, 0.5, 1] as [NSNumber]
        radius.duration = max(period * 1.15, 8)
        radius.repeatCount = .infinity
        radius.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        radius.isRemovedOnCompletion = false
        radius.fillMode = .forwards
        glow.add(radius, forKey: "bloom.radius")
    }

    /// Full-frame sky grade. The wash stays on the whole picture; only brightness turns.
    private static func skyGrade(_ glow: CAGradientLayer?, period: CFTimeInterval, diagonal: Bool) {
        guard let glow else { return }
        pinGlow(glow)
        glow.type = .axial
        glow.startPoint = diagonal ? CGPoint(x: 0.12, y: 0.08) : CGPoint(x: 0.5, y: 0)
        glow.endPoint = diagonal ? CGPoint(x: 0.88, y: 0.92) : CGPoint(x: 0.5, y: 1)
        glow.colors = [
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.06).cgColor
        ]
        glow.locations = [0, 0.55, 1] as [NSNumber]
        glow.opacity = 1
        glow.add(pingPong("opacity", from: 0.32, to: 0.8, period: period), forKey: "bloom")
    }

    /// Closed random walk. First value equals last, so looping does not hitch.
    /// Scale/move stay inside `low...high`; each apply() with a new seed draws a new path.
    static func wander(
        _ keyPath: String,
        low: Double,
        high: Double,
        steps: Int,
        period: CFTimeInterval,
        seed: UInt64
    ) -> CAKeyframeAnimation {
        let lo = min(low, high)
        let hi = max(low, high)
        let count = max(steps, 4)
        var rng = WanderRNG(seed: seed == 0 ? 1 : seed)
        var points: [Double] = []
        var current = lo + rng.unit() * (hi - lo)
        points.append(current)
        for _ in 1..<count {
            let target = lo + rng.unit() * (hi - lo)
            let mix = 0.32 + rng.unit() * 0.56
            current = min(hi, max(lo, current + (target - current) * mix))
            points.append(current)
        }
        points.append(points[0])

        var times: [NSNumber] = [0]
        var cursor = 0.0
        var spans: [Double] = []
        for _ in 0..<(points.count - 1) {
            spans.append(0.55 + rng.unit() * 0.9)
        }
        let total = spans.reduce(0, +)
        for span in spans.dropLast() {
            cursor += span / total
            times.append(NSNumber(value: min(max(cursor, 0.02), 0.98)))
        }
        times.append(1)

        let anim = CAKeyframeAnimation(keyPath: keyPath)
        anim.values = points
        anim.keyTimes = times
        anim.duration = max(period, 0.2)
        anim.repeatCount = .infinity
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.timingFunctions = Array(repeating: ease, count: points.count - 1)
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        return anim
    }

    /// Full cycle starts and ends on the same value, so `repeatCount = infinity` does not hitch.
    static func pingPong(
        _ keyPath: String,
        from: Double,
        to: Double,
        period: CFTimeInterval,
        linear: Bool = false
    ) -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: keyPath)
        anim.values = [from, to, from]
        anim.keyTimes = [0, 0.5, 1] as [NSNumber]
        anim.duration = max(period, 0.2)
        anim.repeatCount = .infinity
        let ease = CAMediaTimingFunction(name: linear ? .linear : .easeInEaseOut)
        anim.timingFunctions = [ease, ease]
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        return anim
    }
}

private struct WanderRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func unit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Double(state >> 11) / Double(1 << 53)
    }
}
