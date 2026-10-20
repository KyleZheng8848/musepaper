import XCTest
@testable import Musepaper

final class InspirationChannelTests: XCTestCase {
    func testTitleTakesFirstPhraseInsteadOfMidCut() {
        XCTAssertEqual(InspirationChannel.title(from: "孤独宇宙"), "孤独宇宙")
        XCTAssertEqual(
            InspirationChannel.title(from: "超现实风景，大气磅礴的奇幻地貌与巨大尺度"),
            "超现实风景"
        )
        XCTAssertEqual(
            InspirationChannel.title(from: "安静、空旷、有探索感的宇宙场景、星球、绚烂星空"),
            "安静、空旷"
        )
    }

    func testEmptyIdeaGetsPlaceholderTitle() {
        XCTAssertEqual(InspirationChannel.title(from: "   "), "未命名任务")
    }
}
