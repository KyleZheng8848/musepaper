import Foundation

enum PromptAPIFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case responses = "OpenAI Responses"
    case chatCompletions = "OpenAI-compatible Chat"
    case anthropicMessages = "Anthropic Messages"

    var id: String { rawValue }
}

enum PromptAgentModelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed = "固定一个"
    case random = "随机一个"

    var id: String { rawValue }
}

/// One selectable Agent target: vendor connection + concrete model name.
struct PromptAgentModelRef: Codable, Hashable, Identifiable, Sendable {
    var configurationID: UUID
    var model: String

    var id: String { "\(configurationID.uuidString)::\(model)" }

    init(configurationID: UUID, model: String) {
        self.configurationID = configurationID
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PromptAgentRouting: Codable, Equatable, Sendable {
    var enabled: Bool
    var mode: PromptAgentModelMode
    /// Pool for Agent (fixed uses `activeRef`; random picks from this list).
    var eligibleRefs: [PromptAgentModelRef]
    var activeRef: PromptAgentModelRef?

    init(
        enabled: Bool = false,
        mode: PromptAgentModelMode = .fixed,
        eligibleRefs: [PromptAgentModelRef] = [],
        activeRef: PromptAgentModelRef? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.eligibleRefs = eligibleRefs
        self.activeRef = activeRef
    }

    enum CodingKeys: String, CodingKey {
        case enabled, mode, eligibleRefs, activeRef
        case eligibleModelIDs, activeModelID // legacy
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try box.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try box.decodeIfPresent(PromptAgentModelMode.self, forKey: .mode) ?? .fixed
        if let refs = try box.decodeIfPresent([PromptAgentModelRef].self, forKey: .eligibleRefs) {
            eligibleRefs = refs
        } else {
            let legacyIDs = try box.decodeIfPresent([UUID].self, forKey: .eligibleModelIDs) ?? []
            eligibleRefs = legacyIDs.map { PromptAgentModelRef(configurationID: $0, model: "") }
        }
        if let ref = try box.decodeIfPresent(PromptAgentModelRef.self, forKey: .activeRef) {
            activeRef = ref
        } else if let legacyID = try box.decodeIfPresent(UUID.self, forKey: .activeModelID) {
            activeRef = PromptAgentModelRef(configurationID: legacyID, model: "")
        } else {
            activeRef = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(enabled, forKey: .enabled)
        try box.encode(mode, forKey: .mode)
        try box.encode(eligibleRefs, forKey: .eligibleRefs)
        try box.encodeIfPresent(activeRef, forKey: .activeRef)
    }

    static func migrating(from legacy: PromptModelConfiguration) -> (configs: [PromptModelConfiguration], routing: PromptAgentRouting) {
        var config = legacy
        let enabled = config.enabled
        config.enabled = false
        let models = config.resolvedModels
        let refs = models.map { PromptAgentModelRef(configurationID: config.id, model: $0) }
        return (
            [config],
            PromptAgentRouting(
                enabled: enabled,
                mode: .fixed,
                eligibleRefs: refs,
                activeRef: refs.first
            )
        )
    }

    mutating func ensureConsistency(with configurations: [PromptModelConfiguration]) {
        let byID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
        // Fill blank model names left by legacy UUID-only refs.
        eligibleRefs = eligibleRefs.compactMap { ref in
            guard let config = byID[ref.configurationID] else { return nil }
            let models = config.resolvedModels
            if ref.model.isEmpty {
                return models.first.map { PromptAgentModelRef(configurationID: config.id, model: $0) }
            }
            guard models.contains(ref.model) else { return nil }
            return ref
        }
        if let active = activeRef {
            if let config = byID[active.configurationID] {
                let models = config.resolvedModels
                if active.model.isEmpty, let first = models.first {
                    activeRef = PromptAgentModelRef(configurationID: config.id, model: first)
                } else if !models.contains(active.model) {
                    activeRef = nil
                }
            } else {
                activeRef = nil
            }
        }
        if activeRef == nil {
            activeRef = eligibleRefs.first ?? configurations.flatMap(\.agentModelRefs).first
        }
        if eligibleRefs.isEmpty, let active = activeRef {
            eligibleRefs = [active]
        }
        if mode == .fixed, let active = activeRef, !eligibleRefs.contains(active) {
            eligibleRefs.append(active)
        }
        // Drop duplicate refs.
        var seen = Set<String>()
        eligibleRefs = eligibleRefs.filter { seen.insert($0.id).inserted }
    }
}

struct PromptModelConfiguration: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Legacy per-config flag; global Agent on/off lives in `PromptAgentRouting.enabled`.
    var enabled: Bool
    /// Vendor / provider display name, e.g. AntChat · OpenAI.
    var name: String
    var baseURL: String
    /// Model id list under this vendor connection (same Base URL + AK).
    var models: [String]
    var apiFormat: PromptAPIFormat
    var timeoutSeconds: Int

    init(
        id: UUID = UUID(),
        enabled: Bool = false,
        name: String = "OpenAI",
        baseURL: String = "https://api.openai.com/v1",
        model: String = "gpt-5.6-terra",
        models: [String]? = nil,
        apiFormat: PromptAPIFormat = .responses,
        timeoutSeconds: Int = 90
    ) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.baseURL = baseURL
        let seed = models ?? [model]
        self.models = Self.normalizedModelList(seed)
        self.apiFormat = apiFormat
        self.timeoutSeconds = min(max(timeoutSeconds, 20), 300)
    }

    enum CodingKeys: String, CodingKey {
        case id, enabled, name, baseURL, model, models, apiFormat, timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try box.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? "OpenAI"
        baseURL = try box.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.openai.com/v1"
        apiFormat = try box.decodeIfPresent(PromptAPIFormat.self, forKey: .apiFormat) ?? .responses
        timeoutSeconds = try box.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 90
        if let list = try box.decodeIfPresent([String].self, forKey: .models), !list.isEmpty {
            models = Self.normalizedModelList(list)
        } else if let single = try box.decodeIfPresent(String.self, forKey: .model) {
            models = Self.normalizedModelList([single])
        } else {
            models = ["gpt-5.6-terra"]
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(enabled, forKey: .enabled)
        try box.encode(name, forKey: .name)
        try box.encode(baseURL, forKey: .baseURL)
        try box.encode(models, forKey: .models)
        // Keep legacy single-model field for older readers / PromptAgent helpers.
        try box.encode(model, forKey: .model)
        try box.encode(apiFormat, forKey: .apiFormat)
        try box.encode(timeoutSeconds, forKey: .timeoutSeconds)
    }

    /// First / primary model id (API calls override this per selection).
    var model: String {
        get { resolvedModels.first ?? "" }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return }
            if models.isEmpty {
                models = [cleaned]
            } else {
                models[0] = cleaned
                models = Self.normalizedModelList(models)
            }
        }
    }

