import Foundation

enum GenerationState: String, Codable, Sendable {
    case queued, composing, generating, adapting, ready, applying, applied, failed, cancelled
}

enum GenerationTrigger: String, Codable, Sendable {
    case manual, scheduled
}

enum BatchState: String, Codable, Sendable {
    case preparing, generating, ready, applied, failed, cancelled
}

struct GenerationBatch: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var seriesID: UUID?
    var recordIDs: [UUID]
    var selectedRecordID: UUID?
    var prompt: String
    var trigger: GenerationTrigger
    var state: BatchState
    var createdAt: Date
    var errorMessage: String?
}

struct DisplayProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var width: Int
    var height: Int
    var scale: Double
    var aspectRatio: Double { Double(width) / Double(max(height, 1)) }

    static let preview = DisplayProfile(id: "preview", name: "演示屏幕", width: 2560, height: 1600, scale: 2)
}

struct WallpaperApplyIntent: Equatable, Sendable {
    var targetDisplayID: String
    var allDisplays: Bool
}

struct DisplayProbe: Equatable, Sendable {
    var width: Int
    var height: Int
    var scale: Double
}

struct GenerationRequest: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var rawInput: String
    var resolvedPrompt: String
    var negativePrompt: String
    var display: DisplayProfile
    var createdAt: Date
    var referenceImagePaths: [String]? = nil
    var batchID: UUID? = nil
    var seriesID: UUID? = nil
    var variationSeed: Int? = nil
    /// Short locked theme shown in the library; full text lives in `resolvedPrompt`.
    var coreKeywords: String? = nil
}

struct GenerationRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var request: GenerationRequest
    var state: GenerationState
    var imagePath: String?
    var isFavorite: Bool
    var feedback: String?
    var errorMessage: String?
    var updatedAt: Date
    var tags: [String]? = nil
    var tagSummary: String? = nil
    /// Soft-delete timestamp; non-nil means the artwork sits in the trash.
    var trashedAt: Date? = nil

    var resolvedTags: [String] { tags ?? [] }
    var isTrashed: Bool { trashedAt != nil }

    var hasUsableImageFile: Bool {
        guard let imagePath, !imagePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: imagePath)
    }

    var createdAt: Date { request.createdAt }
}
