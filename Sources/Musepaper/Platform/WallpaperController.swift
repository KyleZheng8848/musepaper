import AppKit
import Foundation

/// Kept for settings compatibility. Desktop applies always do a single staged
/// commit — custom overlays fight macOS WallpaperAgent and look like jumping.
enum WallpaperTransition: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "无动效"
    case fade = "淡入"
    case crossfade = "交叉溶解"
    case pushLeft = "向左推入"
    case pushRight = "向右推入"
    case pushUp = "向上推入"
    case wipeRight = "向右擦除"
    case wipeDown = "向下擦除"
    case coverLeft = "向左覆盖"
    case uncoverRight = "向右揭开"
    case zoomIn = "放大切入"
    case blinds = "百叶窗"

    var id: String { rawValue }
}

@MainActor
final class WallpaperController {
    static let fillOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: Int(NSImageScaling.scaleAxesIndependently.rawValue),
        .allowClipping: true,
        .fillColor: NSColor.black
    ]

    private let workspace: NSWorkspace
    private let fileManager: FileManager
    private let stagingDirectory: URL
    private var pending: ApplyRequest?
    private var isDraining = false
    private var activeStagedByScreenID: [String: URL] = [:]

    struct ScreenAssignment: Sendable {
        var displayID: String
        var imageURL: URL
    }

    private struct ApplyRequest {
        var assignments: [ScreenAssignment]
        var continuations: [CheckedContinuation<Void, Error>]
    }

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
        self.stagingDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Musepaper", isDirectory: true)
            .appendingPathComponent("ActiveDesktop", isDirectory: true)
    }

    func currentPaths() -> [String: String] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().compactMap { index, screen in
            workspace.desktopImageURL(for: screen).map { (DisplayService.displayID(index: index), $0.path) }
        })
    }

    func apply(
        imageURL: URL,
        targetDisplayID: String,
        allDisplays: Bool,
        transition: WallpaperTransition = .none
    ) async throws {
        _ = transition
        let indexed = NSScreen.screens.enumerated().map { DisplayService.displayID(index: $0.offset) }
        let targets = allDisplays ? indexed : indexed.filter { $0 == targetDisplayID }
        let assignments = targets.map { ScreenAssignment(displayID: $0, imageURL: imageURL) }
        try await apply(assignments: assignments, transition: .none)
    }

    /// Apply possibly different images to specific screens in one visual commit.
    func apply(
        assignments: [ScreenAssignment],
        transition: WallpaperTransition = .none
    ) async throws {
        _ = transition
        guard !assignments.isEmpty else { throw MusepaperError.invalidDisplay }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if var existing = pending {
                var merged = Dictionary(uniqueKeysWithValues: existing.assignments.map { ($0.displayID, $0.imageURL) })
                for item in assignments {
                    merged[item.displayID] = item.imageURL
                }
                existing.assignments = merged.map { ScreenAssignment(displayID: $0.key, imageURL: $0.value) }
                existing.continuations.append(continuation)
                pending = existing
            } else {
                pending = ApplyRequest(assignments: assignments, continuations: [continuation])
            }
            Task { await self.drain() }
        }
    }

    func restore(paths: [String: String], transition: WallpaperTransition = .none) async throws {
        _ = transition
        let assignments = NSScreen.screens.enumerated().compactMap { index, _ -> ScreenAssignment? in
            let id = DisplayService.displayID(index: index)
            guard let path = paths[id], fileManager.fileExists(atPath: path) else { return nil }
            return ScreenAssignment(displayID: id, imageURL: URL(fileURLWithPath: path))
        }
        guard !assignments.isEmpty else { return }
        try await apply(assignments: assignments, transition: .none)
    }

    private func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while let request = pending {
            pending = nil
            do {
                try await perform(request)
                for continuation in request.continuations { continuation.resume() }
            } catch {
                for continuation in request.continuations { continuation.resume(throwing: error) }
            }
        }
    }

    private func perform(_ request: ApplyRequest) async throws {
        let indexedScreens = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.enumerated().map { (DisplayService.displayID(index: $0.offset), $0.element) }
        )
        var staged: [(screenID: String, screen: NSScreen, url: URL)] = []
        staged.reserveCapacity(request.assignments.count)

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let token = UUID().uuidString

        for assignment in request.assignments {
            guard let screen = indexedScreens[assignment.displayID] else { continue }
            guard fileManager.fileExists(atPath: assignment.imageURL.path) else {
                throw MusepaperError.missingImage
            }
            let url = stagingDirectory.appendingPathComponent("\(assignment.displayID)-\(token).png")
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.copyItem(at: assignment.imageURL, to: url)
            staged.append((assignment.displayID, screen, url))
        }
        guard !staged.isEmpty else { throw MusepaperError.invalidDisplay }

        for item in staged {
            try workspace.setDesktopImageURL(item.url, for: item.screen, options: Self.fillOptions)
            activeStagedByScreenID[item.screenID] = item.url
        }

        try await Task.sleep(nanoseconds: 350_000_000)
        cleanupStaging(keeping: Set(activeStagedByScreenID.values.map(\.path)))
        // WallpaperAgent writes huge BMPs after setDesktopImageURL. Prune off the
        // apply path, after a short settle, so switches stay snappy and the new
        // cache file exists before we decide what to keep.
        SystemWallpaperCachePruner.scheduleAfterApply(screenCount: staged.count)
    }

    private func cleanupStaging(keeping: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in files where !keeping.contains(url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Kept for tests — Int32 desktop levels must be widened before arithmetic.
    static var wallpaperOverlayLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
}

/// Prunes macOS WallpaperAgent's on-disk BMP cache after desktop switches.
enum SystemWallpaperCachePruner {
    static let defaultKeepNewest = 6
    static let defaultMaxTotalBytes: Int64 = 512 * 1024 * 1024
    /// Let WallpaperAgent finish copying the new BMP before we scan.
    static let settleNanoseconds: UInt64 = 1_200_000_000
    private static let imageExtensionFolder = "extension-com.apple.wallpaper.extension.image"
    private static let scheduler = PruneScheduler()

    private actor PruneScheduler {
        private var generation = 0

        func nextGeneration() -> Int {
            generation += 1
            return generation
        }

        func isLatest(_ candidate: Int) -> Bool {
            candidate == generation
        }
    }

    static func defaultRootURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches",
            isDirectory: true
        )
    }

    static func imageCacheURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        defaultRootURL(home: home).appendingPathComponent(imageExtensionFolder, isDirectory: true)
    }

    /// Coalesce rapid playlist switches into one delayed prune.
    static func scheduleAfterApply(screenCount: Int) {
        let keepNewest = max(defaultKeepNewest, max(1, screenCount) * 2)
        let settle = settleNanoseconds
        let budget = defaultMaxTotalBytes
        Task.detached(priority: .utility) {
            let generation = await scheduler.nextGeneration()
            try? await Task.sleep(nanoseconds: settle)
            guard await scheduler.isLatest(generation) else { return }
            _ = prune(
                root: imageCacheURL(),
                fileManager: .default,
                keepNewest: keepNewest,
                maxTotalBytes: budget
            )
        }
    }

    @discardableResult
    static func prune(
        root: URL = imageCacheURL(),
        fileManager: FileManager = .default,
        keepNewest: Int = defaultKeepNewest,
        maxTotalBytes: Int64 = defaultMaxTotalBytes
    ) -> Int {
        guard keepNewest > 0, fileManager.fileExists(atPath: root.path) else { return 0 }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var files: [(url: URL, date: Date, size: Int64)] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            // Skip incomplete / zero-byte writes still in flight.
            let size = Int64(values.fileSize ?? 0)
            guard size > 0 else { continue }
            files.append((
                url,
                values.contentModificationDate ?? .distantPast,
                size
            ))
        }
        guard !files.isEmpty else { return 0 }

        files.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.url.path > rhs.url.path
        }

        var keep = Array(files.prefix(keepNewest))
        var total = keep.reduce(Int64(0)) { $0 + $1.size }
        while keep.count > 2, total > maxTotalBytes {
            total -= keep.removeLast().size
        }
        // Even two huge BMPs can exceed the budget on 5K displays — still keep the newest two.
        let keepPaths = Set(keep.map(\.url.path))
        var deleted = 0
        for file in files where !keepPaths.contains(file.url.path) {
            do {
                try fileManager.removeItem(at: file.url)
                deleted += 1
            } catch {
                continue
            }
        }
        return deleted
    }
}