    var resolvedModels: [String] { Self.normalizedModelList(models) }

    var vendorName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.inferredVendorName(for: baseURL)
    }

    var displayName: String { vendorName }

    var agentModelRefs: [PromptAgentModelRef] {
        resolvedModels.map { PromptAgentModelRef(configurationID: id, model: $0) }
    }

    func selectionLabel(forModel modelName: String) -> String {
        "\(vendorName):\(modelName)"
    }

    /// Same host can share one AK across model names on this connection.
    var credentialAffinityKey: String {
        Self.credentialAffinityKey(for: baseURL)
    }

    static func credentialAffinityKey(for baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmed)?.host?.lowercased(), !host.isEmpty {
            return host
        }
        return trimmed.lowercased()
    }

    static func inferredVendorName(for baseURL: String) -> String {
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        if host.contains("anthropic.com") { return "Anthropic" }
        if host.contains("api.openai.com") { return "OpenAI" }
        if host.contains("alipay.com") || host.contains("antchat") { return "AntChat" }
        if host.contains("theta") { return "Theta" }
        if !host.isEmpty {
            return host.split(separator: ".").prefix(1).map(String.init).joined()
        }
        return "文本厂商"
    }

    static func normalizedModelList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }

    func validated() throws -> PromptModelConfiguration {
        var aligned = aligningFormatToHost()
        aligned.models = Self.normalizedModelList(aligned.models)
        guard let url = URL(string: aligned.baseURL), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host else {
            throw MusepaperError.invalidConfiguration("Prompt Agent Base URL 必须是完整的 HTTP(S) 地址")
        }
        if scheme == "http", !["localhost", "127.0.0.1", "::1"].contains(host.lowercased()) {
            throw MusepaperError.invalidConfiguration("远程 Prompt Agent 必须使用 HTTPS")
        }
        guard !aligned.resolvedModels.isEmpty else {
            throw MusepaperError.invalidConfiguration("至少填写一个文本模型名称")
        }
        if aligned.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            aligned.name = Self.inferredVendorName(for: aligned.baseURL)
        }
        return aligned
    }

    func aligningFormatToHost() -> PromptModelConfiguration {
        var copy = self
        copy.apiFormat = Self.inferredFormat(for: baseURL, current: apiFormat)
        return copy
    }

    func withSelectedModel(_ modelName: String) -> PromptModelConfiguration {
        var copy = self
        let cleaned = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            if !copy.resolvedModels.contains(cleaned) {
                copy.models.append(cleaned)
                copy.models = Self.normalizedModelList(copy.models)
            }
            // Move selected model to front so `model` reflects the pick.
            copy.models.removeAll { $0 == cleaned }
            copy.models.insert(cleaned, at: 0)
        }
        return copy
    }

    static func inferredFormat(for baseURL: String, current: PromptAPIFormat) -> PromptAPIFormat {
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        if host.contains("anthropic.com") { return .anthropicMessages }
        if host.contains("api.openai.com") { return .responses }
        if host.contains("alipay.com") || host.contains("antchat") { return .chatCompletions }
        return current
    }

    var endpointPath: String {
        switch apiFormat {
        case .responses: "responses"
        case .chatCompletions: "chat/completions"
        case .anthropicMessages: "messages"
        }
    }
}

