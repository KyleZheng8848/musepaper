import Foundation

@main
enum PortraitPromptSmoke {
    static func main() throws {
        let composer = PromptComposer()
        let planner = VariationPlanner()

        guard composer.isFigureSubject("美女") else { throw Fail("detect-beauty") }
        guard !composer.isFigureSubject("城市风景") else { throw Fail("not-city") }

        let combos = planner.plan(idea: "美女", count: 4, seed: 21)
        for combo in combos {
            guard combo.themeKey == "portrait" else { throw Fail("theme-\(combo.themeKey)") }
            let phrase = combo.visualPhrase
            for bad in ["航拍", "俯瞰", "开阔原野", "地平线", "峡谷"] where phrase.contains(bad) {
                throw Fail("landscape-angle-\(bad): \(phrase)")
            }
        }

        for prompt in composer.uniqueScenePrompts(idea: "美女", channel: nil, emptySpace: .none, seedBase: 17, count: 4) {
            guard prompt.contains("美女") else { throw Fail("missing-core: \(prompt)") }
            for bad in ["航拍", "开阔原野", "俯瞰全貌"] where prompt.contains(bad) {
                throw Fail("scene-\(bad): \(prompt)")
            }
        }

        var draft = PromptDraft(input: "美女")
        draft.mode = .inspiration
        let channel = InspirationChannel(
            name: "旧默认",
            essence: "人像",
            exclude: "人物、文字、水印"
        )
        let negative = composer.negativePrompt(draft: draft, channel: channel)
        guard !negative.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("人物") else {
            throw Fail("negative-still-bans-person: \(negative)")
        }

        print("portrait-prompt-smoke OK")
    }
}

private struct Fail: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
