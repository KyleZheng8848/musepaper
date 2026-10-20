import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case demo = "离线演示"
    case openAI = "OpenAI"
    case compatible = "OpenAI-compatible"
    var id: String { rawValue }
}

enum ImageQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high, auto
    var id: String { rawValue }
}

enum GeneratedImageSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case square = "1024x1024"
    case landscape = "1536x1024"
    case portrait = "1024x1536"
    /// Qwen-Image native-ish 16:9 — sharper than OpenAI's 1536×1024 on Retina desks.
    case qwenLandscape = "1664x928"
    case qwenLandscapeHD = "2048x1152"
    case qwenSquare = "1328x1328"
    case qwenPortrait = "928x1664"

    var id: String { rawValue }

    var pixelWidth: Int {
        switch self {
        case .automatic: return 0
        case .square: return 1024
        case .landscape: return 1536
        case .portrait: return 1024
        case .qwenLandscape: return 1664
        case .qwenLandscapeHD: return 2048
        case .qwenSquare: return 1328
        case .qwenPortrait: return 928
        }
    }

    var pixelHeight: Int {
        switch self {
        case .automatic: return 0
        case .square: return 1024
        case .landscape: return 1024
        case .portrait: return 1536
        case .qwenLandscape: return 928
        case .qwenLandscapeHD: return 1152
        case .qwenSquare: return 1328
        case .qwenPortrait: return 1664
        }
    }

    var pixelCount: Int { pixelWidth * pixelHeight }

    /// Simplified aspect ratio for menus, e.g. `16:9`, `1:1`.
    var aspectRatioLabel: String {
        switch self {
        case .automatic: return ""
        case .square, .qwenSquare: return "1:1"
        case .landscape: return "3:2"
        case .portrait: return "2:3"
        case .qwenLandscape, .qwenLandscapeHD: return "16:9"
        case .qwenPortrait: return "9:16"
        }
    }

    var menuLabel: String {
        switch self {
        case .automatic:
            return "auto（仅官方 OpenAI）"
        default:
            return "\(pixelWidth)×\(pixelHeight) · \(aspectRatioLabel)"
        }
    }

    /// Menu order: auto first, then ascending by pixel area (ties: wider first).
    static var menuOrdered: [GeneratedImageSize] {
        allCases.sorted { lhs, rhs in
            if lhs == .automatic { return true }
            if rhs == .automatic { return false }
            if lhs.pixelCount != rhs.pixelCount {
                return lhs.pixelCount < rhs.pixelCount
            }
            if lhs.pixelWidth != rhs.pixelWidth {
                return lhs.pixelWidth > rhs.pixelWidth
            }
            return lhs.rawValue < rhs.rawValue
        }
    }
}

enum ImageOutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png, jpeg, webp
    var id: String { rawValue }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

struct ImageRoute: Codable, Equatable, Sendable {
    var configurationID: UUID
    var baseURL: String
    var model: String
    var provider: ProviderKind

    var host: String { URL(string: baseURL)?.host ?? baseURL }
    var generationsURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/images/generations"
    }

    static func normalizedURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    func matches(_ configuration: ModelConfiguration) -> Bool {
        configurationID == configuration.id
            && model == configuration.model
            && Self.normalizedURL(baseURL) == Self.normalizedURL(configuration.baseURL)
    }

    static func from(_ configuration: ModelConfiguration) -> ImageRoute {
        ImageRoute(
            configurationID: configuration.id,
            baseURL: configuration.baseURL,
            model: configuration.model,
            provider: configuration.provider
        )
    }
}

struct ModelConfiguration: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var provider: ProviderKind
    var baseURL: String
    var model: String
    var quality: ImageQuality
    var size: GeneratedImageSize
    var outputFormat: ImageOutputFormat
    var imageCount: Int
    var timeoutSeconds: Int

    init(
        id: UUID = UUID(), name: String = "OpenAI · GPT Image 2", provider: ProviderKind = .openAI,
        baseURL: String = "https://api.openai.com/v1", model: String = "gpt-image-2",
        quality: ImageQuality = .medium, size: GeneratedImageSize = .landscape,
        outputFormat: ImageOutputFormat = .png, imageCount: Int = 1, timeoutSeconds: Int = 180
    ) {
        self.id = id; self.name = name; self.provider = provider; self.baseURL = baseURL
        self.model = model; self.quality = quality; self.size = size; self.outputFormat = outputFormat
        self.imageCount = min(max(imageCount, 1), 4); self.timeoutSeconds = min(max(timeoutSeconds, 30), 600)
    }

    static let demo = ModelConfiguration(name: "离线演示", provider: .demo, baseURL: "", model: "demo-renderer", quality: .medium)

    func validated() throws -> ModelConfiguration {
        if provider != .demo {
            guard let url = URL(string: baseURL), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), let host = url.host else {
                throw MusepaperError.invalidConfiguration("Base URL 必须是完整的 HTTP(S) 地址")
            }
            if scheme == "http", !["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
                throw MusepaperError.invalidConfiguration("远程 Provider 必须使用 HTTPS；HTTP 仅允许本机服务")
            }
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MusepaperError.invalidConfiguration("模型名称不能为空")
            }
        }
        return self
    }
}
