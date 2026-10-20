import Foundation

/// Limits parallel API work and shrinks the limit when the provider signals pressure
/// (429 / timeout / congestion). Slowly climbs back after sustained success.
actor AdaptiveConcurrencyGate {
    private var limit: Int
    private let minimum: Int
    private let maximum: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var consecutivePressure = 0
    private var consecutiveSuccess = 0

    init(initial: Int, minimum: Int = 1, maximum: Int = 8) {
        let lo = max(1, minimum)
        let hi = max(lo, maximum)
        self.minimum = lo
        self.maximum = hi
        self.limit = min(max(initial, lo), hi)
    }

    var currentLimit: Int { limit }
    var activeCount: Int { inFlight }

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await work()
            release(outcome: .success)
            return value
        } catch {
            release(outcome: .failure(error))
            throw error
        }
    }

    /// Same as `run`, but on pressure: shrink concurrency, brief backoff, one retry.
    func runWithPressureRetry<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await run(work)
        } catch {
            guard Self.isPressure(error) else { throw error }
            let delay = Self.retryDelayNanoseconds(for: error)
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            return try await run(work)
        }
    }

    private enum Outcome {
        case success
        case failure(Error)
    }

    private func acquire() async {
        while inFlight >= limit {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
        inFlight += 1
    }

    private func release(outcome: Outcome) {
        switch outcome {
        case .success:
            consecutivePressure = 0
            consecutiveSuccess += 1
            if consecutiveSuccess >= 4, limit < maximum {
                limit += 1
                consecutiveSuccess = 0
            }
        case .failure(let error):
            consecutiveSuccess = 0
            if Self.isPressure(error) {
                consecutivePressure += 1
                if limit > minimum {
                    limit = max(minimum, limit - 1)
                }
            }
        }
        inFlight = max(0, inFlight - 1)
        wakeWaitersIfPossible()
    }

    private func wakeWaitersIfPossible() {
        while !waiters.isEmpty, inFlight < limit {
            waiters.removeFirst().resume()
        }
    }

    static func isPressure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let muse = error as? MusepaperError {
            switch muse {
            case .rateLimited:
                return true
            case .networkFailed(let message):
                return messageSuggestsPressure(message)
            case .generationFailed(let message), .invalidResponse(let message):
                return messageSuggestsPressure(message)
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let codes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorResourceUnavailable,
            ]
            if codes.contains(ns.code) { return true }
        }
        return messageSuggestsPressure(error.localizedDescription)
    }

    static func retryDelayNanoseconds(for error: Error) -> UInt64 {
        if case let MusepaperError.rateLimited(retryAfter) = error,
           let raw = retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines),
           let seconds = Double(raw), seconds > 0 {
            return UInt64(min(seconds, 15) * 1_000_000_000)
        }
        return 600_000_000 // 0.6s
    }

    private static func messageSuggestsPressure(_ message: String) -> Bool {
        let m = message.lowercased()
        let needles = [
            "429", "rate limit", "rate_limit", "too many", "tpm", "rpm",
            "timeout", "timed out", "overloaded", "capacity", "congest",
            "频繁", "过载", "繁忙", "稍后重试", "too many requests",
        ]
        return needles.contains { m.contains($0) }
    }
}

/// Serializes PromptComposer.distinguish across parallel polish workers.
actor PromptDeduper {
    private var used = Set<String>()
    private let composer = PromptComposer()

    func distinguish(_ prompt: String, index: Int, seed: Int, core: String) -> String {
        composer.distinguish(prompt, used: &used, index: index, seed: seed, core: core)
    }
}
