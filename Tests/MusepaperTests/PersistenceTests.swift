import Foundation
import XCTest
@testable import Musepaper

final class PersistenceTests: XCTestCase {
    func testRoundTripSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        var snapshot = AppSnapshot()
        snapshot.settings.scheduleEnabled = true
        try await store.save(snapshot)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.settings.scheduleEnabled)
    }

    func testNextFireDateIsInTheFuture() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = 10
        let now = Calendar.current.date(from: components)!
        let next = ScheduleService.nextFireDate(hour: 8, from: now)
        XCTAssertGreaterThan(next, now)
        XCTAssertEqual(Calendar.current.component(.hour, from: next), 8)
        XCTAssertEqual(Calendar.current.component(.minute, from: next), 0)
    }

    func testIntervalNextFireUsesLastProduction() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = 10
        let now = Calendar.current.date(from: components)!
        let last = now.addingTimeInterval(-2 * 3600)
        let next = ScheduleService.nextFireDate(intervalHours: 8, lastProducedAt: last, from: now)
        XCTAssertEqual(next.timeIntervalSince(last), 8 * 3600, accuracy: 1)
    }

    func testWallpaperDisplayChoiceRoundTrips() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        var snapshot = AppSnapshot()
        snapshot.settings.applyToAllDisplays = false
        snapshot.settings.selectedDisplayID = "screen-1"
        try await store.save(snapshot)

        let loaded = try await store.load()
        XCTAssertFalse(loaded.settings.applyToAllDisplays)
        XCTAssertEqual(loaded.settings.selectedDisplayID, "screen-1")
    }

    func testMissingStoreReturnsDefaults() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("missing.json")
        let loaded = try await JSONStore(fileURL: url).load()
        XCTAssertEqual(loaded.channels.count, 1)
    }

    func testUnknownSettingsEnumsAreSanitizedInsteadOfWipingLibrary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("snapshot.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let channelID = UUID().uuidString
        let payload: [String: Any] = [
            "channels": [[
                "id": channelID,
                "name": "霓虹雨巷",
                "essence": "潮湿霓虹",
                "mustInclude": "反光地面",
                "exclude": "文字",
                "palette": "品红",
                "variation": 0.4,
                "requiresApproval": true
            ]],
            "records": [],
            "settings": [
                "desktopClockFace": "海报竖排",
                "livingWallpaperStyle": "不存在的动效",
                "autoApply": false,
                "generateBeforeApplying": true,
                "scheduleEnabled": false,
                "scheduleHour": 8,
                "applyToAllDisplays": true
            ],
            "previousWallpaperPaths": [:],
            "smartCollections": [[
                "id": UUID().uuidString,
                "name": "喜欢霓虹",
                "taskIDs": [],
                "includeTags": ["霓虹"],
                "excludeTags": [],
                "favoritesOnly": true
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: url)

        let loaded = try await JSONStore(fileURL: url).load()
        XCTAssertEqual(loaded.channels.first?.name, "霓虹雨巷")
        XCTAssertEqual(loaded.smartCollections?.first?.name, "喜欢霓虹")
        XCTAssertNil(loaded.settings.desktopClockFace)
        XCTAssertNil(loaded.settings.livingWallpaperStyle)
    }

    func testSaveKeepsRotatingSnapshotBackups() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        var first = AppSnapshot()
        first.channels = [InspirationChannel(name: "一号", essence: "a", mustInclude: "", exclude: "", palette: "", variation: 0.3, requiresApproval: true)]
        try await store.save(first)
        var second = first
        second.channels = [InspirationChannel(name: "二号", essence: "b", mustInclude: "", exclude: "", palette: "", variation: 0.3, requiresApproval: true)]
        try await store.save(second)

        let backups = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Snapshots"),
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(backups.isEmpty)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.channels.first?.name, "二号")
    }

    func testBatchSelectionRoundTrips() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        let selected = UUID()
        var snapshot = AppSnapshot()
        snapshot.batches = [GenerationBatch(
            id: UUID(), seriesID: InspirationChannel.sample.id, recordIDs: [selected],
            selectedRecordID: selected, prompt: "same core, rainy variant", trigger: .scheduled,
            state: .ready, createdAt: Date(), errorMessage: nil
        )]
        try await store.save(snapshot)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.batches?.first?.selectedRecordID, selected)
        XCTAssertEqual(loaded.batches?.first?.trigger, .scheduled)
    }

    func testSeriesReferenceImagesRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        var snapshot = AppSnapshot()
        snapshot.channels = [InspirationChannel(
            name: "雨夜", essence: "潮湿未来城市", coreKeywords: "上海、青蓝霓虹",
            referenceImagePaths: ["/tmp/world.png"]
        )]
        try await store.save(snapshot)

        let loaded = try await store.load()

        XCTAssertEqual(loaded.channels.first?.resolvedReferenceImagePaths, ["/tmp/world.png"])
    }

    func testLegacyPlaylistStillTargetsDesktop() {
        let playlist = WallpaperPlaylist(name: "旧规则")
        XCTAssertTrue(playlist.targetsDesktop)
        XCTAssertEqual(playlist.resolvedPriority, 1)
    }

    func testLegacyScreensaverOnlyPlaylistBecomesDesktop() {
        let playlist = WallpaperPlaylist(
            name: "夜屏保",
            applyToDesktop: false,
            applyToScreensaver: true,
            screensaverIdleSeconds: 60
        )
        XCTAssertTrue(playlist.targetsDesktop)
    }

    func testHigherPriorityOwnsOverlappingScreen() {
        let low = WallpaperPlaylist(name: "随机", enabled: true, priority: 1)
        let high = WallpaperPlaylist(name: "工作", enabled: true, priority: 3)
        let available = ["screen-0", "screen-1"]
        XCTAssertEqual(
            WallpaperPlaylist.owner(of: "screen-0", among: [low, high], available: available)?.name,
            "工作"
        )
        XCTAssertTrue(
            WallpaperPlaylist.ownedDisplayIDs(for: low, among: [low, high], available: available).isEmpty
        )
        XCTAssertEqual(
            WallpaperPlaylist.ownedDisplayIDs(for: high, among: [low, high], available: available),
            available
        )
        XCTAssertEqual(high.priorityCaption(among: [low, high]), "第 1 优先")
        XCTAssertEqual(low.ownershipCaption(among: [low, high], displays: [
            DisplayProfile(id: "screen-0", name: "内屏", width: 1800, height: 1169, scale: 2),
            DisplayProfile(id: "screen-1", name: "外屏", width: 1920, height: 1080, scale: 1)
        ]), "重叠的屏正由「工作」换")
    }

    func testPlaylistPriorityRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshot.json")
        let store = JSONStore(fileURL: url)
        var snapshot = AppSnapshot()
        snapshot.playlists = [
            WallpaperPlaylist(name: "工作", applyToDesktop: false, applyToScreensaver: true, priority: 8)
        ]
        try await store.save(snapshot)
        let loaded = try await store.load()
        let playlist = try XCTUnwrap(loaded.playlists?.first)
        XCTAssertTrue(playlist.targetsDesktop)
        XCTAssertEqual(playlist.resolvedPriority, 8)
    }
}
