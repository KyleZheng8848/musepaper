import CoreGraphics
import QuartzCore
import XCTest
@testable import Musepaper

final class LivingHoloFoilTests: XCTestCase {
    func testDefaultIsOffAndNotAMotionStyle() {
        XCTAssertEqual(AppSettings().livingHoloFoil, nil)
        XCTAssertEqual(LivingHoloFoil.off.isOn, false)
        XCTAssertTrue(LivingHoloFoil.full.isOn)
        XCTAssertFalse(LivingWallpaperStyle.allCases.map(\.rawValue).contains("幻光全开"))
        XCTAssertFalse(LivingWallpaperStyle.motionCases.map(\.rawValue).contains("虹膜镭射"))
        XCTAssertEqual(LivingWallpaperStyle.motionCases.count, LivingWallpaperStyle.allCases.count - 1)
    }

    func testSpectrumFollowsHoloCardStudioKnots() {
        let pink = LivingHoloFoil.spectrum(0)
        XCTAssertEqual(pink.r, 1, accuracy: 0.02)
        XCTAssertEqual(pink.g, 0.32, accuracy: 0.02)
        XCTAssertEqual(pink.b, 0.62, accuracy: 0.02)

        let yellow = LivingHoloFoil.spectrum(0.35)
        XCTAssertEqual(yellow.r, 1, accuracy: 0.02)
        XCTAssertEqual(yellow.g, 0.85, accuracy: 0.02)
        XCTAssertEqual(yellow.b, 0.32, accuracy: 0.02)

        let blue = LivingHoloFoil.spectrum(0.70)
        XCTAssertEqual(blue.r, 0.22, accuracy: 0.02)
        XCTAssertEqual(blue.g, 0.62, accuracy: 0.02)
        XCTAssertEqual(blue.b, 1, accuracy: 0.02)
    }

    func testDepthDefaultOffAndNotAMotionStyle() {
        XCTAssertEqual(AppSettings().livingDepthStyle, nil)
        XCTAssertFalse(LivingDepthStyle.off.isOn)
        XCTAssertTrue(LivingDepthStyle.relief.isOn)
        XCTAssertFalse(LivingWallpaperStyle.allCases.map(\.rawValue).contains("浮雕"))
        XCTAssertFalse(LivingWallpaperStyle.allCases.map(\.rawValue).contains("深度视差"))
        XCTAssertFalse(LivingWallpaperStyle.allCases.map(\.rawValue).contains("贺卡分层"))
        XCTAssertFalse(LivingWallpaperStyle.motionCases.map(\.rawValue).contains("浮雕"))
    }

    func testCardCutoutOvalsAreStackedSheets() {
        let pack = LivingCardCutout.ovalPack(size: CGSize(width: 240, height: 160))
        let subject = LivingCardCutout.opaqueFraction(pack.subject)
        let lift = LivingCardCutout.opaqueFraction(pack.lift)
        let mid = LivingCardCutout.opaqueFraction(pack.mid)
        XCTAssertGreaterThan(subject, 0.08)
        XCTAssertLessThan(subject, lift)
        XCTAssertLessThan(lift, mid)
        XCTAssertLessThan(mid, 0.72)
        XCTAssertFalse(pack.usedSubject)
        let huge = LivingCardCutout.ovalPack(size: CGSize(width: 5120, height: 2880))
        XCTAssertLessThanOrEqual(huge.subject.width, Int(LivingCardCutout.maskMaxEdge))
        XCTAssertLessThanOrEqual(huge.mid.height, Int(LivingCardCutout.maskMaxEdge))
    }

    func testReliefPlateRendersFromMask() {
        let pack = LivingCardCutout.ovalPack(size: CGSize(width: 240, height: 160))
        let plate = LivingReliefStamp.plate(mask: pack.mid, strength: 1)
        XCTAssertNotNil(plate)
        XCTAssertGreaterThan(plate?.width ?? 0, 8)
    }

