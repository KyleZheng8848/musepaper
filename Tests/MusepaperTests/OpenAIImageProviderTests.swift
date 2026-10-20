import Foundation
import XCTest
@testable import Musepaper

final class OpenAIImageProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testGeneratesImageFromBase64Response() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let provider = try OpenAIImageProvider(configuration: ModelConfiguration(), apiKey: "secret", session: mockSession())
        let request = GenerationRequest(id: UUID(), rawInput: "test", resolvedPrompt: "test", negativePrompt: "", display: .preview, createdAt: Date())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let urls = try await provider.generate(request, outputDirectory: directory)
        XCTAssertEqual(try Data(contentsOf: urls[0]), Data("hello".utf8))
    }

    func testOfficialOpenAIOmitsNegativePrompt() async throws {
        MockURLProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            XCTAssertNil(payload?["negative_prompt"])
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let provider = try OpenAIImageProvider(configuration: ModelConfiguration(), apiKey: "secret", session: mockSession())
        XCTAssertFalse(provider.sendsNegativePrompt)
        let request = GenerationRequest(
            id: UUID(), rawInput: "test", resolvedPrompt: "test",
            negativePrompt: "dock, menu bar", display: .preview, createdAt: Date()
        )
        _ = try await provider.generate(request, outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testCompatibleImageBodyOmitsOfficialOpenAIFields() async throws {
        MockURLProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            XCTAssertEqual(payload?["model"] as? String, "Qwen-Image-2512-Lightning")
            XCTAssertEqual(payload?["size"] as? String, "1536x1024")
            XCTAssertEqual(payload?["response_format"] as? String, "b64_json")
            XCTAssertEqual(payload?["output_format"] as? String, "png")
            XCTAssertNil(payload?["quality"])
            XCTAssertNil(payload?["n"])
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        var config = ModelConfiguration()
        config.provider = .compatible
        config.baseURL = "https://antchat.alipay.com/v1"
        config.model = "Qwen-Image-2512-Lightning"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secret", session: mockSession())
        let request = GenerationRequest(
            id: UUID(), rawInput: "test", resolvedPrompt: "test",
            negativePrompt: "", display: .preview, createdAt: Date()
        )
        _ = try await provider.generate(request, outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testChineseCoreIsSentAsEnglishWithoutCJK() async throws {
        var captured: [String: Any] = [:]
        MockURLProtocol.handler = { request in
            captured = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        var config = ModelConfiguration()
        config.provider = .compatible
        config.baseURL = "https://antchat.alipay.com/v1"
        config.model = "Qwen-Image-2512-Lightning"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secret", session: mockSession())
        let request = GenerationRequest(
            id: UUID(),
            rawInput: "温暖的春天的悠闲午后",
            resolvedPrompt: "温暖的春天的悠闲午后，空着的院子，干净木地板上有一片春光",
            negativePrompt: "text, letters, 文字, 招牌",
            display: .preview,
            createdAt: Date(),
            coreKeywords: "温暖的春天的悠闲午后"
        )
        _ = try await provider.generate(request, outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let prompt = captured["prompt"] as? String ?? ""
        XCTAssertFalse(PromptComposer().containsCJK(prompt), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("spring") || prompt.localizedCaseInsensitiveContains("afternoon"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("no text"), prompt)
        XCTAssertEqual(captured["negative_prompt"] as? String, "text, letters, 文字, 招牌")
    }

    func testCompatibleProviderSendsNegativePrompt() async throws {
        MockURLProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            XCTAssertEqual(payload?["negative_prompt"] as? String, "dock, menu bar")
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        var config = ModelConfiguration()
        config.provider = .compatible
        config.baseURL = "http://127.0.0.1:8080/v1"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secret", session: mockSession())
        XCTAssertTrue(provider.sendsNegativePrompt)
        let request = GenerationRequest(
            id: UUID(), rawInput: "test", resolvedPrompt: "test",
            negativePrompt: "dock, menu bar", display: .preview, createdAt: Date()
        )
        _ = try await provider.generate(request, outputDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testCustomBaseURLSendsNegativePrompt() {
        XCTAssertTrue(
            OpenAIImageProvider.shouldSendNegativePrompt(
                provider: .openAI, baseURL: "https://image.example.com/v1"
            )
        )
        XCTAssertFalse(
            OpenAIImageProvider.shouldSendNegativePrompt(
                provider: .openAI, baseURL: "https://api.openai.com/v1"
            )
        )
        XCTAssertTrue(
            OpenAIImageProvider.shouldSendNegativePrompt(
                provider: .compatible, baseURL: "https://api.openai.com/v1"
            )
        )
    }

    func testSanitizeAPIKeyStripsBearerAndNewlines() {
        XCTAssertEqual(OpenAIImageProvider.sanitizeAPIKey("  Bearer abcdefghijklmnop  "), "abcdefghijklmnop")
        XCTAssertEqual(OpenAIImageProvider.fingerprint("abcdefghijklmnop"), "abcd…mnop·16位")
    }

    func testConnectionRejectsWhenModelMissingFromList() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/models") == true {
                let json = #"{"data":[{"id":"Hy3"},{"id":"gpt-4o"}]}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            XCTFail("should not reach generations when model missing from list")
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        var config = ModelConfiguration()
        config.model = "Qwen-Image-2512-Lightning"
        config.baseURL = "https://api.openai.com/v1"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secretkeysecretkey", session: mockSession())
        do {
            try await provider.testConnection()
            XCTFail("missing model in list must fail early")
        } catch let error as MusepaperError {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains(L10n.isChinese ? "没有「Qwen-Image-2512-Lightning」" : "“Qwen-Image-2512-Lightning” is missing"), text)
            XCTAssertTrue(text.contains("Hy3") || text.contains(L10n.isChinese ? "令牌" : "Token"), text)
        }
    }

    func testAntChatSkipsModelsListAndProbesGenerations() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/models") == true {
                XCTFail("antchat must not gate on /models")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            XCTAssertTrue(request.url?.path.hasSuffix("/images/generations") == true, request.url?.path ?? "")
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        var config = ModelConfiguration()
        config.model = "Qwen-Image-2512-Lightning"
        config.baseURL = "https://antchat.alipay.com/v1"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secretkeysecretkey", session: mockSession())
        try await provider.testConnection()
    }

    func testConnectionUsesImageGenerationsNotModelList() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/models") == true {
                let json = #"{"data":[{"id":"gpt-image-2"}]}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            XCTAssertEqual(request.url?.path, "/v1/images/generations")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = "{\"data\":[{\"b64_json\":\"aGVsbG8=\"}]}".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let provider = try OpenAIImageProvider(configuration: ModelConfiguration(), apiKey: "secret", session: mockSession())
        try await provider.testConnection()
    }

    func testMissingModelErrorNamesTheImageModel() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"error":{"message":"[0b249d3517869728426747214eec1e] 模型不存在"}}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, body)
        }
        var config = ModelConfiguration()
        config.model = "Hy3"
        config.baseURL = "https://antchat.alipay.com/v1"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secret", session: mockSession())
        do {
            try await provider.testConnection()
            XCTFail("chat-like image model must fail")
        } catch let error as MusepaperError {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("Hy3"), text)
            XCTAssertTrue(text.contains(L10n.isChinese ? "对话" : "chat model") || text.contains(L10n.isChinese ? "文生图" : "image model") || text.contains(L10n.isChinese ? "图像" : "image access"), text)
        }
    }

    func testMissingImageModelPointsToCopiedKey() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"error":{"message":"[0b249d3517869728426747214eec1e] 模型不存在"}}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, body)
        }
        var config = ModelConfiguration()
        config.model = "Qwen-Image-2512-Lightning"
        config.baseURL = "https://antchat.alipay.com/v1"
        let provider = try OpenAIImageProvider(configuration: config, apiKey: "secret", session: mockSession())
        do {
            try await provider.testConnection()
            XCTFail("missing image entitlement must fail")
        } catch let error as MusepaperError {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("Qwen-Image-2512-Lightning"), text)
            XCTAssertTrue(text.contains("AK") || text.contains(L10n.isChinese ? "令牌" : "Token"), text)
            XCTAssertFalse(text.contains("不要填 Hy3"), text)
        }
    }

    func testLLaDASizeStaysOnOfficial1024Family() {
        XCTAssertEqual(
            OpenAIImageProvider.normalizedSize(.qwenLandscapeHD, dialect: .antchat, model: "LLaDA-Image"),
            "1536x1024"
        )
        XCTAssertEqual(
            OpenAIImageProvider.normalizedSize(.qwenSquare, dialect: .antchat, model: "LLaDA-Image"),
            "1024x1024"
        )
        var llada = ModelConfiguration()
        llada.baseURL = "https://antchat.alipay.com/v1"
        llada.model = "LLaDA-Image"
        llada.size = .qwenLandscapeHD
        XCTAssertEqual(OpenAIImageProvider.preferredSize(for: llada), .landscape)
        var qwen = llada
        qwen.model = "Qwen-Image-2512-Lightning"
        qwen.size = .landscape
        XCTAssertEqual(OpenAIImageProvider.preferredSize(for: qwen), .qwenLandscapeHD)
    }

    func testLooksLikeChatModel() {
        XCTAssertTrue(OpenAIImageProvider.looksLikeChatModel("Hy3"))
        XCTAssertTrue(OpenAIImageProvider.looksLikeChatModel("gpt-4o"))
        XCTAssertFalse(OpenAIImageProvider.looksLikeChatModel("Qwen-Image-2512-Lightning"))
        XCTAssertFalse(OpenAIImageProvider.looksLikeChatModel("gpt-image-2"))
    }

    func testUnauthorizedIsClassified() async throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let provider = try OpenAIImageProvider(configuration: ModelConfiguration(), apiKey: "bad", session: mockSession())
        do { try await provider.testConnection(); XCTFail("Expected unauthorized") }
        catch let error as MusepaperError { XCTAssertEqual(error, .unauthorized) }
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request.capturingBody())
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
