import Foundation
import QuartzCore

@main
enum LivingMotionSmoke {
    static func main() throws {
        let ping = LivingMotion.pingPong("transform.scale", from: 1, to: 1.08, period: 16)
        let pingValues = (ping.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
        guard pingValues.first == pingValues.last, pingValues.count == 3 else {
            throw Fail("ping-must-close")
        }

        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let photo = CALayer()
        photo.frame = host.bounds
        host.addSublayer(photo)
        let glow = CAGradientLayer()
        glow.frame = CGRect(x: -800, y: 0, width: 704, height: 800)
        host.addSublayer(glow)

        for name in ["光影流转", "追光扫过", "斜向扫光", "高光呼吸"] {
            LivingMotion.apply(styleRaw: name, to: photo, glow: glow, gain: 1.7)
            if glow.frame != host.bounds { throw Fail("\(name) glow-not-full-frame \(glow.frame)") }
            if glow.animation(forKey: "sweep") != nil { throw Fail("\(name) sliding-curtain") }
            if glow.animation(forKey: "orbit") != nil { throw Fail("\(name) orbit-curtain") }
            if (glow.animationKeys() ?? []).contains(where: { $0.contains("position") }) {
                throw Fail("\(name) position-travel")
            }
        }

        LivingMotion.apply(styleRaw: "电影横移", to: photo, glow: glow, gain: 1.7)
        guard photo.animation(forKey: "living.x") != nil else { throw Fail("cinema-must-pan") }

        let walk = LivingMotion.wander("transform.scale", low: 1.05, high: 1.12, steps: 6, period: 36, seed: 7)
        let walkValues = (walk.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
        guard walkValues.count > 4, walkValues.first == walkValues.last else { throw Fail("wander-must-close") }
        guard walkValues.allSatisfy({ $0 >= 1.05 && $0 <= 1.12 }) else { throw Fail("wander-out-of-range") }
        LivingMotion.apply(styleRaw: "随机游走", to: photo, glow: glow, gain: 1.7)
        guard photo.animation(forKey: "living.scale") != nil, photo.animation(forKey: "living.x") != nil else {
            throw Fail("wander-must-move")
        }

        print("LIVING_MOTION_SMOKE_OK")
    }

    struct Fail: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
