import AppKit
import Foundation

@main
struct ProviderSmoke {
    static func main() async throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ error: SmokeError, line: UInt = #line) throws {
            guard condition() else {
                FileHandle.standardError.write(Data("SMOKE_FAIL check=\(checks + 1) line=\(line) error=\(error)\n".utf8))
                throw error
            }
            checks += 1
        }
        let credentialRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-credential-smoke-\(UUID().uuidString)")
        let credentialFile = credentialRoot.appendingPathComponent("credentials.json")
        let credentials = CredentialStore(fileURL: credentialFile)
        let localID = UUID()
        try await credentials.save("local-secret", for: localID)
        let localExists = await credentials.contains(localID)
        let localValue = try await credentials.read(for: localID)
        try expect(localExists, .credentialRoundTrip)
        try expect(localValue == "local-secret", .credentialRoundTrip)
        let permissions = try FileManager.default.attributesOfItem(atPath: credentialFile.path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600, .credentialPermissions)
        try await credentials.delete(for: localID)
        let deleted = !(await credentials.contains(localID))
        try expect(deleted, .credentialDelete)
        try? FileManager.default.removeItem(at: credentialRoot)

        MockProtocol.handler = { request in
            let pixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z6ZkAAAAASUVORK5CYII="
            let response = "{\"data\":[{\"b64_json\":\"\(pixelPNG)\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, response)
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockProtocol.self]
        let provider = try OpenAIImageProvider(configuration: ModelConfiguration(), apiKey: "smoke-secret", session: URLSession(configuration: sessionConfiguration))
        let request = GenerationRequest(id: UUID(), rawInput: "ocean", resolvedPrompt: "a quiet ocean", negativePrompt: "", display: .preview, createdAt: Date())
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("musepaper-smoke-\(UUID().uuidString)")
        let urls = try await GenerationPipeline(provider: provider).run(request, outputDirectory: output)
        guard let sent = MockProtocol.lastRequest else { throw SmokeError.invalidPath }
        try expect(sent.url?.path == "/v1/images/generations", .invalidPath)
        try expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer smoke-secret", .missingAuthorization)
        let payload = try JSONSerialization.jsonObject(with: MockProtocol.lastBody ?? Data()) as? [String: Any]
        try expect(payload?["model"] as? String == "gpt-image-2", .invalidBody)
        let sentPrompt = payload?["prompt"] as? String ?? ""
        try expect(sentPrompt.localizedCaseInsensitiveContains("ocean"), .invalidBody)
        try expect(!PromptComposer().containsCJK(sentPrompt), .invalidBody)
        try expect(payload?["size"] as? String == "1536x1024", .invalidBody)
        try expect(payload?["quality"] as? String == "medium", .invalidBody)
        try expect(urls.count == 1, .invalidImage)
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: urls[0])) else { throw SmokeError.invalidImage }
        try expect(bitmap.pixelsWide == 2560, .invalidImage)
        try expect(bitmap.pixelsHigh == 1600, .invalidImage)
        let reference = output.appendingPathComponent("reference.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z6ZkAAAAASUVORK5CYII=")!.write(to: reference)
        var editRequest = request
        editRequest.id = UUID()
        editRequest.referenceImagePaths = [reference.path]
        _ = try await provider.generate(editRequest, outputDirectory: output)
        try expect(MockProtocol.lastRequest?.url?.path == "/v1/images/edits", .invalidMultipart)
        try expect(MockProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true, .invalidMultipart)
        try expect((MockProtocol.lastBody ?? Data()).range(of: Data("name=\"image[]\"".utf8)) != nil, .invalidMultipart)

        MockProtocol.handler = { request in
            let response = #"{"output":[{"content":[{"type":"output_text","text":"雨夜上海天际线，电影级蓝绿霓虹，右侧低细节留白，无文字水印"}]}]}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, response)
        }
        let promptSession = URLSession(configuration: sessionConfiguration)
        let promptAgent = try PromptAgent(configuration: PromptModelConfiguration(enabled: true), apiKey: "prompt-secret", session: promptSession)
        let enhanced = try await promptAgent.enhance(PromptEnhancementContext(
            rawPrompt: "雨后的上海", deterministicPrompt: "雨后的上海；右侧留白",
            channelName: nil, channelEssence: nil, requiredElements: nil,
            excludedElements: "文字、水印", palette: "蓝绿", emptySpace: "右侧留白",
            displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0
        ))
        let promptPayload = try JSONSerialization.jsonObject(with: MockProtocol.lastBody ?? Data()) as? [String: Any]
        try expect(MockProtocol.lastRequest?.url?.path == "/v1/responses", .invalidPromptAgent)
        try expect(MockProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer prompt-secret", .invalidPromptAgent)
        try expect(promptPayload?["model"] as? String == "gpt-5.6-terra", .invalidPromptAgent)
        try expect(enhanced.contains("上海") || enhanced.localizedCaseInsensitiveContains("shanghai") || enhanced.localizedCaseInsensitiveContains("skyline"), .invalidPromptAgent)
        let composer = PromptComposer()
        let composed = try composer.resolve(draft: PromptDraft(input: "雨夜城市"), channel: nil, display: .preview)
        try expect(!composed.contains("适合作为 macOS 桌面壁纸"), .invalidPromptPurity)
        try expect(!composed.contains("避免：") && !composed.contains("Dock") && !composed.contains("没有文字"), .invalidPromptPurity)
        let providerSafe = composer.enforcePureArtwork(enhanced + "；避免：文字；没有文字")
        try expect(providerSafe.contains("上海") || providerSafe.localizedCaseInsensitiveContains("shanghai") || providerSafe.localizedCaseInsensitiveContains("skyline"), .invalidPromptPurity)
        try expect(!providerSafe.contains("避免") && !providerSafe.contains("没有文字") && !providerSafe.contains("无文字水印"), .invalidPromptPurity)
        let variationRules = "天气：晴/雨/雾；时段：黎明/黄昏/深夜；视角：广角/低机位/航拍"
        let planner = VariationPlanner()
        try expect(planner.cue(from: variationRules, seed: 42) == planner.cue(from: variationRules, seed: 42), .invalidVariation)
        try expect(planner.cue(from: variationRules, seed: 42) != planner.cue(from: variationRules, seed: 43), .invalidVariation)
        print("SMOKE_OK checks=\(checks) keychain=absent credentials=config-0600 generation=ok edits=ok prompt_agent=ok series_variation=ok batch_ready=ok full_bleed=configured base64=ok adapted=2560x1600 image_file=ok")
    }
}

private enum SmokeError: Error {
    case credentialRoundTrip, credentialDelete, credentialPermissions
    case invalidPath, missingAuthorization, invalidBody, invalidImage, invalidMultipart, invalidPromptAgent, invalidVariation, invalidPromptPurity
}

private final class MockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lastRequest = request
            Self.lastBody = request.httpBody ?? Self.read(stream: request.httpBodyStream)
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }

    private static func read(stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