    @MainActor
    func testReliefRidesPhotoAndDoesNotHideIt() {
        let host = CALayer()
        let image = CALayer()
        host.addSublayer(image)
        let overlay = LivingDepthOverlay()
        overlay.attach(to: host, imageLayer: image, bounds: CGRect(x: 0, y: 0, width: 800, height: 500))
        XCTAssertTrue(overlay.front.isHidden)
        XCTAssertFalse(image.isHidden)

        overlay.setStyle(.relief, gain: 1)
        XCTAssertFalse(overlay.front.isHidden)
        XCTAssertFalse(image.isHidden)
        XCTAssertTrue(overlay.front.superlayer === image)

        overlay.setStyle(.off, gain: 1)
        XCTAssertTrue(overlay.front.isHidden)
        XCTAssertFalse(image.isHidden)
    }

    func testLivingMotionPingPongClosesTheLoop() {
        let anim = LivingMotion.pingPong("transform.scale", from: 1.0, to: 1.08, period: 16)
        let values = (anim.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
        XCTAssertEqual(values.first, values.last)
        XCTAssertEqual(anim.repeatCount, .infinity)
        XCTAssertEqual(values.count, 3)
    }

    func testWanderClosesAndStaysInRange() {
        let anim = LivingMotion.wander(
            "transform.translation.x",
            low: -20,
            high: 20,
            steps: 6,
            period: 40,
            seed: 42
        )
        let values = (anim.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
        XCTAssertGreaterThan(values.count, 4)
        XCTAssertEqual(values.first, values.last)
        XCTAssertTrue(values.allSatisfy { $0 >= -20 && $0 <= 20 })
        let unique = Set(values.map { ($0 * 100).rounded() / 100 })
        XCTAssertGreaterThan(unique.count, 2)
        let ping = LivingMotion.wander(
            "transform.translation.x",
            low: -20,
            high: 20,
            steps: 6,
            period: 40,
            seed: 99
        )
        let other = (ping.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue ?? ($0 as? Double) }
        XCTAssertNotEqual(values, other)
    }

    func testWanderStyleMovesScaleAndTranslation() {
        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let photo = CALayer()
        photo.frame = host.bounds
        host.addSublayer(photo)
        LivingMotion.apply(styleRaw: "随机游走", to: photo, glow: nil, gain: 1.7)
        XCTAssertNotNil(photo.animation(forKey: "living.scale"))
        XCTAssertNotNil(photo.animation(forKey: "living.x"))
        XCTAssertNotNil(photo.animation(forKey: "living.y"))
        XCTAssertTrue(LivingWallpaperStyle.allCases.map(\.rawValue).contains("随机游走"))
    }

    func testLightStylesDoNotSlideACurtain() {
        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let photo = CALayer()
        photo.frame = host.bounds
        host.addSublayer(photo)
        let glow = CAGradientLayer()
        glow.frame = CGRect(x: -800, y: 0, width: 700, height: 800)
        host.addSublayer(glow)

        for name in ["光影流转", "追光扫过", "斜向扫光", "高光呼吸"] {
            LivingMotion.apply(styleRaw: name, to: photo, glow: glow, gain: 1.7)
            XCTAssertEqual(glow.frame, host.bounds, name)
            XCTAssertNil(glow.animation(forKey: "sweep"), name)
            XCTAssertNil(glow.animation(forKey: "orbit"), name)
            let keys = Set(glow.animationKeys() ?? [])
            XCTAssertFalse(keys.contains { $0.contains("position") }, name)
        }
    }

    func testAmounts() {
        XCTAssertEqual(LivingHoloFoil.iris.irisAmount, 1)
        XCTAssertEqual(LivingHoloFoil.iris.sparkleAmount, 0)
        XCTAssertEqual(LivingHoloFoil.sparkle.irisAmount, 0)
        XCTAssertEqual(LivingHoloFoil.sparkle.sparkleAmount, 1)
        XCTAssertEqual(LivingHoloFoil.full.irisAmount, 1)
        XCTAssertEqual(LivingHoloFoil.full.sparkleAmount, 1)
    }
}
