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
        XCTAssertEqual(await gate.currentLimit, 3)
        do {
            _ = try await gate.run { () -> Int in
                throw MusepaperError.rateLimited(retryAfter: nil)
            }
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(AdaptiveConcurrencyGate.isPressure(error))
        }
        XCTAssertEqual(await gate.currentLimit, 2)
    }

    func testCapsParallelism() async throws {
        let gate = AdaptiveConcurrencyGate(initial: 2, minimum: 1, maximum: 2)
        let lock = NSLock()
        var peak = 0
        var current = 0

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    _ = try? await gate.run {
                        lock.lock(); current += 1; peak = max(peak, current); lock.unlock()
                        try await Task.sleep(nanoseconds: 80_000_000)
                        lock.lock(); current -= 1; lock.unlock()
                        return true
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertEqual(await gate.activeCount, 0)
    }
}
