import Foundation

actor JSONStore {
    private let fileURL: URL
    private let backupDirectory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let maxBackups = 30

    /// Set after each `load()` — UI can surface recovery messages.
    private(set) var lastLoadNote: String?

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Musepaper", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("snapshot.json")
        self.backupDirectory = self.fileURL.deletingLastPathComponent().appendingPathComponent("Snapshots", isDirectory: true)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> AppSnapshot {
        lastLoadNote = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSnapshot()
        }
        let primary = try Data(contentsOf: fileURL)
        if let snapshot = decodeFlexible(primary) {
            return snapshot
        }

        for backup in backupURLs() {
            guard let data = try? Data(contentsOf: backup), let snapshot = decodeFlexible(data) else { continue }
            lastLoadNote = "主配置无法解码，已从备份恢复（\(backup.lastPathComponent)）"
            // Restore primary so future launches stay healthy.
            try? data.write(to: fileURL, options: .atomic)
            return snapshot
        }

        throw MusepaperError.persistenceFailed(
            "作品库配置无法读取，且没有可用备份。为避免覆盖，本次不会写入。请从 Time Machine 恢复 snapshot.json。"
        )
    }

    func save(_ snapshot: AppSnapshot) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rotateBackupIfNeeded()
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            throw MusepaperError.persistenceFailed(error.localizedDescription)
        }
    }

    private func rotateBackupIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "snapshot-\(formatter.string(from: Date())).json"
        let destination = backupDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: fileURL, to: destination)

        let backups = backupURLs()
        if backups.count > maxBackups {
            for stale in backups.suffix(from: maxBackups) {
                try? FileManager.default.removeItem(at: stale)
            }
        }
    }

    private func backupURLs() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    private func decodeFlexible(_ data: Data) -> AppSnapshot? {
        if let snapshot = try? decoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }
        guard let sanitized = try? SnapshotSanitizer.sanitize(data),
              let snapshot = try? decoder.decode(AppSnapshot.self, from: sanitized) else {
            return nil
        }
        if lastLoadNote == nil {
            lastLoadNote = "配置里有过期字段，已自动兼容加载"
        }
        return snapshot
    }
}

/// Drop unknown enum raw values so a renamed style/face cannot wipe the whole library.
enum SnapshotSanitizer {
    static func sanitize(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        if var settings = root["settings"] as? [String: Any] {
            nullUnknown(&settings, key: "desktopClockFace", allowed: DesktopClockFace.allCases.map(\.rawValue))
            nullUnknown(&settings, key: "livingWallpaperStyle", allowed: LivingWallpaperStyle.allCases.map(\.rawValue))
            nullUnknown(&settings, key: "wallpaperTransition", allowed: WallpaperTransition.allCases.map(\.rawValue))
            nullUnknown(&settings, key: "desktopWeatherUnit", allowed: WeatherTemperatureUnit.allCases.map(\.rawValue))
            nullUnknown(&settings, key: "scheduledApplyMode", allowed: ScheduledApplyMode.allCases.map(\.rawValue))
            root["settings"] = settings
        }

        if var channels = root["channels"] as? [[String: Any]] {
            for index in channels.indices {
                nullUnknown(&channels[index], key: "promptStrategy", allowed: PromptStrategy.allCases.map(\.rawValue))
            }
            root["channels"] = channels
        }

        if var models = root["modelConfigurations"] as? [[String: Any]] {
            for index in models.indices {
                replaceUnknown(&models[index], key: "provider", allowed: ProviderKind.allCases.map(\.rawValue), fallback: ProviderKind.compatible.rawValue)
                replaceUnknown(&models[index], key: "quality", allowed: ImageQuality.allCases.map(\.rawValue), fallback: ImageQuality.medium.rawValue)
                replaceUnknown(&models[index], key: "size", allowed: GeneratedImageSize.allCases.map(\.rawValue), fallback: GeneratedImageSize.landscape.rawValue)
                replaceUnknown(&models[index], key: "outputFormat", allowed: ImageOutputFormat.allCases.map(\.rawValue), fallback: ImageOutputFormat.png.rawValue)
            }
            root["modelConfigurations"] = models
        }

        if var prompt = root["promptModelConfiguration"] as? [String: Any] {
            replaceUnknown(&prompt, key: "apiFormat", allowed: PromptAPIFormat.allCases.map(\.rawValue), fallback: PromptAPIFormat.chatCompletions.rawValue)
            root["promptModelConfiguration"] = prompt
        }

        if var prompts = root["promptModelConfigurations"] as? [[String: Any]] {
            for index in prompts.indices {
                replaceUnknown(
                    &prompts[index],
                    key: "apiFormat",
                    allowed: PromptAPIFormat.allCases.map(\.rawValue),
                    fallback: PromptAPIFormat.chatCompletions.rawValue
                )
            }
            root["promptModelConfigurations"] = prompts
        }

        if var routing = root["promptAgentRouting"] as? [String: Any] {
            replaceUnknown(
                &routing,
                key: "mode",
                allowed: PromptAgentModelMode.allCases.map(\.rawValue),
                fallback: PromptAgentModelMode.fixed.rawValue
            )
            root["promptAgentRouting"] = routing
        }

        if var playlists = root["playlists"] as? [[String: Any]] {
            for index in playlists.indices {
                nullUnknown(&playlists[index], key: "atmosphere", allowed: PlaylistAtmosphere.allCases.map(\.rawValue))
                replaceUnknown(&playlists[index], key: "source", allowed: PlaylistSource.allCases.map(\.rawValue), fallback: PlaylistSource.all.rawValue)
                replaceUnknown(&playlists[index], key: "order", allowed: PlaylistOrder.allCases.map(\.rawValue), fallback: PlaylistOrder.shuffle.rawValue)
            }
            root["playlists"] = playlists
        }

        if var route = root["verifiedImageRoute"] as? [String: Any] {
            replaceUnknown(&route, key: "provider", allowed: ProviderKind.allCases.map(\.rawValue), fallback: ProviderKind.compatible.rawValue)
            root["verifiedImageRoute"] = route
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func nullUnknown(_ object: inout [String: Any], key: String, allowed: [String]) {
        guard let value = object[key] as? String else { return }
        if !allowed.contains(value) {
            object[key] = NSNull()
        }
    }

    private static func replaceUnknown(_ object: inout [String: Any], key: String, allowed: [String], fallback: String) {
        guard let value = object[key] as? String else { return }
        if !allowed.contains(value) {
            object[key] = fallback
        }
    }
}
