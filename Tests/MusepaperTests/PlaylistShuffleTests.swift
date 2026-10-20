import XCTest
@testable import Musepaper

final class PlaylistShuffleTests: XCTestCase {
    func testShuffleBagDoesNotRepeatUntilExhausted() {
        let pool = (0..<8).map { _ in UUID() }
        var knownPool: [UUID] = []
        var queue: [UUID] = []
        var seen: [UUID] = []
        var last: UUID?
        for _ in 0..<pool.count {
            var avoid = Set<UUID>()
            if let last { avoid.insert(last) }
            let next = PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool, avoiding: avoid)
            let id = try! XCTUnwrap(next)
            XCTAssertFalse(seen.contains(id), "repeated \(id) before the bag emptied: \(seen)")
            seen.append(id)
            last = id
        }
        XCTAssertEqual(Set(seen).count, pool.count)
        XCTAssertTrue(queue.isEmpty)
    }

    func testShuffleBagRefillsAfterAFullPass() {
        let pool = (0..<5).map { _ in UUID() }
        var knownPool: [UUID] = []
        var queue: [UUID] = []
        var firstPass: [UUID] = []
        for _ in 0..<pool.count {
            firstPass.append(try! XCTUnwrap(PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool, avoiding: [])))
        }
        XCTAssertEqual(Set(firstPass).count, pool.count)
        let again = try! XCTUnwrap(PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool, avoiding: []))
        XCTAssertTrue(pool.contains(again))
        XCTAssertEqual(queue.count, pool.count - 1)
    }

    func testShuffleBagSkipsCurrentAndUsedIDsThisRound() {
        let pool = (0..<4).map { _ in UUID() }
        var knownPool: [UUID] = []
        var queue = pool
        let current = pool[0]
        let used = Set([pool[1]])
        let next = try! XCTUnwrap(PlaylistShuffle.takeNext(poolIDs: pool, queue: &queue, knownPool: &knownPool, avoiding: used.union([current])))
        XCTAssertNotEqual(next, current)
        XCTAssertNotEqual(next, pool[1])
        XCTAssertFalse(queue.contains(next))
    }

    func testShuffleBagDropsStaleIDsAndAddsNewcomers() {
        let old = UUID()
        let keep = UUID()
        let fresh = UUID()
        var knownPool = [old, keep]
        var queue = [old, keep]
        let next = try! XCTUnwrap(PlaylistShuffle.takeNext(poolIDs: [keep, fresh], queue: &queue, knownPool: &knownPool, avoiding: []))
        XCTAssertTrue([keep, fresh].contains(next))
        XCTAssertFalse(queue.contains(old))
        XCTAssertEqual(Set([next] + queue), Set([keep, fresh]))
    }

    func testLegacyPlaylistJSONHasNilShuffleQueue() throws {
        let playlist = WallpaperPlaylist(name: "旧随机", order: .shuffle)
        XCTAssertNil(playlist.shuffleQueueIDs)
        let encoded = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(WallpaperPlaylist.self, from: encoded)
        XCTAssertNil(decoded.shuffleQueueIDs)
    }

    func testShuffleQueueRoundTrips() throws {
        let ids = [UUID(), UUID()]
        let playlist = WallpaperPlaylist(name: "袋", order: .shuffle, shuffleQueueIDs: ids)
        let encoded = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(WallpaperPlaylist.self, from: encoded)
        XCTAssertEqual(decoded.shuffleQueueIDs, ids)
    }
}
