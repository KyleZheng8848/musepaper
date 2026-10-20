import XCTest
@testable import Musepaper

final class VariationPlannerTests: XCTestCase {
    private let planner = VariationPlanner()
    private let rules = "天气：晴/雨/雾；时段：黎明/黄昏/深夜；视角：广角/低机位/航拍"

    func testMoodIdeaRotatesSightingsInsteadOfPortraitLock() {
        let combos = planner.plan(idea: "温暖的春天的悠闲午后", count: 4, seed: 11)
        XCTAssertEqual(combos.count, 4)
        for combo in combos {
            XCTAssertEqual(combo.themeKey, "mood", combo.visualPhrase)
            XCTAssertFalse(combo.visualPhrase.contains("人物是唯一亮部"), combo.visualPhrase)
            XCTAssertFalse(combo.visualPhrase.contains("全身站姿"), combo.visualPhrase)
            XCTAssertFalse(combo.visualPhrase.contains("航拍"), combo.visualPhrase)
        }
        let sightings = Set(combos.compactMap { $0.value(for: "sighting") })
        XCTAssertGreaterThanOrEqual(sightings.count, 2, "心情句应换看见什么，不能整批同一类：\(sightings)")
        XCTAssertTrue(sightings.isSubset(of: ["空场", "人", "静物", "室内"]), "\(sightings)")
    }

    func testMoodSentenceWithWomanStaysMoodNotPortrait() {
        for idea in ["温暖的午后，a woman sits", "温暖的春天的悠闲午后，园子里的女人"] {
            let combo = planner.plan(idea: idea, count: 1, seed: 7)[0]
            XCTAssertEqual(combo.themeKey, "mood", idea)
            XCTAssertEqual(combo.value(for: "sighting") != nil, true, idea)
        }
        XCTAssertEqual(planner.plan(idea: "美女", count: 1, seed: 7)[0].themeKey, "portrait")
    }

    func testPortraitIdeaDoesNotUseLandscapeAngles() {
        let combos = planner.plan(idea: "美女", count: 4, seed: 21)
        XCTAssertEqual(combos.count, 4)
        for combo in combos {
            XCTAssertEqual(combo.themeKey, "portrait")
            let phrase = combo.visualPhrase
            XCTAssertFalse(phrase.contains("航拍"), phrase)
            XCTAssertFalse(phrase.contains("俯瞰"), phrase)
            XCTAssertFalse(phrase.contains("开阔原野"), phrase)
            XCTAssertFalse(phrase.contains("地平线"), phrase)
            XCTAssertFalse(phrase.contains("峡谷"), phrase)
        }
        let shots = Set(combos.compactMap { $0.value(for: "shot") })
        XCTAssertTrue(shots.contains(where: { ["半身", "近景面部", "全身站姿", "过肩三分"].contains($0) }))
    }

    func testCityBatchCoversMultiplePlacesAndShots() {
        let combos = planner.plan(idea: "城市风景", count: 4, seed: 11)
        XCTAssertEqual(combos.count, 4)
        for i in 0..<4 {
            for j in 0..<i {
                XCTAssertNotEqual(combos[i].visualPhrase, combos[j].visualPhrase)
            }
        }
        let places = Set(combos.compactMap { $0.value(for: "place") })
        let shots = Set(combos.compactMap { $0.value(for: "shot") })
        XCTAssertGreaterThanOrEqual(places.count, 2, "城市风景应走到至少两种地点类：\(places)")
        XCTAssertGreaterThanOrEqual(shots.count, 2, "城市风景应走到至少两种景别：\(shots)")
        XCTAssertFalse(combos.contains { $0.visualPhrase.contains("本次变化") })
        XCTAssertFalse(combos.contains { $0.visualPhrase.contains("候选差异指令") })
    }

    func testCosmosDoesNotUseDomesticForeign() {
        let combos = planner.plan(idea: "宇宙", count: 4, seed: 3)
        for combo in combos {
            XCTAssertFalse(combo.visualPhrase.contains("国内"))
            XCTAssertFalse(combo.visualPhrase.contains("国外"))
            XCTAssertEqual(combo.themeKey, "cosmos")
        }
        XCTAssertGreaterThanOrEqual(Set(combos.compactMap { $0.value(for: "place") }).count, 2)
        XCTAssertGreaterThanOrEqual(Set(combos.compactMap { $0.value(for: "shot") }).count, 2)
    }

