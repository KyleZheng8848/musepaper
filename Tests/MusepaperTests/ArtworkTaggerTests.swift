import XCTest
@testable import Musepaper

final class ArtworkTaggerTests: XCTestCase {
    func testRetagDropsOldMachineTagsAndKeepsUserLike() {
        let merged = ArtworkTagger.mergeRetag(
            generated: ["城市", "夜景", "喜欢", "磁盘恢复"],
            existing: ["旧标签", "喜欢", "雾"],
            isFavorite: false
        )
        XCTAssertEqual(merged.first, "喜欢")
        XCTAssertTrue(merged.contains("城市"))
        XCTAssertTrue(merged.contains("夜景"))
        XCTAssertFalse(merged.contains("旧标签"))
        XCTAssertFalse(merged.contains("雾"))
        XCTAssertFalse(merged.contains("磁盘恢复"))
        XCTAssertEqual(merged.filter { $0 == "喜欢" }.count, 1)
    }

    func testRetagKeepsLikeWhenOnlyFavoriteFlagIsSet() {
        let merged = ArtworkTagger.mergeRetag(
            generated: ["森林", "晨光"],
            existing: ["旧标签"],
            isFavorite: true
        )
        XCTAssertEqual(merged.first, "喜欢")
        XCTAssertEqual(Array(merged.dropFirst()), ["森林", "晨光"])
    }

    func testRetagDoesNotInventLike() {
        let merged = ArtworkTagger.mergeRetag(
            generated: ["喜欢", "城市"],
            existing: ["夜景"],
            isFavorite: false
        )
        XCTAssertEqual(merged, ["城市"])
    }
}
