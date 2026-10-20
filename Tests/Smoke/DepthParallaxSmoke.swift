import Foundation
import QuartzCore

@main
enum DepthParallaxSmoke {
    @MainActor
    static func main() throws {
        guard LivingDepthStyle.off.isOn == false else { throw Fail("off-must-be-off") }
        guard LivingDepthStyle.relief.isOn else { throw Fail("relief-must-be-on") }

        let pack = LivingCardCutout.ovalPack(size: CGSize(width: 240, height: 160))
        guard let plate = LivingReliefStamp.plate(mask: pack.mid, strength: 1) else {
            throw Fail("plate-must-render")
        }
        guard plate.width > 8, plate.height > 8 else { throw Fail("plate-too-small") }

        let host = CALayer()
        let image = CALayer()
        host.addSublayer(image)
        let overlay = LivingDepthOverlay()
        overlay.attach(to: host, imageLayer: image, bounds: CGRect(x: 0, y: 0, width: 1280, height: 800))
        overlay.setStyle(.relief, gain: 1)
        guard overlay.front.isHidden == false else { throw Fail("relief-must-unhide") }
        guard image.isHidden == false else { throw Fail("photo-must-stay") }
        guard overlay.front.superlayer === image else { throw Fail("relief-must-ride-photo") }

        overlay.setStyle(.off, gain: 1)
        guard overlay.front.isHidden, image.isHidden == false else {
            throw Fail("off-must-keep-photo")
        }
        print("DEPTH_PARALLAX_SMOKE_OK")
    }

    struct Fail: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
