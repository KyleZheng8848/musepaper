import Foundation

enum ScheduledApplyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case review = "生成后放入待选"
    case applyFirst = "自动应用第一张"
    var id: String { rawValue }
}

/// 作品集网格按创作时间排序（卡片也显示 createdAt）。
enum LibrarySortOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case newestFirst = "最新在前"
    case oldestFirst = "最早在前"
    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable, Sendable {
    var autoApply = false
    var generateBeforeApplying = true
    var scheduleEnabled = false
    var scheduleHour = 8
    var applyToAllDisplays = true
    var selectedDisplayID: String?
    var selectedChannelID: UUID?
    var skipWhenLowPower: Bool?
    var historyLimit: Int?
    var scheduledSeriesID: UUID?
    var scheduledCandidateCount: Int?
    var scheduledApplyMode: ScheduledApplyMode?
    var wallpaperTransition: WallpaperTransition?
    /// Desktop corner controls: like + delete + next wallpaper.
    var desktopControlsEnabled: Bool?
    var lastAppliedArtworkID: UUID?
    /// Per-screen cursor. Desktop corner buttons must resolve this screen, not the last apply.
    var lastAppliedArtworkIDsByDisplay: [String: UUID]?
    /// File stems the user deleted — reindex must not resurrect them from disk.
    var deletedArtworkStems: [String]?
    /// Ambient motion over the still desktop wallpaper (under apps).
    var livingWallpaperEnabled: Bool?
    var livingWallpaperStyle: LivingWallpaperStyle?
    /// Extra holographic foil on top of the atmosphere motion. Default off.
    var livingHoloFoil: LivingHoloFoil?
    /// Optional mask-based relief on the photo. Default off.
    var livingDepthStyle: LivingDepthStyle?
    /// Center desktop clock / date.
    var desktopClockEnabled: Bool?
    var desktopClockFace: DesktopClockFace?
    /// Desktop weather / temperature chip.
    var desktopWeatherEnabled: Bool?
    var desktopWeatherUnit: WeatherTemperatureUnit?
    /// Optional city override (e.g. "杭州"). Empty → auto locate.
    var desktopWeatherCity: String?
    /// Library grid sort by creation time.
    var librarySortOrder: LibrarySortOrder?
    /// 系统通知去重：已提示过的线上版本。
    var updateNoticeSeenVersion: String?
    /// 横幅「稍后」：该线上版本不再显示横幅。
    var updateBannerDismissedVersion: String?
}

struct AppSnapshot: Codable, Sendable {
    var channels: [InspirationChannel] = [.sample]
    var records: [GenerationRecord] = []
    var settings = AppSettings()
    var previousWallpaperPaths: [String: String] = [:]
    var modelConfigurations: [ModelConfiguration]?
    var activeModelConfigurationID: UUID?
    /// Legacy single text-model config; migrated into `promptModelConfigurations` on load.
    var promptModelConfiguration: PromptModelConfiguration?
    var promptModelConfigurations: [PromptModelConfiguration]?
    var promptAgentRouting: PromptAgentRouting?
    var batches: [GenerationBatch]?
    var smartCollections: [SmartCollection]?
    var playlists: [WallpaperPlaylist]?
    var verifiedImageRoute: ImageRoute?
}
