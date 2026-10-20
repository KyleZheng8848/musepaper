import Foundation
import XCTest
@testable import Musepaper

final class PromptAgentTests: XCTestCase {
    func testResponsesAPIRequestAndParsing() async throws {
        let result = try await run(
            format: .responses,
            response: #"{"output":[{"content":[{"type":"output_text","text":"电影感海边灯塔，右侧留白，无文字水印"}]}]}"#
        )
        XCTAssertTrue(
            result.text.contains("灯塔")
                || result.text.localizedCaseInsensitiveContains("lighthouse")
                || result.text.localizedCaseInsensitiveContains("seaside"),
            result.text
        )
        XCTAssertTrue(result.text.contains("电影感") || result.text.localizedCaseInsensitiveContains("cinematic"), result.text)
        XCTAssertFalse(result.text.contains("无文字"))
        XCTAssertFalse(result.text.contains("没有文字"))
        XCTAssertEqual(result.request.url?.path, "/v1/responses")
        XCTAssertEqual(result.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testChatCompletionsRequestAndParsing() async throws {
        let result = try await run(
            format: .chatCompletions,
            response: #"{"choices":[{"message":{"content":"夜雨上海天际线，超宽构图，无边框"}}]}"#
        )
        XCTAssertTrue(
            result.text.contains("上海")
                || result.text.localizedCaseInsensitiveContains("shanghai")
                || result.text.localizedCaseInsensitiveContains("skyline"),
            result.text
        )
        XCTAssertFalse(result.text.contains("超宽"))
        XCTAssertTrue(result.text.localizedCaseInsensitiveContains("wide") || result.text.localizedCaseInsensitiveContains("shanghai"), result.text)
        XCTAssertEqual(result.request.url?.path, "/v1/chat/completions")
    }

    func testAnthropicMessagesRequestAndParsing() async throws {
        let result = try await run(
            format: .anthropicMessages,
            response: #"{"content":[{"type":"text","text":"静谧森林晨雾，近处枝叶低细节"}]}"#
        )
        XCTAssertTrue(
            result.text.contains("森林")
                || result.text.localizedCaseInsensitiveContains("forest")
                || result.text.localizedCaseInsensitiveContains("mist"),
            result.text
        )
        XCTAssertEqual(result.request.url?.path, "/v1/messages")
        XCTAssertEqual(result.request.value(forHTTPHeaderField: "x-api-key"), "test-key")
    }

    func testConfigurationRejectsRemoteHTTP() {
        var configuration = PromptModelConfiguration()
        configuration.baseURL = "http://example.com/v1"
        XCTAssertThrowsError(try configuration.validated())
    }

    func testBlueprintExpansionParsesStructuredDesign() async throws {
        let json = #"{"name":"雨夜城","essence":"安静电影感","core_keywords":"未来上海,蓝绿霓虹","variation_axes":"天气：雨/雾/雪；视角：广角/航拍/低机位","palette":"深蓝,青绿","exclusions":"文字,水印"}"#
        let envelope = try JSONSerialization.data(withJSONObject: ["output_text": json])
        PromptAgentProtocol.responseData = envelope
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        let agent = try PromptAgent(configuration: PromptModelConfiguration(enabled: true), apiKey: "test-key", session: URLSession(configuration: sessionConfiguration))

        let result = try await agent.expandBlueprint(idea: "雨夜未来上海")

        XCTAssertEqual(result.name, "雨夜城")
        XCTAssertTrue(result.coreKeywords.contains("未来上海"))
        XCTAssertTrue(result.variationAxes.contains("天气："))
    }

    func testArtworkTaggingParsesMultipleTags() async throws {
        PromptAgentProtocol.responseData = Data(#"{"output_text":"{\"tags\":[\"城市\",\"雨夜\",\"冷色\",\"电影感\",\"极简\",\"横向构图\"]}"}"#.utf8)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        let agent = try PromptAgent(
            configuration: PromptModelConfiguration(enabled: true), apiKey: "test-key",
            session: URLSession(configuration: sessionConfiguration)
        )

        let tags = try await agent.suggestTags(prompt: "雨夜城市，青蓝色电影光线", taskName: "未来城市")

        XCTAssertEqual(tags.count, 6)
        XCTAssertTrue(tags.contains("雨夜"))
        XCTAssertTrue(tags.contains("电影感"))
    }

    private func run(format: PromptAPIFormat, response: String) async throws -> (text: String, request: URLRequest) {
        PromptAgentProtocol.responseData = Data(response.utf8)
        PromptAgentProtocol.lastRequest = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        var configuration = PromptModelConfiguration(enabled: true, apiFormat: format)
        configuration.baseURL = "https://example.test/v1"
        let agent = try PromptAgent(configuration: configuration, apiKey: "test-key", session: URLSession(configuration: sessionConfiguration))
        let text = try await agent.enhance(context)
        return (text, try XCTUnwrap(PromptAgentProtocol.lastRequest))
    }

    func testEnhanceInputCarriesDimensionComboAndOmitsLegacyLabels() async throws {
        let result = try await run(
            format: .responses,
            response: #"{"output_text":"雨后滨江街巷，湿石板倒映橱窗暖光"}"#
        )
        let body = try JSONSerialization.jsonObject(with: result.request.httpBody ?? Data()) as? [String: Any]
        let input = body?["input"] as? String ?? ""
        let instructions = body?["instructions"] as? String ?? ""
        XCTAssertTrue(input.contains("Core subject") || input.contains("Core meaning") || input.contains("城市风景"))
        XCTAssertFalse(input.contains("只描写景物本身"))
        XCTAssertFalse(input.contains("用户原始想法："))
        XCTAssertFalse(input.contains("本地约束草稿："))
        XCTAssertFalse(input.contains("2560"))
        XCTAssertFalse(input.contains("1440"))
        XCTAssertFalse(input.contains("没有文字"))
        XCTAssertTrue(input.localizedCaseInsensitiveContains("cinematic") || instructions.localizedCaseInsensitiveContains("cinematic"))
        XCTAssertFalse(instructions.localizedCaseInsensitiveContains("English only"))
        XCTAssertTrue(instructions.contains("photograph") || input.contains("photograph"))
        XCTAssertTrue(instructions.contains("no text"))
        XCTAssertTrue(instructions.contains("person") || input.contains("person"))
        XCTAssertTrue(instructions.localizedCaseInsensitiveContains("Chinese") || input.localizedCaseInsensitiveContains("Keep the subject's name"))
    }

    func testEnhanceInputKeepsFigureSubjectInsteadOfLandscape() async throws {
        PromptAgentProtocol.responseData = Data(#"{"output_text":"美女，窗边柔光半身，伦勃朗侧光，背景虚化"}"#.utf8)
        PromptAgentProtocol.lastRequest = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        let agent = try PromptAgent(
            configuration: PromptModelConfiguration(enabled: true),
            apiKey: "test-key",
            session: URLSession(configuration: sessionConfiguration)
        )
        let figureContext = PromptEnhancementContext(
            rawPrompt: "美女",
            deterministicPrompt: "美女，半身，柔光",
            channelName: nil, channelEssence: nil, requiredElements: nil,
            excludedElements: "文字、水印", palette: nil, emptySpace: "无",
            displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
            coreKeywords: "美女",
            dimensionCombo: "窗边柔光，半身构图，伦勃朗侧光，85mm浅景深"
        )
        let text = try await agent.enhance(figureContext)
        XCTAssertTrue(
            text.contains("美女")
                || text.localizedCaseInsensitiveContains("woman")
                || text.localizedCaseInsensitiveContains("person"),
            text
        )
        let body = try JSONSerialization.jsonObject(with: PromptAgentProtocol.lastRequest?.httpBody ?? Data()) as? [String: Any]
        let input = body?["input"] as? String ?? ""
        XCTAssertTrue(input.contains("美女"))
        XCTAssertTrue(input.contains("person"))
        XCTAssertFalse(input.contains("只描写景物本身"))
        XCTAssertFalse(input.contains("开阔的风景"))
        XCTAssertTrue(input.contains("Keep the person") || input.contains("person"))
    }

    func testAlipayHostUsesChatCompletions() {
        var configuration = PromptModelConfiguration(enabled: true, apiFormat: .responses)
        configuration.baseURL = "https://antchat.alipay.com/v1"
        XCTAssertEqual(try configuration.validated().apiFormat, .chatCompletions)
        XCTAssertTrue(try configuration.validated().endpointPath.contains("chat"))
    }

    func testConnectionAcceptsEchoedGuardrails() async throws {
        PromptAgentProtocol.responseData = Data(#"{"choices":[{"message":{"content":"暮色海边灯塔。不要写没有文字 Dock 菜单栏"}}]}"#.utf8)
        PromptAgentProtocol.lastRequest = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        var configuration = PromptModelConfiguration(enabled: true, apiFormat: .responses)
        configuration.baseURL = "https://antchat.alipay.com/v1"
        let agent = try PromptAgent(configuration: configuration, apiKey: "test-key", session: URLSession(configuration: sessionConfiguration))
        try await agent.testConnection()
        XCTAssertTrue(PromptAgentProtocol.lastRequest?.url?.path.contains("chat/completions") == true)
    }

    func testEnhanceStripsEchoedGuardrailsInsteadOfFailing() async throws {
        let result = try await run(
            format: .chatCompletions,
            response: #"{"choices":[{"message":{"content":"暮色海边灯塔，礁石被浪打湿。不要写没有文字 Dock 菜单栏"}}]}"#
        )
        XCTAssertTrue(
            result.text.contains("灯塔")
                || result.text.localizedCaseInsensitiveContains("lighthouse")
                || result.text.localizedCaseInsensitiveContains("seaside")
                || result.text.localizedCaseInsensitiveContains("reef"),
            result.text
        )
        XCTAssertFalse(result.text.contains("Dock"))
        XCTAssertFalse(result.text.contains("菜单栏"))
        XCTAssertFalse(result.text.contains("没有文字"))
    }

    func testEnhanceRejectsInstructionEssay() async {
        do {
            _ = try await run(
                format: .responses,
                response: #"{"output_text":"一句审美定义，逗号分隔的不可变核心词，分辨率 3600x2338"}"#
            )
            XCTFail("说明书回传必须被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("说明书") || error.localizedDescription.contains("纯画面"))
        }
    }

    func testBlueprintRejectsSchemaTemplate() async {
        let json = #"{"name":"简短系列名","essence":"一句审美定义","core_keywords":"逗号分隔的不可变核心词","variation_axes":"维度与选项","palette":"主色与点缀色","exclusions":"禁止元素"}"#
        PromptAgentProtocol.responseData = try! JSONSerialization.data(withJSONObject: ["output_text": json])
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        let agent = try! PromptAgent(
            configuration: PromptModelConfiguration(enabled: true), apiKey: "test-key",
            session: URLSession(configuration: sessionConfiguration)
        )
        do {
            _ = try await agent.expandBlueprint(idea: "千岛之国")
            XCTFail("模板蓝图必须被拒绝")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("说明书") || error.localizedDescription.contains("模板"))
        }
    }

    func testEnhanceInputDropsPlaceholderSeriesFields() async throws {
        PromptAgentProtocol.responseData = Data(#"{"output_text":"热带群岛，浅礁湖，远处绿色小岛"}"#.utf8)
        PromptAgentProtocol.lastRequest = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        var configuration = PromptModelConfiguration(enabled: true, apiFormat: .responses)
        configuration.baseURL = "https://example.test/v1"
        let agent = try PromptAgent(configuration: configuration, apiKey: "test-key", session: URLSession(configuration: sessionConfiguration))
        let dirty = PromptEnhancementContext(
            rawPrompt: "超清晰，4k，千岛之国",
            deterministicPrompt: "一句审美定义，3600x2338",
            channelName: "简短系列名",
            channelEssence: "一句审美定义",
            requiredElements: nil,
            excludedElements: "文字、水印",
            palette: nil,
            emptySpace: "右侧留白",
            displayWidth: 3600,
            displayHeight: 2338,
            referenceImageCount: 0,
            coreKeywords: "逗号分隔的不可变核心词"
        )
        _ = try await agent.enhance(dirty)
        let body = try JSONSerialization.jsonObject(with: PromptAgentProtocol.lastRequest?.httpBody ?? Data()) as? [String: Any]
        let input = body?["input"] as? String ?? ""
        XCTAssertTrue(input.contains("千岛之国"))
        XCTAssertFalse(input.contains("简短系列名"))
        XCTAssertFalse(input.contains("一句审美定义"))
        XCTAssertFalse(input.contains("3600"))
        XCTAssertFalse(input.contains("2338"))
        XCTAssertFalse(input.contains("4k"))
        XCTAssertFalse(input.contains("超清晰"))
    }

    func testEnhanceMoodPromptStaysSpokenAndGrounded() async throws {
        PromptAgentProtocol.responseData = Data(#"{"output_text":"温暖的春天的悠闲午后，超广角机位，空气透视，巷口招牌上写着欢迎"}"#.utf8)
        PromptAgentProtocol.lastRequest = nil
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [PromptAgentProtocol.self]
        let agent = try PromptAgent(
            configuration: PromptModelConfiguration(enabled: true),
            apiKey: "test-key",
            session: URLSession(configuration: sessionConfiguration)
        )
        let mood = PromptEnhancementContext(
            rawPrompt: "温暖的春天的悠闲午后",
            deterministicPrompt: "温暖的春天的悠闲午后",
            channelName: nil, channelEssence: nil, requiredElements: nil,
            excludedElements: "文字、水印", palette: nil, emptySpace: "无",
            displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
            coreKeywords: "温暖的春天的悠闲午后"
        )
        let text = try await agent.enhance(mood)
        XCTAssertFalse(PromptComposer().containsCJK(text), text)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("spring") || text.localizedCaseInsensitiveContains("afternoon"), text)
        XCTAssertTrue(PromptComposer().hasConcreteSubject(text), text)
        XCTAssertFalse(text.contains("超广角"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("welcome"), text)
        let body = try JSONSerialization.jsonObject(with: PromptAgentProtocol.lastRequest?.httpBody ?? Data()) as? [String: Any]
        let input = body?["input"] as? String ?? ""
        XCTAssertTrue(input.contains("温暖的春天的悠闲午后"))
        XCTAssertTrue(
            input.contains("visible thing")
                || input.contains("still life")
                || input.contains("interior")
                || input.contains("empty place")
                || input.contains("person in the light"),
            input
        )
        XCTAssertTrue(input.contains("Do not default to a woman") || input.contains("Do not lock"), input)
        XCTAssertTrue(input.localizedCaseInsensitiveContains("cinematic") || input.localizedCaseInsensitiveContains("camera"))
    }

    private var context: PromptEnhancementContext {
        PromptEnhancementContext(
            rawPrompt: "城市风景", deterministicPrompt: "中国南方滨江都会的雨后街巷",
            channelName: nil, channelEssence: nil, requiredElements: nil,
            excludedElements: "文字、水印", palette: nil, emptySpace: "右侧留白",
            displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
            dimensionCombo: "中国南方滨江都会，行人尺度的街景，雨刚停，超广角让地面很近"
        )
    }
}

private final class PromptAgentProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