struct PromptEnhancementContext: Equatable, Sendable {
    var rawPrompt: String
    var deterministicPrompt: String
    var channelName: String?
    var channelEssence: String?
    var requiredElements: String?
    var excludedElements: String
    var palette: String?
    var emptySpace: String
    var displayWidth: Int
    var displayHeight: Int
    var referenceImageCount: Int
    var coreKeywords: String = ""
    var variationAxes: String = ""
    var variationSeed: Int? = nil
    var promptStrategy: String? = nil
    var dimensionCombo: String = ""
    var frameIndex: Int = 0
    var frameCount: Int = 1

    /// Build context off the main actor for parallel polish workers.
    static func makeParallel(
        idea: String,
        themeSource: String,
        deterministic: String,
        channel: InspirationChannel?,
        draft: PromptDraft,
        display: DisplayProfile,
        seed: Int,
        dimensionCombo: String,
        referenceImageCount: Int
    ) -> PromptEnhancementContext {
        let composer = PromptComposer()
        let resolvedChannel = channel.flatMap { $0.isSchemaTemplate ? nil : $0 }
        let raw = composer.userCore(idea: idea, channel: resolvedChannel)
        var exclusions = [draft.negative, resolvedChannel?.exclude ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "、")
        if composer.allowsVisibleFigure(raw) {
            exclusions = exclusions
                .split(whereSeparator: { "、,，;；/".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { value in
                    let compact = value.replacingOccurrences(of: " ", with: "")
                    return !["人物", "人像", "人", "people", "person", "human"].contains(compact.lowercased())
                }
                .joined(separator: "、")
        }
        return PromptEnhancementContext(
            rawPrompt: raw,
            deterministicPrompt: composer.usableVisual(deterministic) ?? raw,
            channelName: composer.usableVisual(resolvedChannel?.name ?? ""),
            channelEssence: composer.usableVisual(resolvedChannel?.essence ?? ""),
            requiredElements: composer.usableVisual(resolvedChannel?.mustInclude ?? ""),
            excludedElements: exclusions,
            palette: composer.usableVisual(resolvedChannel?.palette ?? ""),
            emptySpace: draft.emptySpace.rawValue,
            displayWidth: display.width,
            displayHeight: display.height,
            referenceImageCount: referenceImageCount,
            coreKeywords: themeSource.isEmpty ? raw : themeSource,
            variationAxes: composer.usableVisual(resolvedChannel?.resolvedVariationAxes ?? "") ?? "",
            variationSeed: seed,
            promptStrategy: resolvedChannel?.resolvedPromptStrategy.rawValue,
            dimensionCombo: composer.usableVisual(dimensionCombo) ?? ""
        )
    }
}
