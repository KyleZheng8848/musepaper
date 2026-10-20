import Foundation

struct PromptAgent: Sendable {
    let configuration: PromptModelConfiguration
    let apiKey: String
    let session: URLSession

    init(configuration: PromptModelConfiguration, apiKey: String, session: URLSession? = nil) throws {
        self.configuration = try configuration.validated()
        let key = OpenAIImageProvider.sanitizeAPIKey(apiKey)
        guard !key.isEmpty else { throw MusepaperError.missingAPIKey }
        self.apiKey = key
        if let session {
            self.session = session
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.timeoutIntervalForRequest = TimeInterval(min(configuration.timeoutSeconds, 45))
            settings.timeoutIntervalForResource = TimeInterval(min(configuration.timeoutSeconds, 45) + 15)
            settings.waitsForConnectivity = false
            self.session = URLSession(configuration: settings)
        }
    }

    func enhance(_ context: PromptEnhancementContext) async throws -> String {
        let composer = PromptComposer()
        let theme = composer.usableVisual(context.coreKeywords)
            ?? composer.usableVisual(context.rawPrompt)
            ?? ""
        let seed = context.variationSeed ?? theme.hashValue
        let dialect = ImagePromptDialect.infer(from: context.imageModel)
        let request = try buildRequest(
            system: Self.systemPrompt(for: dialect),
            input: Self.visualUserInput(context),
            maxTokens: dialect == .llada ? 160 : 900
        )
        let data = try await perform(request)
        let text = try extractText(from: data)
        let rawText = clean(text)
        if composer.isSchemaPlaceholder(rawText) {
            throw MusepaperError.invalidResponse("Prompt Agent 回传了说明书而不是纯画面描述")
        }
        let cleaned = composer.enforcePureArtwork(rawText)
        let spoken = composer.finishAgentPrompt(cleaned, core: theme, seed: seed, model: context.imageModel)
        if spoken.count < 12 {
            if theme.count >= 4 {
                return composer.finishAgentPrompt(theme, core: theme, seed: seed, model: context.imageModel)
            }
            throw MusepaperError.invalidResponse("Prompt Agent 返回内容过短")
        }
        if composer.containsInstructionLeak(spoken) {
            if theme.count >= 4 {
                return composer.finishAgentPrompt(theme, core: theme, seed: seed, model: context.imageModel)
            }
            throw MusepaperError.invalidResponse("Prompt Agent 回传了说明书而不是纯画面描述")
        }
        return spoken
    }

