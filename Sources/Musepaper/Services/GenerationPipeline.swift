import Foundation
import OSLog

actor GenerationPipeline {
    private let provider: any ImageProvider
    private let adapter = WallpaperImageAdapter()
    private let logger = Logger(subsystem: "dev.musepaper.app", category: "generation")
    private(set) var activeIDs: Set<UUID> = []

    init(provider: any ImageProvider) { self.provider = provider }

    func run(_ request: GenerationRequest, outputDirectory: URL) async throws -> [URL] {
        activeIDs.insert(request.id)
        defer { activeIDs.remove(request.id) }
        logger.info("Generating request \(request.id.uuidString, privacy: .public) with \(self.provider.name, privacy: .public)")
        guard !Task.isCancelled else { throw CancellationError() }
        do {
            let rawURLs = try await provider.generate(request, outputDirectory: outputDirectory)
            guard !Task.isCancelled else { throw CancellationError() }
            guard !rawURLs.isEmpty, rawURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw MusepaperError.missingImage }
            return try rawURLs.enumerated().map { try adapter.adapt($0.element, to: request.display, index: $0.offset + 1) }
        } catch {
            logger.error("Generation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
