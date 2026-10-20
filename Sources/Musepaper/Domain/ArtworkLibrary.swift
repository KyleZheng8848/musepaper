import Foundation

struct SmartCollection: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var taskIDs: [UUID]
    var includeTags: [String]
    var excludeTags: [String]
    var favoritesOnly: Bool

    init(
        id: UUID = UUID(), name: String, taskIDs: [UUID] = [],
        includeTags: [String] = [], excludeTags: [String] = [], favoritesOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.taskIDs = taskIDs
        self.includeTags = includeTags
        self.excludeTags = excludeTags
        self.favoritesOnly = favoritesOnly
    }

    func includes(_ artwork: GenerationRecord) -> Bool {
        if favoritesOnly && !artwork.isFavorite { return false }
        if !taskIDs.isEmpty {
            guard let taskID = artwork.request.seriesID, taskIDs.contains(taskID) else { return false }
        }
        let artworkTags = Set(artwork.resolvedTags.map { $0.lowercased() })
        let required = Set(includeTags.map { $0.lowercased() })
        let excluded = Set(excludeTags.map { $0.lowercased() })
        return required.isSubset(of: artworkTags) && artworkTags.isDisjoint(with: excluded)
    }
}

enum PlaylistSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case all = "全部作品"
    case task = "生成任务"
    case collection = "智能作品集"
    var id: String { rawValue }
}

enum PlaylistOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case shuffle = "随机播放"
    case newest = "最新优先"
    case oldest = "顺序播放"
    var id: String { rawValue }
}

