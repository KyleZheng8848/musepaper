import Foundation

@main
enum HoloFoilSmoke {
    @MainActor
    static func main() throws {
        guard LivingHoloFoil.off.isOn == false else { throw Fail("off-must-be-off") }
        guard LivingHoloFoil.full.isOn else { throw Fail("full-must-be-on") }
        guard LivingHoloFoil.iris.irisAmount == 1, LivingHoloFoil.iris.sparkleAmount == 0 else {
            throw Fail("iris-amounts")
        }
        let pink = LivingHoloFoil.spectrum(0)
        guard abs(pink.r - 1) < 0.02, abs(pink.g - 0.32) < 0.02 else {
            throw Fail("spectrum-pink \(pink)")
        }
        let overlay = HoloFoilOverlay()
        overlay.setFoil(.full, strength: 1)
        overlay.layout(CGRect(x: 0, y: 0, width: 800, height: 500))
        guard overlay.layer.isHidden == false else { throw Fail("full-must-unhide") }
        overlay.setFoil(.off, strength: 1)
        guard overlay.layer.isHidden else { throw Fail("off-must-hide") }
        print("HOLO_FOIL_SMOKE_OK")
    }

    struct Fail: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }
}
