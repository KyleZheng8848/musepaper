import XCTest
@testable import Musepaper

final class AdaptiveConcurrencyGateTests: XCTestCase {
    func testPressureDetection() {
        XCTAssertTrue(AdaptiveConcurrencyGate.isPressure(MusepaperError.rateLimited(retryAfter: "2")))
        XCTAssertTrue(AdaptiveConcurrencyGate.isPressure(MusepaperError.networkFailed("request timed out")))
        XCTAssertTrue(AdaptiveConcurrencyGate.isPressure(MusepaperError.generationFailed("HTTP 429 too many requests")))
        XCTAssertFalse(AdaptiveConcurrencyGate.isPressure(MusepaperError.missingAPIKey))
        XCTAssertFalse(AdaptiveConcurrencyGate.isPressure(CancellationError()))
    }

    func testShrinksOnPressure() async throws {
        let gate = AdaptiveConcurrencyGate(initial: 3, minimum: 1, maximum: 3)
        let initialLimit = await gate.currentLimit
        XCTAssertEqual(initialLimit, 3)
        do {
            _ = try await gate.run { () -> Int in
                throw MusepaperError.rateLimited(retryAfter: nil)
            }
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(AdaptiveConcurrencyGate.isPressure(error))
        }
        let reducedLimit = await gate.currentLimit
        XCTAssertEqual(reducedLimit, 2)
    }

    func testCapsParallelism() async throws {
        let gate = AdaptiveConcurrencyGate(initial: 2, minimum: 1, maximum: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    _ = try? await gate.run {
                        await probe.enter()
                        try await Task.sleep(nanoseconds: 80_000_000)
                        await probe.leave()
                        return true
                    }
                }
            }
        }
        let peak = await probe.peak
        let activeCount = await gate.activeCount
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertEqual(activeCount, 0)
    }
}

private actor ConcurrencyProbe {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() { current -= 1 }
}
