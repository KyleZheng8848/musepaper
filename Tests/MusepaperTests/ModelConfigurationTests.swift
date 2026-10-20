import XCTest
@testable import Musepaper

final class ModelConfigurationTests: XCTestCase {
    func testDefaultUsesCurrentImageModel() {
        XCTAssertEqual(ModelConfiguration().model, "gpt-image-2")
    }

    func testImageCountIsClamped() {
        XCTAssertEqual(ModelConfiguration(imageCount: 99).imageCount, 4)
        XCTAssertEqual(ModelConfiguration(imageCount: 0).imageCount, 1)
    }

    func testInvalidBaseURLRejected() {
        var config = ModelConfiguration(); config.baseURL = "not a url"
        XCTAssertThrowsError(try config.validated())
    }

    func testRemoteHTTPRejected() {
        var config = ModelConfiguration(); config.baseURL = "http://example.com/v1"
        XCTAssertThrowsError(try config.validated())
    }

    func testLocalHTTPAccepted() {
        var config = ModelConfiguration(); config.provider = .compatible; config.baseURL = "http://127.0.0.1:8080/v1"
        XCTAssertNoThrow(try config.validated())
    }

    func testAPIKeyIsNotPartOfConfigurationEncoding() throws {
        let text = String(data: try JSONEncoder().encode(ModelConfiguration()), encoding: .utf8)!
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apiKey"))
    }
}