    func testNamedPlaceIsNotSwappedAbroad() {
        let combos = planner.plan(idea: "雨后的上海外滩", count: 4, seed: 8)
        for combo in combos {
            if let place = combo.value(for: "place") {
                XCTAssertFalse(place.contains("国外"))
            }
        }
    }

    func testSameSeedKeepsSameVariant() {
        XCTAssertEqual(planner.cue(from: rules, seed: 42), planner.cue(from: rules, seed: 42))
        XCTAssertEqual(
            planner.plan(idea: "城市风景", count: 4, seed: 5).map(\.visualPhrase),
            planner.plan(idea: "城市风景", count: 4, seed: 5).map(\.visualPhrase)
        )
    }

    func testDifferentSeedsChangeExpression() {
        XCTAssertNotEqual(planner.cue(from: rules, seed: 42), planner.cue(from: rules, seed: 43))
    }

    func testCatalogHasAtLeastTwentyFiveAxes() {
        XCTAssertGreaterThanOrEqual(VariationPlanner.catalog.count, 20)
        XCTAssertGreaterThanOrEqual(Set(VariationPlanner.catalog.map(\.name)).count, 20)
    }

    func testExploreDoesNotWriteAxisLabels() {
        let phrases = planner.explore(seed: 7, pick: 8)
        XCTAssertGreaterThanOrEqual(phrases.count, 5)
        let joined = phrases.joined(separator: "，")
        XCTAssertFalse(joined.contains("天气="))
        XCTAssertFalse(joined.contains("本次变化"))
        XCTAssertFalse(joined.contains("："))
    }

    func testBatchDrawsDifferentAxisMixes() {
        let batch = planner.exploreBatch(count: 4, seed: 2026)
        XCTAssertEqual(batch.count, 4)
        let joined = batch.map { $0.joined(separator: "，") }
        XCTAssertEqual(Set(joined).count, 4)
    }

    func testFjordStaysOnTheLandformAndDropsCityCraft() {
        let combos = planner.plan(idea: "超级无敌峡湾地貌", count: 4, seed: 21)
        XCTAssertEqual(combos.count, 4)
        XCTAssertTrue(combos.allSatisfy { $0.themeKey == "nature" })
        for combo in combos {
            let phrase = combo.visualPhrase
            XCTAssertTrue(phrase.contains("同一主体") || phrase.contains("纵深") || phrase.contains("俯瞰") || phrase.contains("近"), phrase)
            XCTAssertFalse(phrase.contains("玻璃幕墙"), phrase)
            XCTAssertFalse(phrase.contains("湿沥青"), phrase)
            XCTAssertFalse(phrase.contains("路灯"), phrase)
            XCTAssertFalse(phrase.contains("水边聚落"), phrase)
            XCTAssertFalse(phrase.contains("孤树"), phrase)
        }
    }

    func testCafeChalkboardUsesInteriorNotGenericFogClimate() {
        let combo = planner.plan(idea: "一个咖啡店门口有一个黑板", count: 1, seed: 3)[0]
        XCTAssertEqual(combo.themeKey, "interior", combo.visualPhrase)
        XCTAssertFalse(combo.visualPhrase.contains("薄雾把后景削成淡色的层"), combo.visualPhrase)
    }

    func testVariationPhrasesAreDimensionsNotProps() {
        let ideas = ["超级无敌峡湾地貌", "马尔代夫的果冻海", "城市风景", "宇宙"]
        let banned = ["孤树", "路灯", "玻璃幕墙", "钟楼", "穹顶", "渔港", "灯塔", "椅子", "书架", "水箱", "天线", "桥墩", "窗格"]
        for idea in ideas {
            for combo in planner.plan(idea: idea, count: 4, seed: 21) {
                for word in banned {
                    XCTAssertFalse(combo.visualPhrase.contains(word), "\(idea) 不应把物件写进变化轴：\(word) / \(combo.visualPhrase)")
                }
            }
        }
    }
}
