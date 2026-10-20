import XCTest
@testable import Musepaper

final class ArtworkPromptSidecarTests: XCTestCase {
    func testWriteAndReadBesideWallpaperFilename() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-prompt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let image = dir.appendingPathComponent("\(UUID().uuidString)-1.wallpaper-1.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let written = ArtworkPromptSidecar.write(
            finalPrompt: "雨夜长街，青蓝霓虹倒影",
            rawInput: "雨夜城市",
            negativePrompt: "文字,水印",
            nextTo: image
        )
        XCTAssertNotNil(written)
        XCTAssertTrue(written!.lastPathComponent.hasSuffix(".prompt.json"))

        let payload = ArtworkPromptSidecar.read(nextTo: image)
        XCTAssertEqual(payload?.finalPrompt, "雨夜长街，青蓝霓虹倒影")
        XCTAssertEqual(payload?.rawInput, "雨夜城市")
    }

    func testFinalPromptTextPrefersResolved() {
        let request = GenerationRequest(
            id: UUID(),
            rawInput: "短想法",
            resolvedPrompt: "完整最终 Prompt",
            negativePrompt: "",
            display: .preview,
            createdAt: Date()
        )
        let record = GenerationRecord(
            id: request.id,
            request: request,
            state: .ready,
            imagePath: nil,
            isFavorite: false,
            updatedAt: Date()
        )
        XCTAssertEqual(record.finalPromptText, "完整最终 Prompt")
        XCTAssertEqual(record.ideaText, "短想法")
    }
}
