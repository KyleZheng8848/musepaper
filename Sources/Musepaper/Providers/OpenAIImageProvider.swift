import Foundation

struct OpenAIImageProvider: ImageProvider {
    let configuration: ModelConfiguration
    let apiKey: String
    let session: URLSession
    var name: String { configuration.name }

    init(configuration: ModelConfiguration, apiKey: String, session: URLSession? = nil) throws {
        self.configuration = try configuration.validated()
        let key = Self.sanitizeAPIKey(apiKey)
        guard !key.isEmpty else { throw MusepaperError.missingAPIKey }
        self.apiKey = key
        if let session { self.session = session }
        else {
            let settings = URLSessionConfiguration.ephemeral
            settings.timeoutIntervalForRequest = TimeInterval(configuration.timeoutSeconds)
            settings.timeoutIntervalForResource = TimeInterval(configuration.timeoutSeconds + 30)
            settings.waitsForConnectivity = false
            self.session = URLSession(configuration: settings)
        }
    }

    func testConnection() async throws {
        let dialect = Self.imageAPIDialect(baseURL: configuration.baseURL)
        // AntChat / many gateways list chat models only; a missing image name must not
        // block the real /images/generations probe.
        if dialect != .antchat {
            let available = try await listModelIDs()
            let wanted = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !available.isEmpty, !available.contains(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) {
                let sample = available.filter {
                    $0.localizedCaseInsensitiveContains("image") || $0.localizedCaseInsensitiveContains("vision")
                }.prefix(6)
                let hint = sample.isEmpty
                    ? available.prefix(6).joined(separator: "、")
                    : sample.joined(separator: "、")
                throw MusepaperError.generationFailed(
                    "这把令牌（\(Self.fingerprint(apiKey))）在 \(configuration.baseURL) 上能列到 \(available.count) 个模型，但没有「\(wanted)」。常见原因：误存了只开对话的令牌。本机有图像权限的钥指纹请对照一下。列表里可见：\(hint)"
                )
            }
        }
        if Self.looksLikeChatModel(configuration.model) {
            throw MusepaperError.invalidConfiguration(
                "「\(configuration.model)」像对话模型。文生图请填图像模型名（例如 Qwen-Image-2512-Lightning），不要填 Hy3 / GPT。"
            )
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-probe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var probeConfig = configuration
        // Keep the probe small and fast — full wallpaper timeout is wrong for “save & test”.
        probeConfig.size = dialect == .antchat ? .landscape : .square
        probeConfig.timeoutSeconds = min(configuration.timeoutSeconds, 45)
        let probeProvider = try OpenAIImageProvider(configuration: probeConfig, apiKey: apiKey, session: session)
        let probe = GenerationRequest(
            id: UUID(), rawInput: "probe", resolvedPrompt: "solid dark blue field",
            negativePrompt: "", display: .preview, createdAt: Date()
        )
        _ = try await probeProvider.generate(probe, outputDirectory: folder)
    }

    func listModelIDs() async throws -> [String] {
        var request = URLRequest(url: try endpoint("models"))
        request.httpMethod = "GET"
        authorize(&request)
        let data = try await perform(request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let rows = root["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            (row["id"] as? String) ?? (row["name"] as? String)
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func fingerprint(_ key: String) -> String {
        let trimmed = sanitizeAPIKey(key)
        guard trimmed.count >= 8 else { return "过短(\(trimmed.count))" }
        return "\(trimmed.prefix(4))…\(trimmed.suffix(4))·\(trimmed.count)位"
    }

    static func sanitizeAPIKey(_ key: String) -> String {
        var value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bearer ") {
            value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generate(_ request: GenerationRequest, outputDirectory: URL) async throws -> [URL] {
        let references = (request.referenceImagePaths ?? []).map(URL.init(fileURLWithPath:))
        var urlRequest: URLRequest
        if references.isEmpty {
            urlRequest = URLRequest(url: try endpoint("images/generations"))
            urlRequest.httpMethod = "POST"
            authorize(&urlRequest)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let dialect = Self.imageAPIDialect(baseURL: configuration.baseURL)
            let body = ImageGenerationBody(
                model: configuration.model,
                prompt: promptForImageModel(request),
                n: configuration.imageCount,
                size: Self.normalizedSize(configuration.size, dialect: dialect),
                quality: configuration.quality.rawValue,
                outputFormat: configuration.outputFormat.rawValue,
                negativePrompt: sendsNegativePrompt ? request.negativePrompt : nil,
                dialect: dialect
            )
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } else {
            urlRequest = try multipartEditRequest(request: request, references: references)
        }
        let data = try await perform(urlRequest)
        let response: ImageGenerationResponse
        do { response = try JSONDecoder().decode(ImageGenerationResponse.self, from: data) }
        catch { throw MusepaperError.invalidResponse("图片响应 JSON 解析失败：\(error.localizedDescription)") }
        guard !response.data.isEmpty else { throw MusepaperError.invalidResponse("响应中没有图片") }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, item) in response.data.enumerated() {
            let imageData: Data
            if let encoded = item.b64JSON, let decoded = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
                imageData = decoded
            } else if let remote = item.url, let remoteURL = URL(string: remote) {
                do { imageData = try await session.data(from: remoteURL).0 }
                catch { throw MusepaperError.networkFailed("图片下载失败：\(error.localizedDescription)") }
            } else {
                throw MusepaperError.invalidResponse("第 \(index + 1) 张图片缺少 b64_json 或 url")
            }
            guard !imageData.isEmpty else { throw MusepaperError.invalidResponse("第 \(index + 1) 张图片为空") }
            let url = outputDirectory.appendingPathComponent("\(request.id.uuidString)-\(index + 1).\(configuration.outputFormat.fileExtension)")
            try imageData.write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }

    private func multipartEditRequest(request: GenerationRequest, references: [URL]) throws -> URLRequest {
        let boundary = "Musepaper-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        let dialect = Self.imageAPIDialect(baseURL: configuration.baseURL)
        var fields = [
            "model": configuration.model,
            "prompt": promptForImageModel(request),
            "size": Self.normalizedSize(configuration.size, dialect: dialect)
        ]
        switch dialect {
        case .officialOpenAI:
            fields["n"] = String(configuration.imageCount)
            fields["quality"] = configuration.quality.rawValue
            fields["output_format"] = configuration.outputFormat.rawValue
        case .antchat:
            fields["response_format"] = "b64_json"
            fields["output_format"] = configuration.outputFormat.rawValue
        case .compatible:
            fields["n"] = String(configuration.imageCount)
            fields["response_format"] = "b64_json"
            fields["output_format"] = configuration.outputFormat.rawValue
        }
        if sendsNegativePrompt {
            let negative = request.negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !negative.isEmpty { fields["negative_prompt"] = negative }
        }
        for key in fields.keys.sorted() {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n")
        }
        for url in references.prefix(8) {
            guard FileManager.default.fileExists(atPath: url.path) else { throw MusepaperError.invalidConfiguration("参考图片不存在：\(url.lastPathComponent)") }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty, data.count <= 25 * 1024 * 1024 else { throw MusepaperError.invalidConfiguration("参考图片为空或超过 25 MB：\(url.lastPathComponent)") }
            let mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"][url.pathExtension.lowercased()] ?? "image/png"
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"\(url.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n")
            body.append(data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        var result = URLRequest(url: try endpoint("images/edits"))
        result.httpMethod = "POST"
        authorize(&result)
        result.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        result.httpBody = body
        return result
    }

    var sendsNegativePrompt: Bool {
        Self.shouldSendNegativePrompt(provider: configuration.provider, baseURL: configuration.baseURL)
    }

    func promptForImageModel(_ request: GenerationRequest) -> String {
        PromptComposer().imageModelPrompt(
            request.resolvedPrompt,
            core: request.coreKeywords ?? request.rawInput,
            seed: request.variationSeed ?? request.resolvedPrompt.hashValue
        )
    }

    static func shouldSendNegativePrompt(provider: ProviderKind, baseURL: String) -> Bool {
        if provider == .compatible { return true }
        return imageAPIDialect(baseURL: baseURL) != .officialOpenAI
    }

    static func usesOfficialOpenAIImageAPI(baseURL: String) -> Bool {
        imageAPIDialect(baseURL: baseURL) == .officialOpenAI
    }

    enum ImageAPIDialect: Equatable, Sendable {
        case officialOpenAI
        case antchat
        case compatible
    }

    static func imageAPIDialect(baseURL: String) -> ImageAPIDialect {
        let host = (URL(string: baseURL)?.host ?? baseURL).lowercased()
        if host.contains("api.openai.com") { return .officialOpenAI }
        if host.contains("antchat") || host.contains("alipay.com") { return .antchat }
        return .compatible
    }

    /// Map UI size picks onto what each gateway actually accepts.
    /// AntChat/Qwen: prefer native Qwen sizes (up to ~2048). Official OpenAI: only 1024/1536 family.
    static func normalizedSize(_ size: GeneratedImageSize, dialect: ImageAPIDialect) -> String {
        switch dialect {
        case .officialOpenAI:
            switch size {
            case .automatic: return "auto"
            case .square, .qwenSquare: return "1024x1024"
            case .portrait, .qwenPortrait: return "1024x1536"
            case .landscape, .qwenLandscape, .qwenLandscapeHD: return "1536x1024"
            }
        case .antchat, .compatible:
            switch size {
            case .automatic: return GeneratedImageSize.qwenLandscapeHD.rawValue
            default: return size.rawValue
            }
        }
    }

    /// Prefer a sharp Qwen landscape size when the host is AntChat and the user
    /// is still on the soft OpenAI 1536×1024 default.
    static func preferredSize(for configuration: ModelConfiguration) -> GeneratedImageSize {
        let dialect = imageAPIDialect(baseURL: configuration.baseURL)
        guard dialect == .antchat else { return configuration.size }
        switch configuration.size {
        case .landscape, .automatic, .square:
            return .qwenLandscapeHD
        default:
            return configuration.size
        }
    }

    private func endpoint(_ path: String) throws -> URL {
        guard var components = URLComponents(string: configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw MusepaperError.invalidConfiguration("Base URL 无法解析")
        }
        let suffix = path.split(separator: "/").map(String.init)
        let existing = components.path.split(separator: "/").map(String.init)
        components.path = "/" + (existing + suffix).joined(separator: "/")
        guard let url = components.url else { throw MusepaperError.invalidConfiguration("请求地址无法构建") }
        return url
    }

    private func explainFailure(status: Int, message: String) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = (try? endpoint("images/generations").absoluteString) ?? configuration.baseURL
        let missingModel = message.contains("模型不存在")
            || (message.localizedCaseInsensitiveContains("model")
                && (message.localizedCaseInsensitiveContains("not found")
                    || message.localizedCaseInsensitiveContains("does not exist")
                    || message.contains("不存在")))
        let unauthorizedModel = status == 401 || message.contains("未授权") || message.localizedCaseInsensitiveContains("unauthorized")
        if missingModel || unauthorizedModel {
            if Self.looksLikeChatModel(model) {
                return "HTTP \(status)：「\(model)」像对话模型。出图要用文生图名（例如 Qwen-Image-2512-Lightning），不要填 Hy3。"
            }
            return "HTTP \(status)：\(endpoint) 拒绝了「\(model)」。令牌 \(Self.fingerprint(apiKey)) 能通过鉴权，但生图仍说模型不存在——通常是这把令牌没开图像推理（Hy3 对话通了也不算），或和本机不是同一把钥。请在本机设置里看成功时的令牌指纹对照。原文：\(message)"
        }
        return "HTTP \(status)：\(message)（模型 \(model)）"
    }

    static func looksLikeChatModel(_ model: String) -> Bool {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return false }
        if name.contains("image") || name.contains("flux") || name.contains("dall")
            || name.contains("sdxl") || name.contains("diffusion") || name.contains("lightning")
        {
            return false
        }
        let chatMarks = ["hy3", "gpt-4", "gpt-5", "gpt-3", "claude", "qwen-plus", "qwen-max", "qwen-turbo", "deepseek", "glm-4", "kimi", "moonshot", "sonnet", "opus"]
        return chatMarks.contains { name.contains($0) }
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Musepaper/0.1", forHTTPHeaderField: "User-Agent")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            if error.code == .timedOut { throw MusepaperError.networkFailed("请求超时，请检查模型超时设置") }
            throw MusepaperError.networkFailed(error.localizedDescription)
        } catch { throw MusepaperError.networkFailed(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else { throw MusepaperError.invalidResponse("缺少 HTTP 状态") }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403:
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? String(data: data.prefix(600), encoding: .utf8) ?? ""
            if message.contains("模型") || message.localizedCaseInsensitiveContains("model") {
                throw MusepaperError.generationFailed(explainFailure(status: http.statusCode, message: message.isEmpty ? "未授权" : message))
            }
            throw MusepaperError.unauthorized
        case 402: throw MusepaperError.paymentRequired
        case 429: throw MusepaperError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        default:
            let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? String(data: data.prefix(600), encoding: .utf8) ?? "未知错误"
            let billingText = [message, apiError?.error.code ?? "", apiError?.error.type ?? ""].joined(separator: " ").lowercased()
            if billingText.contains("quota") || billingText.contains("billing") || billingText.contains("credit") { throw MusepaperError.paymentRequired }
            throw MusepaperError.generationFailed(explainFailure(status: http.statusCode, message: message))
        }
    }
}

private struct ImageGenerationBody: Encodable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    let quality: String
    let outputFormat: String
    let negativePrompt: String?
    let dialect: OpenAIImageProvider.ImageAPIDialect

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size, quality
        case outputFormat = "output_format"
        case responseFormat = "response_format"
        case negativePrompt = "negative_prompt"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(size, forKey: .size)
        switch dialect {
        case .officialOpenAI:
            try container.encode(n, forKey: .n)
            try container.encode(quality, forKey: .quality)
            try container.encode(outputFormat, forKey: .outputFormat)
        case .antchat:
            // Theta/AntChat: model+prompt+size+response_format+output_format. No `quality`.
            try container.encode("b64_json", forKey: .responseFormat)
            try container.encode(outputFormat, forKey: .outputFormat)
        case .compatible:
            try container.encode(n, forKey: .n)
            try container.encode("b64_json", forKey: .responseFormat)
            try container.encode(outputFormat, forKey: .outputFormat)
        }
        let negative = negativePrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !negative.isEmpty {
            try container.encode(negative, forKey: .negativePrompt)
        }
    }
}

private struct ImageGenerationResponse: Decodable {
    struct Item: Decodable {
        let b64JSON: String?
        let url: String?
        enum CodingKeys: String, CodingKey { case b64JSON = "b64_json"; case url }
    }
    let data: [Item]
}

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String; let type: String?; let code: String? }
    let error: Detail
}
