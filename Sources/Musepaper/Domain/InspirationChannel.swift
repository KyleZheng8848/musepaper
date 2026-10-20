import Foundation

enum PromptStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case explore = "主题探索"
    case enhance = "加强原 Prompt"
    case hybrid = "探索并加强"
    var id: String { rawValue }
}

struct InspirationChannel: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var essence: String
    var mustInclude: String
    var exclude: String
    var palette: String
    var variation: Double
    var requiresApproval: Bool
    var coreKeywords: String?
    var variationAxes: String?
    var defaultCandidateCount: Int?
    var referenceImagePaths: [String]?
    var promptStrategy: PromptStrategy?
    var scheduleEnabled: Bool?
    var scheduleHour: Int?
    var scheduledCandidateCount: Int?
    var scheduleIntervalHours: Int?
    var scheduleIntervalSeconds: Int?
    var seedArtworkPath: String?
    var seedArtworkID: UUID?
    var lastProducedAt: Date?

    static let minCandidateCount = 1
    /// Typo guard only (e.g. 999999). Not a product batch limit — type whatever you want.
    static let maxCandidateCount = 9_999
    static let candidateCountRange = minCandidateCount...maxCandidateCount
    static let countPresets = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 100, 128]
    static let minIntervalHours = 1
    static let maxIntervalHours = 168
    static let intervalRange = minIntervalHours...maxIntervalHours
    static let minIntervalSeconds = 10
    static let maxIntervalSeconds = 30 * 24 * 3600
    static let defaultIntervalSeconds = 8 * 3600
    static let intervalSecondsRange = minIntervalSeconds...maxIntervalSeconds

    static func clampedCount(_ count: Int) -> Int {
        min(max(count, minCandidateCount), maxCandidateCount)
    }

    static func clampedInterval(_ hours: Int) -> Int {
        min(max(hours, minIntervalHours), maxIntervalHours)
    }

    static func clampedIntervalSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minIntervalSeconds), maxIntervalSeconds)
    }

    static func intervalComponents(
        _ seconds: Int,
        minSeconds: Int = minIntervalSeconds,
        maxSeconds: Int = maxIntervalSeconds
    ) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let value = min(max(seconds, minSeconds), maxSeconds)
        return (value / 86400, (value % 86400) / 3600, (value % 3600) / 60, value % 60)
    }

    static func seconds(days: Int, hours: Int, minutes: Int, seconds: Int) -> Int {
        clampedIntervalSeconds((((days * 24) + hours) * 60 + minutes) * 60 + seconds)
    }

    static func cadenceLabel(_ hours: Int) -> String {
        cadenceLabel(seconds: hours * 3600)
    }

    static func cadenceLabel(
        seconds: Int,
        minSeconds: Int = minIntervalSeconds,
        maxSeconds: Int = maxIntervalSeconds
    ) -> String {
        let parts = intervalComponents(seconds, minSeconds: minSeconds, maxSeconds: maxSeconds)
        if parts.days > 0, parts.hours == 0, parts.minutes == 0, parts.seconds == 0 {
            return parts.days == 1 ? "每天一次" : "每 \(parts.days) 天"
        }
        if parts.days == 0, parts.hours == 1, parts.minutes == 0, parts.seconds == 0 {
            return "每小时"
        }
        if parts.days == 0, parts.minutes == 0, parts.seconds == 0, parts.hours > 0 {
            return "每 \(parts.hours) 小时"
        }
        var chunks: [String] = []
        if parts.days > 0 { chunks.append("\(parts.days)天") }
        if parts.hours > 0 { chunks.append("\(parts.hours)小时") }
        if parts.minutes > 0 { chunks.append("\(parts.minutes)分") }
        if parts.seconds > 0 { chunks.append("\(parts.seconds)秒") }
        return chunks.isEmpty ? "每 \(max(1, minSeconds)) 秒" : "每 \(chunks.joined())"
    }

    enum IntervalUnit: String, CaseIterable, Identifiable {
        case days = "天"
        case hours = "小时"
        case minutes = "分钟"
        case seconds = "秒"
        var id: String { rawValue }
        var stepSeconds: Int {
            switch self {
            case .days: 86400
            case .hours: 3600
            case .minutes: 60
            case .seconds: 1
            }
        }
        var maxAmount: Int {
            switch self {
            case .days: 30
            case .hours: 168
            case .minutes: 24 * 60
            case .seconds: 3600
            }
        }
    }

    static func preferredUnit(for seconds: Int) -> IntervalUnit {
        let value = clampedIntervalSeconds(seconds)
        if value % 86400 == 0 { return .days }
        if value % 3600 == 0 { return .hours }
        if value % 60 == 0 { return .minutes }
        return .seconds
    }

    static func amount(for seconds: Int, unit: IntervalUnit) -> Int {
        max(1, clampedIntervalSeconds(seconds) / unit.stepSeconds)
    }

    static func seconds(amount: Int, unit: IntervalUnit) -> Int {
        clampedIntervalSeconds(max(1, amount) * unit.stepSeconds)
    }

    init(
        id: UUID = UUID(), name: String, essence: String, mustInclude: String = "",
        exclude: String = "文字、水印", palette: String = "深蓝、灰黑、少量暖光",
        variation: Double = 0.55, requiresApproval: Bool = true,
        coreKeywords: String = "", variationAxes: String = "",
        defaultCandidateCount: Int = 4, referenceImagePaths: [String] = [],
        promptStrategy: PromptStrategy = .hybrid, scheduleEnabled: Bool = false,
        scheduleHour: Int = 8, scheduledCandidateCount: Int = 4,
        scheduleIntervalHours: Int = 8, scheduleIntervalSeconds: Int? = nil,
        seedArtworkPath: String? = nil,
        seedArtworkID: UUID? = nil, lastProducedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.essence = essence
        self.mustInclude = mustInclude
        self.exclude = exclude
        self.palette = palette
        self.variation = variation
        self.requiresApproval = requiresApproval
        self.coreKeywords = coreKeywords
        self.variationAxes = variationAxes
        self.defaultCandidateCount = Self.clampedCount(defaultCandidateCount)
        self.referenceImagePaths = referenceImagePaths
        self.promptStrategy = promptStrategy
        self.scheduleEnabled = scheduleEnabled
        self.scheduleHour = min(max(scheduleHour, 0), 23)
        self.scheduledCandidateCount = Self.clampedCount(scheduledCandidateCount)
        if let scheduleIntervalSeconds {
            self.scheduleIntervalSeconds = Self.clampedIntervalSeconds(scheduleIntervalSeconds)
            self.scheduleIntervalHours = nil
        } else {
            self.scheduleIntervalSeconds = Self.clampedIntervalSeconds(scheduleIntervalHours * 3600)
            self.scheduleIntervalHours = Self.clampedInterval(scheduleIntervalHours)
        }
        self.seedArtworkPath = seedArtworkPath
        self.seedArtworkID = seedArtworkID
        self.lastProducedAt = lastProducedAt
    }

    var resolvedCoreKeywords: String { coreKeywords?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }

    /// The user's own preset. Variations may add around this, never replace it.
    var lockedCore: String {
        let composer = PromptComposer()
        if let keys = composer.usableVisual(resolvedCoreKeywords) { return keys }
        if let essence = composer.usableVisual(essence) { return essence }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !composer.isSchemaPlaceholder(title) { return title }
        return ""
    }
    var resolvedVariationAxes: String { variationAxes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var resolvedCandidateCount: Int { Self.clampedCount(defaultCandidateCount ?? 4) }
    var resolvedReferenceImagePaths: [String] { referenceImagePaths ?? [] }
    var resolvedPromptStrategy: PromptStrategy { promptStrategy ?? .hybrid }
    var resolvedScheduleEnabled: Bool { scheduleEnabled ?? false }
    var resolvedScheduleHour: Int { min(max(scheduleHour ?? 8, 0), 23) }
    var resolvedScheduledCandidateCount: Int { Self.clampedCount(scheduledCandidateCount ?? resolvedCandidateCount) }
    var resolvedScheduleIntervalSeconds: Int {
        if let scheduleIntervalSeconds {
            return Self.clampedIntervalSeconds(scheduleIntervalSeconds)
        }
        if let scheduleIntervalHours {
            return Self.clampedIntervalSeconds(scheduleIntervalHours * 3600)
        }
        return Self.defaultIntervalSeconds
    }
    var resolvedScheduleIntervalHours: Int {
        max(1, resolvedScheduleIntervalSeconds / 3600)
    }
    var resolvedSeedPath: String? {
        guard let path = seedArtworkPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    var isSchemaTemplate: Bool {
        let composer = PromptComposer()
        if composer.usableVisual(essence) != nil { return false }
        return composer.isSchemaPlaceholder(name)
            || composer.isSchemaPlaceholder(essence)
            || composer.isSchemaPlaceholder(resolvedCoreKeywords)
    }

    /// One sentence is enough to own a task. Empty title/essence/core fields
    /// inherit the idea so the editor cannot trap people behind prompt-engineering.
    func completingMissingFields(idea: String) -> InspirationChannel {
        var copy = self
        let fallback = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || PromptComposer().isSchemaPlaceholder(copy.name)
        {
            copy.name = Self.title(from: fallback)
        }
        if copy.essence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || PromptComposer().isSchemaPlaceholder(copy.essence)
        {
            copy.essence = fallback
        }
        if copy.resolvedCoreKeywords.isEmpty || PromptComposer().isSchemaPlaceholder(copy.resolvedCoreKeywords) {
            copy.coreKeywords = copy.essence
        }
        return copy
    }

    static func title(from idea: String) -> String {
        let trimmed = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未命名任务" }
        let marks = CharacterSet(charactersIn: "，,、。；;：:/\n")
        if let first = trimmed.rangeOfCharacter(from: marks) {
            let head = String(trimmed[..<first.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (4...12).contains(head.count) { return head }
            if head.count > 12 { return String(head.prefix(12)) }
            let after = trimmed[first.upperBound...]
            if let second = after.rangeOfCharacter(from: marks) {
                let two = String(trimmed[..<second.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if (2...12).contains(two.count) { return two }
            }
        }
        return trimmed.count <= 12 ? trimmed : String(trimmed.prefix(12))
    }

    static let sample = InspirationChannel(
        name: "孤独宇宙",
        essence: "安静、空旷、有探索感的宇宙场景",
        mustInclude: "遥远光源、巨大空间尺度",
        coreKeywords: "孤独尺度、深空、克制暖光",
        variationAxes: "观察：近处边缘/行星全景/极远光带；时段：日蚀/黎明/深夜；尺度：贴近/压过来/铺开"
    )
}

struct WallpaperBlueprintSuggestion: Equatable, Sendable {
    var name: String
    var essence: String
    var coreKeywords: String
    var variationAxes: String
    var palette: String
    var exclusions: String
}
