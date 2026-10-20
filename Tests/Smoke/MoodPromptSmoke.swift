import Foundation

@main
struct MoodPromptSmoke {
    static func main() throws {
        let composer = PromptComposer()
        let core = "温暖的春天的悠闲午后"
        guard composer.needsGroundedScene(core) else {
            fatalError("mood core must need a grounded sighting")
        }
        let dirty = composer.groundIfNeeded(
            "\(core)，电影感，85mm，空气透视，巷口招牌上写着欢迎",
            core: core,
            seed: 1
        )
        guard dirty.hasPrefix(core) else { fatalError("core must lead: \(dirty)") }
        guard composer.hasConcretePlace(dirty) else { fatalError("must land a place: \(dirty)") }
        guard dirty.contains("电影感") || dirty.contains("85mm") else {
            fatalError("mood replace must keep shot language: \(dirty)")
        }
        for banned in ["招牌", "没有文字", "写着", "欢迎", "巷口", "， ，"] {
            guard !dirty.contains(banned) else { fatalError("still contains \(banned): \(dirty)") }
        }
        let negative = composer.negativePrompt(draft: PromptDraft(input: core), channel: nil)
        guard negative.contains("招牌"), negative.contains("中文") || negative.lowercased().contains("chinese") else {
            fatalError("negatives must cover signage/language: \(negative)")
        }
        let imagePrompt = composer.imageModelPrompt(dirty, core: core, seed: 1)
        guard !composer.containsCJK(imagePrompt) else {
            fatalError("mood-only image API prompt must stay English: \(imagePrompt)")
        }
        guard imagePrompt.localizedCaseInsensitiveContains("spring")
            || imagePrompt.localizedCaseInsensitiveContains("afternoon") else {
            fatalError("image API prompt lost the mood: \(imagePrompt)")
        }
        guard !imagePrompt.localizedCaseInsensitiveContains("no text") else {
            fatalError("positive prompt must not say no text: \(imagePrompt)")
        }
        let cases: [(core: String, must: [String])] = [
            (core, ["spring", "afternoon"]),
            ("雨夜的未来上海", ["上海", "shanghai"]),
            ("马尔代夫的果冻海", ["马尔代夫", "maldives"]),
            ("美女", ["美女", "woman", "person", "portrait"]),
            ("孤独宇宙", ["孤独宇宙", "cosmos", "space"]),
            ("安静、空旷、有探索感的宇宙场景", ["宇宙", "cosmos", "space"]),
            ("橘猫", ["橘猫", "cat"]),
            ("一杯咖啡", ["咖啡", "coffee"]),
            ("五爪金龙", ["五爪金龙"])
        ]
        for item in cases {
            let api = composer.imageModelPrompt(item.core, core: item.core, seed: 3)
            guard item.must.contains(where: { api.localizedCaseInsensitiveContains($0) }) else {
                fatalError("lost meaning for \(item.core): \(api)")
            }
            guard !api.localizedCaseInsensitiveContains("no text") else {
                fatalError("positive said no text: \(api)")
            }
            if item.core.contains("宇宙") || item.core.contains("橘猫") || item.core.contains("咖啡") {
                for banned in ["afternoon", "courtyard", "balcony", "blanket"] {
                    guard !api.localizedCaseInsensitiveContains(banned) else {
                        fatalError("\(item.core) got mood leftover \(banned): \(api)")
                    }
                }
                guard !api.localizedCaseInsensitiveContains("landscape photograph") else {
                    fatalError("\(item.core) locked to landscape: \(api)")
                }
            }
            print("IMAGE_CASE \(item.core) => \(api)")
        }
        let cosmosEnhanced = composer.spokenRewrite(
            "A quiet vast cosmos, a thin band of stars.",
            core: "孤独宇宙",
            seed: 4
        )
        var used = Set<String>()
        let cosmosDistinguished = composer.distinguish(
            cosmosEnhanced, used: &used, index: 0, seed: 4, core: "孤独宇宙"
        )
        let cosmosAPI = composer.imageModelPrompt(cosmosDistinguished, core: "孤独宇宙", seed: 4)
        guard cosmosDistinguished.contains("孤独宇宙"), cosmosAPI.contains("孤独宇宙") else {
            fatalError("agent path lost 孤独宇宙: \(cosmosDistinguished) / \(cosmosAPI)")
        }
        for banned in ["afternoon", "courtyard", "balcony", "blanket"] {
            guard !cosmosAPI.localizedCaseInsensitiveContains(banned) else {
                fatalError("agent path pasted mood onto cosmos: \(cosmosAPI)")
            }
        }
        print("AGENT_PATH cosmos => \(cosmosAPI)")

        let shot = composer.sanitizeVisualPrompt("孤独宇宙，低机位，35mm，电影感，没有文字")
        guard shot.contains("低机位"), shot.contains("35mm"), shot.contains("电影感") else {
            fatalError("sanitize dropped shot language: \(shot)")
        }
        guard !shot.contains("没有文字") else { fatalError("sanitize kept no-text: \(shot)") }

        let spoken = composer.spokenRewrite(
            "电影感海边灯塔，低机位，35mm，没有文字",
            core: "海边灯塔",
            seed: 2
        )
        guard spoken.contains("海边灯塔") else { fatalError("spoken lost 海边灯塔: \(spoken)") }
        guard spoken.contains("电影感") || spoken.contains("35mm") || spoken.contains("低机位") else {
            fatalError("spoken dropped shot language: \(spoken)")
        }
        guard !spoken.localizedCaseInsensitiveContains("no text") else {
            fatalError("spoken kept no text: \(spoken)")
        }

        let ocean = composer.imageModelPrompt("a quiet ocean", core: "ocean")
        guard ocean.localizedCaseInsensitiveContains("photorealistic photograph") else {
            fatalError("ocean wrap missing photograph: \(ocean)")
        }
        guard !ocean.localizedCaseInsensitiveContains("landscape photograph") else {
            fatalError("ocean locked to landscape: \(ocean)")
        }

        let batch = composer.uniqueScenePrompts(
            idea: core, channel: nil, emptySpace: .none, seedBase: 11, count: 4
        )
        var personHits = 0
        var emptyHits = 0
        for prompt in batch {
            guard prompt.contains(core) else { fatalError("batch lost core: \(prompt)") }
            if composer.isFigureSubject(prompt) || prompt.contains("光里有一个人") { personHits += 1 }
            if prompt.contains("院子") || prompt.contains("阳台") || prompt.contains("空地方") { emptyHits += 1 }
        }
        guard personHits < 4 else { fatalError("mood batch locked to people: \(batch)") }
        guard emptyHits < 4 else { fatalError("mood batch locked to empty yards: \(batch)") }
        let womanPlan = VariationPlanner().plan(idea: "\(core)，a woman sits", count: 1, seed: 7)[0]
        guard womanPlan.themeKey == "mood" else {
            fatalError("mood+woman flipped to \(womanPlan.themeKey)")
        }
        guard !composer.shouldAdoptTypedIdeaAsSeriesCore(locked: core, idea: "园子里的女人") else {
            fatalError("agent woman must not steal mood core")
        }

        print("MOOD_PROMPT_OK ui=\(dirty)")
        print("IMAGE_MODEL_PROMPT \(imagePrompt)")
        print("SHOT_LANGUAGE \(shot)")
        print("SPOKEN_LIGHTHOUSE \(spoken)")
    }
}
