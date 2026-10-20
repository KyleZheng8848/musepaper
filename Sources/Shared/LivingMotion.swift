import AppKit
import ImageIO
import QuartzCore

/// CALayer motions shared by the desktop overlay and the system .saver module.
enum LivingMotion {
    static func apply(styleRaw: String, to layer: CALayer, glow: CAGradientLayer?, gain: CGFloat) {
        glow?.removeAllAnimations()
        glow?.opacity = 0
        let style = styleRaw == "随机氛围" ? randomStyleRaw() : styleRaw

        switch style {
        case "缓缓推镜":
            addGroup(to: layer, duration: 36, animations: [
                scale(from: 1.0, to: 1.08, duration: 28),
                translateX(from: -16, to: 16, duration: 32, gain: gain),
                translateY(from: 10, to: -10, duration: 36, gain: gain)
            ])
        case "呼吸缩放":
            layer.add(scale(from: 1.0, to: 1.045, duration: 8), forKey: "living")
        case "轻柔平移":
            addGroup(to: layer, duration: 24, animations: [
                translateX(from: -22, to: 22, duration: 24, gain: gain),
                scale(from: 1.06, to: 1.06, duration: 24)
            ])
        case "光影流转":
            layer.add(scale(from: 1.02, to: 1.06, duration: 18), forKey: "living")
            addSweep(glow)
        case "电影横移":
            addGroup(to: layer, duration: 40, animations: [
                scale(from: 1.1, to: 1.1, duration: 40),
                translateX(from: -36, to: 36, duration: 40, gain: gain)
            ])
        case "悬浮动感":
            addGroup(to: layer, duration: 30, animations: [
                scale(from: 1.04, to: 1.07, duration: 30),
                translateX(from: -14, to: 14, duration: 22, gain: gain),
                translateY(from: -10, to: 10, duration: 26, gain: gain)
            ])
        case "薄雾呼吸":
            addGroup(to: layer, duration: 16, animations: [
                scale(from: 1.03, to: 1.06, duration: 16),
                opacity(from: 0.88, to: 1.0, duration: 10)
            ])
        case "微微倾侧":
            let rot = CABasicAnimation(keyPath: "transform.rotation.z")
            rot.fromValue = -0.012
            rot.toValue = 0.012
            rot.duration = 20
            rot.autoreverses = true
            rot.repeatCount = .infinity
            rot.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            addGroup(to: layer, duration: 20, animations: [
                rot,
                scale(from: 1.08, to: 1.08, duration: 20)
            ])
        case "追光扫过":
            layer.add(scale(from: 1.03, to: 1.05, duration: 20), forKey: "living")
            if let glow {
                glow.colors = [
                    NSColor.clear.cgColor,
                    NSColor.white.withAlphaComponent(0.16).cgColor,
                    NSColor.clear.cgColor
                ]
                glow.startPoint = CGPoint(x: 0.5, y: 0)
                glow.endPoint = CGPoint(x: 0.5, y: 1)
                addSweep(glow, vertical: true)
            }
        case "环绕游移":
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -12 * gain, y: -8 * gain, width: 24 * gain, height: 16 * gain))
            let orbit = CAKeyframeAnimation(keyPath: "transform.translation")
            orbit.path = path
            orbit.duration = 28
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            orbit.rotationMode = .none
            addGroup(to: layer, duration: 28, animations: [
                orbit,
                scale(from: 1.07, to: 1.07, duration: 28)
            ])
        case "涟漪起伏":
            addGroup(to: layer, duration: 12, animations: [
                scale(from: 1.0, to: 1.055, duration: 6),
                opacity(from: 1.0, to: 0.92, duration: 6)
            ])
        case "脉动推进":
            addGroup(to: layer, duration: 14, animations: [
                scale(from: 1.0, to: 1.1, duration: 7),
                translateY(from: 0, to: -8, duration: 7, gain: gain)
            ])
        case "波纹视差":
            addGroup(to: layer, duration: 22, animations: [
                scale(from: 1.04, to: 1.09, duration: 22),
                translateX(from: -18, to: 18, duration: 14, gain: gain),
                translateY(from: 8, to: -12, duration: 18, gain: gain)
            ])
        case "对角缓移":
            addGroup(to: layer, duration: 34, animations: [
                scale(from: 1.08, to: 1.08, duration: 34),
                translateX(from: -28, to: 28, duration: 34, gain: gain),
                translateY(from: -16, to: 16, duration: 34, gain: gain)
            ])
        case "高光呼吸":
            addGroup(to: layer, duration: 14, animations: [
                scale(from: 1.02, to: 1.07, duration: 14),
                opacity(from: 0.9, to: 1.0, duration: 7)
            ])
            if let glow {
                glow.colors = [
                    NSColor.clear.cgColor,
                    NSColor.white.withAlphaComponent(0.2).cgColor,
                    NSColor.clear.cgColor
                ]
                glow.opacity = 1
                glow.add(opacity(from: 0.15, to: 0.55, duration: 7), forKey: "bloom")
            }
        case "斜向扫光":
            layer.add(scale(from: 1.05, to: 1.05, duration: 20), forKey: "living")
            if let glow {
                glow.colors = [
                    NSColor.clear.cgColor,
                    NSColor.white.withAlphaComponent(0.18).cgColor,
                    NSColor.clear.cgColor
                ]
                glow.startPoint = CGPoint(x: 0, y: 0)
                glow.endPoint = CGPoint(x: 1, y: 1)
                addSweep(glow)
            }
        case "脉动漂移":
            addGroup(to: layer, duration: 18, animations: [
                scale(from: 1.0, to: 1.08, duration: 9),
                translateX(from: -12, to: 20, duration: 18, gain: gain),
                translateY(from: 6, to: -10, duration: 15, gain: gain)
            ])
        case "暗调微闪":
            addGroup(to: layer, duration: 10, animations: [
                scale(from: 1.05, to: 1.06, duration: 10),
                opacity(from: 0.94, to: 1.0, duration: 1.6)
            ])
        default:
            layer.add(scale(from: 1.0, to: 1.045, duration: 8), forKey: "living")
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
            "波纹视差", "对角缓移", "高光呼吸", "斜向扫光", "脉动漂移", "暗调微闪"
        ].randomElement() ?? "缓缓推镜"
    }

    private static func addSweep(_ glow: CAGradientLayer?, vertical: Bool = false) {
        guard let glow else { return }
        glow.opacity = 1
        let width = glow.superlayer?.bounds.width ?? 1200
        let height = glow.superlayer?.bounds.height ?? 800
        if vertical {
            glow.frame = CGRect(x: 0, y: -height * 0.4, width: width, height: height * 0.45)
            let sweep = CABasicAnimation(keyPath: "position.y")
            sweep.fromValue = -height * 0.2
            sweep.toValue = height * 1.2
            sweep.duration = 16
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(sweep, forKey: "sweep")
        } else {
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -width * 0.2
            sweep.toValue = width * 1.2
            sweep.duration = 14
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.add(sweep, forKey: "sweep")
        }
    }

    private static func addGroup(to layer: CALayer, duration: CFTimeInterval, animations: [CAAnimation]) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.repeatCount = .infinity
        layer.add(group, forKey: "living")
    }

    private static func scale(from: CGFloat, to: CGFloat, duration: CFTimeInterval) -> CABasicAnimation {
        animate("transform.scale", from: from, to: to, duration: duration)
    }

    private static func translateX(from: CGFloat, to: CGFloat, duration: CFTimeInterval, gain: CGFloat) -> CABasicAnimation {
        animate("transform.translation.x", from: from * gain, to: to * gain, duration: duration)
    }

    private static func translateY(from: CGFloat, to: CGFloat, duration: CFTimeInterval, gain: CGFloat) -> CABasicAnimation {
        animate("transform.translation.y", from: from * gain, to: to * gain, duration: duration)
    }

    private static func opacity(from: Float, to: Float, duration: CFTimeInterval) -> CABasicAnimation {
        animate("opacity", from: from, to: to, duration: duration)
    }

    private static func animate(_ key: String, from: Any, to: Any, duration: CFTimeInterval) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: key)
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return anim
    }
}