    func expandBlueprint(idea: String) async throws -> WallpaperBlueprintSuggestion {
        let cleaned = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw MusepaperError.emptyPrompt }
        let request = try buildRequest(system: Self.blueprintSystemPrompt, input: "用户想设计的壁纸系列：\(cleaned)")
        let data = try await perform(request)
        let raw = try extractText(from: data)
        let jsonText = cleanJSON(raw)
        guard let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any] else {
            throw MusepaperError.invalidResponse("Prompt Agent 没有返回可解析的壁纸蓝图")
        }
        func string(_ key: String) -> String { (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let suggestion = WallpaperBlueprintSuggestion(
            name: string("name"), essence: string("essence"), coreKeywords: string("core_keywords"),
            variationAxes: string("variation_axes"), palette: string("palette"), exclusions: string("exclusions")
        )
        guard !suggestion.essence.isEmpty, !suggestion.coreKeywords.isEmpty else {
            throw MusepaperError.invalidResponse("壁纸蓝图缺少审美内核或核心词")
        }
        let composer = PromptComposer()
        if composer.isSchemaPlaceholder(suggestion.name)
            || composer.isSchemaPlaceholder(suggestion.essence)
            || composer.isSchemaPlaceholder(suggestion.coreKeywords)
        {
            throw MusepaperError.invalidResponse("壁纸蓝图还是说明书模板，请换一个具体主题再试")
        }
        return suggestion
    }

    func suggestTags(prompt: String, taskName: String?, imageJPEG: Data? = nil) async throws -> [String] {
        let hasImage = imageJPEG != nil
        var lines = [
            "来源任务：\(taskName ?? "自由创作")",
            "最终图片 Prompt：\(prompt.isEmpty ? "（无文字 Prompt，请以图片为准）" : prompt)"
        ]
        if hasImage {
            lines.append("已附带压缩预览图。请以画面可见内容为主打标签，文字 Prompt 仅作参考。")
        }
        let request = try buildRequest(
            system: Self.taggingSystemPrompt,
            input: lines.joined(separator: "\n"),
            imageJPEG: imageJPEG,
            maxTokens: 320
        )
        let data = try await perform(request)
        let raw = cleanJSON(try extractText(from: data))
        guard let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let values = object["tags"] as? [String] else {
            throw MusepaperError.invalidResponse("Agent 没有返回可解析的作品标签")
        }
        let tags = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tags.isEmpty else { throw MusepaperError.invalidResponse("Agent 返回的作品标签为空") }
        return Array(NSOrderedSet(array: tags).compactMap { $0 as? String }.prefix(12))
    }

    func testConnection() async throws {
        let request = try buildRequest(
            system: "只用一句话描写能看见的画面，不要解释。",
            input: "海边灯塔",
            maxTokens: 32
        )
        let data = try await perform(request)
        let text = try extractText(from: data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MusepaperError.invalidResponse("模型没有返回文本")
        }
    }

    private func buildRequest(
        system: String,
        input: String,
        imageJPEG: Data? = nil,
        maxTokens: Int = 900
    ) throws -> URLRequest {
        var request = URLRequest(url: try endpoint())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Musepaper/0.2", forHTTPHeaderField: "User-Agent")
        let body: [String: Any]
        let imageB64 = imageJPEG.map { $0.base64EncodedString() }
        switch configuration.apiFormat {
        case .responses:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let userContent: Any
            if let imageB64 {
                userContent = [
                    [
                        "role": "user",
                        "content": [
                            ["type": "input_text", "text": input],
                            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(imageB64)"]
                        ]
                    ]
                ]
            } else {
                userContent = input
            }
            body = [
                "model": configuration.model,
                "instructions": system,
                "input": userContent,
                "reasoning": ["effort": "low"],
                "text": ["verbosity": "low"],
                "max_output_tokens": maxTokens
            ]
        case .chatCompletions:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let userContent: Any
            if let imageB64 {
                userContent = [
                    ["type": "text", "text": input],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageB64)"]]
                ]
            } else {
                userContent = input
            }
            body = [
                "model": configuration.model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userContent]
                ],
                "max_tokens": maxTokens
            ]
        case .anthropicMessages:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let userContent: Any
            if let imageB64 {
                userContent = [
                    [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": imageB64
                        ]
                    ],
                    ["type": "text", "text": input]
                ]
            } else {
                userContent = input
            }
            body = [
                "model": configuration.model,
                "system": system,
                "messages": [["role": "user", "content": userContent]],
                "max_tokens": maxTokens
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func endpoint() throws -> URL {
        let raw = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: raw) else {
            throw MusepaperError.invalidConfiguration("Prompt Agent Base URL 无法解析")
        }
        let existing = components.path.split(separator: "/").map(String.init)
        let suffix = configuration.endpointPath.split(separator: "/").map(String.init)
        if existing.suffix(suffix.count) != suffix {
            components.path = "/" + (existing + suffix).joined(separator: "/")
        }
        guard let url = components.url else { throw MusepaperError.invalidConfiguration("Prompt Agent 请求地址无法构建") }
        return url
    }

    /// Facts only. Never send “Those characters / This frame differs / Keep them” —
    /// LLaDA paints those words onto the wallpaper.
    static func visualUserInput(_ context: PromptEnhancementContext) -> String {
        let composer = PromptComposer()
        let theme = composer.usableVisual(context.rawPrompt) ?? ""
        let essence = composer.usableVisual(context.channelEssence ?? "") ?? ""
        let include = composer.usableVisual(context.requiredElements ?? "") ?? ""
        let palette = composer.usableVisual(context.palette ?? "") ?? ""
        let keywords = composer.usableVisual(context.coreKeywords) ?? ""
        let subject = keywords.isEmpty ? theme : keywords
        let core = subject.isEmpty ? theme : subject
        let seed = context.variationSeed ?? context.frameIndex
        let plan = composer.framePlan(core: core, seed: seed, model: context.imageModel)
        let frame = composer.promptFrame(core: core, seed: seed)
        var lines = [
            "主题：\(core)",
            "光：\(frame.light)",
            "看：\(frame.view)"
        ]
        let dialect = ImagePromptDialect.infer(from: context.imageModel)
        if !essence.isEmpty, essence != subject {
            lines.append("气味：\(essence)")
        }
        if !include.isEmpty {
            lines.append("还要看见：\(include)")
        }
        if !palette.isEmpty {
            lines.append("颜色：\(palette)")
        }
        let alignedCombo = composer.alignVariationHint(context.dimensionCombo, to: plan)
        if !alignedCombo.isEmpty {
            let hint = dialect == .llada ? composer.shortVisualClause(alignedCombo) : alignedCombo
            if !hint.isEmpty {
                lines.append("这一张多看见：\(hint)")
            }
        }
        switch context.emptySpace {
        case "左侧留白": lines.append("左边松一点")
        case "右侧留白": lines.append("右边松一点")
        case "中央留白": lines.append("中间松一点")
        default: break
        }
        return lines.joined(separator: "\n")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            if error.code == .timedOut { throw MusepaperError.networkFailed("Prompt Agent 请求超时") }
            throw MusepaperError.networkFailed(error.localizedDescription)
        } catch { throw MusepaperError.networkFailed(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw MusepaperError.invalidResponse("Prompt Agent 缺少 HTTP 状态") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw MusepaperError.unauthorized
        case 402: throw MusepaperError.paymentRequired
        case 429: throw MusepaperError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data.prefix(600), encoding: .utf8)
                ?? "未知错误"
            throw MusepaperError.generationFailed("Prompt Agent HTTP \(http.statusCode)：\(message)")
        }
    }

    private func extractText(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MusepaperError.invalidResponse("Prompt Agent 响应不是 JSON")
        }
        if let direct = root["output_text"] as? String, !direct.isEmpty { return direct }
        if let output = root["output"] as? [[String: Any]] {
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                for block in content {
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                }
            }
        }
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.isEmpty { return content }
            if let blocks = message["content"] as? [[String: Any]] {
                for block in blocks {
                    if let text = block["text"] as? String, !text.isEmpty { return text }
                    if let text = block["content"] as? String, !text.isEmpty { return text }
                }
            }
            if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty { return reasoning }
        }
        if let content = root["content"] as? [[String: Any]] {
            for block in content {
                if let text = block["text"] as? String, !text.isEmpty { return text }
            }
        }
        throw MusepaperError.invalidResponse("Prompt Agent 响应中没有文本")
    }

    private func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.replacingOccurrences(of: "```text", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func cleanJSON(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = value.firstIndex(of: "{"), let end = value.lastIndex(of: "}") else { return value }
        return String(value[start...end])
    }

    static var systemPrompt: String { systemPrompt(for: .generic) }

    static func systemPrompt(for dialect: ImagePromptDialect) -> String {
        switch dialect {
        case .llada:
            return """
            只输出一句画面。
            一张电影感照片，<主题原词>，<光>，<远近或质感>
            中文专名原样留下。只写看得见的东西。
            """
        case .qwen, .generic:
            return """
            写成 1 到 3 句画面。
            中文专名原样留下。只输出画面。
            """
        }
    }

    static let blueprintSystemPrompt = """
    你是壁纸系列设计师。把用户的一句话想法拆成可长期生成变体的设计蓝图。
    区分不可变内核与可变维度：不可变内核锁定主体身份、情绪、艺术语言和关键视觉符号。
    人物/人像主题：内核必须锁人物身份与气质；exclusions 不要默认写「人物」；variation_axes 用 姿态/景别/光线/服饰质感/背景虚化，不要套城市空镜轴。
    纯心情/季节主题：内核只锁心情词；exclusions 不要写「人物」；variation_axes 必须含 看见什么：空场/人/静物/室内，禁止整批空院子或整批补人。
    variation_axes 必须按主题选轴，禁止所有主题都套「国内城市/国外城市」。
    城市风景用 地点/景别/气候/镜头；宇宙用 轨道位置/观察点/天文现象/尺度；魔幻、海岸、山林、室内、人像、心情各自换轴。
    每个轴给 3–5 个维度档位，不要写要新增的物件。格式“维度：选项/选项/选项；维度：...”。
    禁止把孤树、路灯、玻璃幕墙、钟楼、船、房子写成轴上的选项。
    只输出一个 JSON 对象，不使用 Markdown。字段必须是维度词，禁止回传模板词。
    {"name":"雨夜城","essence":"潮湿安静的未来都会","core_keywords":"湿沥青,霓虹倒影","variation_axes":"天气：雨/雾；景别：街巷/天际线；色温：冷青/琥珀","palette":"青蓝,暖窗","exclusions":"文字,水印"}
    """

    static let taggingSystemPrompt = """
    你是 Musepaper 的作品策展 Agent。为作品生成 6–10 个短标签，供智能作品集筛选和壁纸轮播使用。
    若附带了图片，必须以画面可见内容为主；文字 Prompt 只作参考。没有图片时才完全依赖文字。
    标签应覆盖：主体/场景、情绪、色彩、天气、时段、视觉风格与构图特征；只标注有依据的内容，不要写完整句子。
    统一使用简短中文标签，避免同义词重复。只输出 JSON：{"tags":["标签1","标签2"]}
    """
}