struct WallpaperPlaylist: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var source: PlaylistSource
    var sourceID: UUID?
    var order: PlaylistOrder
    /// Change interval in seconds. Minimum 1s; maximum 30 days.
    var intervalSeconds: Int
    var enabled: Bool
    var lastArtworkID: UUID?
    /// Per-display cursor for independent wallpapers on each screen.
    var lastArtworkIDsByDisplay: [String: UUID]?
    /// Target `screen-N` ids. Empty / nil = all currently connected screens.
    var targetDisplayIDs: [String]?
    /// Per-task atmosphere; default follow global settings.
    var atmosphere: PlaylistAtmosphere?
    /// Larger number wins when two enabled tasks claim the same screen. Nil = 1.
    var priority: Int?
    /// Legacy decode-only: old builds stored desktop/screensaver surfaces.
    var applyToDesktop: Bool?
    var applyToScreensaver: Bool?
    var screensaverIdleSeconds: Int?

    static let minIntervalSeconds = 1
    static let maxIntervalSeconds = 30 * 24 * 3600
    static let defaultIntervalSeconds = 60 * 60
    static let minPriority = 1
    static let maxPriority = 99
    static let defaultPriority = 1

    /// Stable identity for the built-in library shuffle task — survives empty snapshots.
    static let presetID = UUID(uuidString: "A11C0FFE-5EED-4A11-9A11-000000000001")!

    /// One always-available rule: rotate the whole library once a day.
    static var libraryShufflePreset: WallpaperPlaylist {
        WallpaperPlaylist(
            id: presetID,
            name: "随机",
            source: .all,
            order: .shuffle,
            intervalSeconds: 24 * 3600,
            enabled: false,
            atmosphere: .random,
            priority: minPriority
        )
    }

    var isPreset: Bool { id == Self.presetID }

    static func clampedIntervalSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minIntervalSeconds), maxIntervalSeconds)
    }

    static func clampedPriority(_ value: Int) -> Int {
        min(max(value, minPriority), maxPriority)
    }

    init(
        id: UUID = UUID(), name: String, source: PlaylistSource = .all,
        sourceID: UUID? = nil, order: PlaylistOrder = .shuffle,
        intervalSeconds: Int = WallpaperPlaylist.defaultIntervalSeconds,
        enabled: Bool = false, lastArtworkID: UUID? = nil,
        lastArtworkIDsByDisplay: [String: UUID]? = nil,
        targetDisplayIDs: [String]? = nil,
        atmosphere: PlaylistAtmosphere? = .followGlobal,
        priority: Int? = nil,
        applyToDesktop: Bool? = nil,
        applyToScreensaver: Bool? = nil,
        screensaverIdleSeconds: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.sourceID = sourceID
        self.order = order
        self.intervalSeconds = Self.clampedIntervalSeconds(intervalSeconds)
        self.enabled = enabled
        self.lastArtworkID = lastArtworkID
        self.lastArtworkIDsByDisplay = lastArtworkIDsByDisplay
        self.targetDisplayIDs = targetDisplayIDs
        self.atmosphere = atmosphere ?? .followGlobal
        self.priority = priority.map(Self.clampedPriority)
        self.applyToDesktop = applyToDesktop
        self.applyToScreensaver = applyToScreensaver
        self.screensaverIdleSeconds = screensaverIdleSeconds
    }

    /// Legacy convenience for callers that still think in minutes.
    init(
        id: UUID = UUID(), name: String, source: PlaylistSource = .all,
        sourceID: UUID? = nil, order: PlaylistOrder = .shuffle,
        intervalMinutes: Int, enabled: Bool = false, lastArtworkID: UUID? = nil,
        atmosphere: PlaylistAtmosphere? = .followGlobal
    ) {
        self.init(
            id: id, name: name, source: source, sourceID: sourceID, order: order,
            intervalSeconds: intervalMinutes * 60, enabled: enabled,
            lastArtworkID: lastArtworkID, atmosphere: atmosphere
        )
    }

    var resolvedAtmosphere: PlaylistAtmosphere { atmosphere ?? .followGlobal }

    var resolvedPriority: Int { Self.clampedPriority(priority ?? Self.defaultPriority) }

    /// Screensaver surface was dropped; every task is a desktop wallpaper rule.
    var targetsDesktop: Bool { true }

    static func ranked(_ playlists: [WallpaperPlaylist]) -> [WallpaperPlaylist] {
        playlists.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.resolvedPriority != rhs.element.resolvedPriority {
                    return lhs.element.resolvedPriority > rhs.element.resolvedPriority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func rank(of id: UUID, among playlists: [WallpaperPlaylist]) -> Int? {
        ranked(playlists).firstIndex { $0.id == id }.map { $0 + 1 }
    }

    static func owner(
        of displayID: String,
        among playlists: [WallpaperPlaylist],
        available: [String]
    ) -> WallpaperPlaylist? {
        ranked(playlists).first { playlist in
            playlist.enabled && playlist.resolvedTargetDisplayIDs(available: available).contains(displayID)
        }
    }

    static func ownedDisplayIDs(
        for playlist: WallpaperPlaylist,
        among playlists: [WallpaperPlaylist],
        available: [String]
    ) -> [String] {
        playlist.resolvedTargetDisplayIDs(available: available).filter { displayID in
            owner(of: displayID, among: playlists, available: available)?.id == playlist.id
        }
    }

    func ownershipCaption(among playlists: [WallpaperPlaylist], displays: [DisplayProfile]) -> String {
        let available = displays.map(\.id)
        let wanted = resolvedTargetDisplayIDs(available: available)
        if !enabled { return "暂停中，先不管屏" }
        if wanted.isEmpty { return "还没有检测到屏幕" }
        let owned = Self.ownedDisplayIDs(for: self, among: playlists, available: available)
        if owned.isEmpty {
            let blocker = wanted
                .compactMap { Self.owner(of: $0, among: playlists, available: available)?.name }
                .first
            if let blocker { return "重叠的屏正由「\(blocker)」换" }
            return "当前管不到屏"
        }
        if owned.count == wanted.count {
            return targetCaption(displays: displays)
        }
        let ownedNames = owned.compactMap { id in displays.first { $0.id == id }?.name }
        let ownedText = ownedNames.isEmpty ? "\(owned.count) 块屏" : ownedNames.joined(separator: "、")
        let blocked = wanted.filter { !owned.contains($0) }
        let blocker = blocked.compactMap { Self.owner(of: $0, among: playlists, available: available)?.name }.first
        if let blocker { return "现管\(ownedText)；其余由「\(blocker)」换" }
        return "现管\(ownedText)"
    }

    func priorityCaption(among playlists: [WallpaperPlaylist]) -> String {
        let rank = Self.rank(of: id, among: playlists) ?? 1
        return "第 \(rank) 优先"
    }

    var targetsAllDisplays: Bool {
        let ids = targetDisplayIDs ?? []
        return ids.isEmpty
    }

    func resolvedTargetDisplayIDs(available: [String]) -> [String] {
        guard !available.isEmpty else { return [] }
        let wanted = (targetDisplayIDs ?? []).filter { available.contains($0) }
        return wanted.isEmpty ? available : wanted
    }

    func lastArtworkID(on displayID: String) -> UUID? {
        if let mapped = lastArtworkIDsByDisplay?[displayID] { return mapped }
        return lastArtworkID
    }

    mutating func rememberArtwork(_ artworkID: UUID, on displayIDs: [String]) {
        lastArtworkID = artworkID
        var map = lastArtworkIDsByDisplay ?? [:]
        for id in displayIDs {
            map[id] = artworkID
        }
        lastArtworkIDsByDisplay = map
    }

    mutating func rememberAssignments(_ assignments: [(displayID: String, artworkID: UUID)]) {
        guard let last = assignments.last else { return }
        lastArtworkID = last.artworkID
        var map = lastArtworkIDsByDisplay ?? [:]
        for item in assignments {
            map[item.displayID] = item.artworkID
        }
        lastArtworkIDsByDisplay = map
    }

    var intervalCaption: String {
        InspirationChannel.cadenceLabel(
            seconds: intervalSeconds,
            minSeconds: Self.minIntervalSeconds,
            maxSeconds: Self.maxIntervalSeconds
        )
    }

    func targetCaption(displays: [DisplayProfile]) -> String {
        let available = displays.map(\.id)
        let ids = resolvedTargetDisplayIDs(available: available)
        if targetsAllDisplays || ids.count == available.count {
            return ids.count <= 1 ? "当前屏幕" : "全部 \(ids.count) 块屏（可各不同）"
        }
        let names = ids.compactMap { id in displays.first(where: { $0.id == id })?.name }
        if names.isEmpty { return "选定屏幕" }
        if names.count <= 2 { return names.joined(separator: "、") }
        return "\(names.prefix(2).joined(separator: "、")) 等 \(names.count) 屏"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source, sourceID, order
        case intervalSeconds, intervalMinutes
        case enabled, lastArtworkID, lastArtworkIDsByDisplay
        case targetDisplayIDs, atmosphere, priority
        case applyToDesktop, applyToScreensaver, screensaverIdleSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        source = try c.decode(PlaylistSource.self, forKey: .source)
        sourceID = try c.decodeIfPresent(UUID.self, forKey: .sourceID)
        order = try c.decodeIfPresent(PlaylistOrder.self, forKey: .order) ?? .shuffle
        if let seconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) {
            intervalSeconds = Self.clampedIntervalSeconds(seconds)
        } else if let minutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) {
            intervalSeconds = Self.clampedIntervalSeconds(minutes * 60)
        } else {
            intervalSeconds = Self.defaultIntervalSeconds
        }
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lastArtworkID = try c.decodeIfPresent(UUID.self, forKey: .lastArtworkID)
        lastArtworkIDsByDisplay = try c.decodeIfPresent([String: UUID].self, forKey: .lastArtworkIDsByDisplay)
        targetDisplayIDs = try c.decodeIfPresent([String].self, forKey: .targetDisplayIDs)
        atmosphere = try c.decodeIfPresent(PlaylistAtmosphere.self, forKey: .atmosphere) ?? .followGlobal
        priority = try c.decodeIfPresent(Int.self, forKey: .priority).map(Self.clampedPriority)
        applyToDesktop = try c.decodeIfPresent(Bool.self, forKey: .applyToDesktop)
        applyToScreensaver = try c.decodeIfPresent(Bool.self, forKey: .applyToScreensaver)
        screensaverIdleSeconds = try c.decodeIfPresent(Int.self, forKey: .screensaverIdleSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(sourceID, forKey: .sourceID)
        try c.encode(order, forKey: .order)
        try c.encode(intervalSeconds, forKey: .intervalSeconds)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(lastArtworkID, forKey: .lastArtworkID)
        try c.encodeIfPresent(lastArtworkIDsByDisplay, forKey: .lastArtworkIDsByDisplay)
        try c.encodeIfPresent(targetDisplayIDs, forKey: .targetDisplayIDs)
        try c.encodeIfPresent(atmosphere, forKey: .atmosphere)
        try c.encodeIfPresent(priority, forKey: .priority)
    }
}
