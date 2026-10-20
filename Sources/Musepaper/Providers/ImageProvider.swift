import Foundation

protocol ImageProvider: Sendable {
    var name: String { get }
    func generate(_ request: GenerationRequest, outputDirectory: URL) async throws -> [URL]
    func testConnection() async throws
}

extension ImageProvider {
    func testConnection() async throws { }
}
