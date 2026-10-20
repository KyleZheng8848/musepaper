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

        let cafeCore = "一个咖啡店门口有一个黑板"
        let llada = composer.imageModelPrompt(
            "夜雾里一个剪影，黑板上写着qwennewbee欢迎，volumetric fog, cinematic noir",
            core: cafeCore,
            seed: 2,
            model: "LLaDA-Image"
        )
        guard llada.contains("电影感照片") else { fatalError("LLaDA must use a photo sentence: \(llada)") }
        guard llada.contains("咖啡店") || llada.contains("黑板") else { fatalError("LLaDA cafe lost the subject: \(llada)") }
        guard !llada.localizedCaseInsensitiveContains("those characters") else { fatalError("LLaDA kept instruction echo: \(llada)") }
        guard !llada.localizedCaseInsensitiveContains("this frame differs") else { fatalError("LLaDA kept agent scaffold: \(llada)") }
        guard !llada.localizedCaseInsensitiveContains("noir") else { fatalError("LLaDA defaulted to noir: \(llada)") }
        guard !llada.localizedCaseInsensitiveContains("newbee") else { fatalError("LLaDA kept painted brand: \(llada)") }
        guard !llada.localizedCaseInsensitiveContains("qwen") else { fatalError("LLaDA kept painted qwen: \(llada)") }
        guard !llada.contains("，里") && !llada.hasSuffix("里") else { fatalError("LLaDA left strip debris: \(llada)") }
        let cafePlan = composer.framePlan(core: cafeCore, seed: 1, model: "LLaDA-Image")
        let aligned = composer.alignVariationHint("薄雾把后景削成淡色的层，广角强调空间深度", to: cafePlan)
        guard !aligned.contains("薄雾") else { fatalError("daylight plan still asked for 薄雾: \(aligned)") }
        guard !llada.contains("写着") else { fatalError("LLaDA kept 写着: \(llada)") }
        let night = composer.imageModelPrompt(
            "雨夜的未来上海，湿沥青倒映霓虹",
            core: "雨夜的未来上海",
            seed: 3,
            model: "LLaDA-Image"
        )
        guard !night.localizedCaseInsensitiveContains("even daylight") else {
            fatalError("requested night must not be forced to daylight: \(night)")
        }
        guard !night.localizedCaseInsensitiveContains("bright natural daylight") else {
            fatalError("requested night must not be forced to daylight: \(night)")
        }
        guard !night.contains("晴朗日光") && !night.contains("正午强光") else {
            fatalError("requested night must not be forced to daylight: \(night)")
        }
        guard night.contains("雨") || night.contains("上海") else { fatalError("LLaDA night lost the subject: \(night)") }
        guard night.contains("电影感照片") else { fatalError("LLaDA night must be a photo sentence: \(night)") }
        let aerial = composer.imageModelPrompt(
            "从水上飞机高空俯瞰地面，马尔代夫，Those characters are the subject name",
            core: "从水上飞机高空俯瞰地面，马尔代夫",
            seed: 2,
            model: "LLaDA-Image"
        )
        guard aerial.contains("马尔代夫") || aerial.contains("俯瞰") else { fatalError("LLaDA aerial lost meaning: \(aerial)") }
        guard aerial.contains("电影感照片") else { fatalError("LLaDA aerial must be a photo sentence: \(aerial)") }
        guard !aerial.localizedCaseInsensitiveContains("those characters") else { fatalError("LLaDA aerial kept echo: \(aerial)") }
        guard !aerial.localizedCaseInsensitiveContains("higher angle") else {
            fatalError("LLaDA aerial pushed higher haze: \(aerial)")
        }
        print("LLADA_AERIAL \(aerial)")
        print("LLADA_CAFE \(llada)")
        print("LLADA_NIGHT \(night)")
        let crystal = composer.imageModelPrompt("晶石", core: "晶石", seed: 2, model: "LLaDA-Image")
        guard crystal.contains("晶石") else {
            fatalError("LLaDA 晶石 lost the mineral: \(crystal)")
        }
        guard !crystal.localizedCaseInsensitiveContains("given subject") else {
            fatalError("LLaDA 晶石 fell back to given subject: \(crystal)")
        }
        guard !crystal.localizedCaseInsensitiveContains("person") && !crystal.localizedCaseInsensitiveContains("woman") else {
            fatalError("LLaDA 晶石 became a person: \(crystal)")
        }
        print("LLADA_CRYSTAL \(crystal)")
        let lladaBatch = composer.uniqueScenePrompts(
            idea: "从水上飞机高空俯瞰地面，马尔代夫",
            channel: nil,
            emptySpace: .none,
            seedBase: 42,
            count: 4
        ).enumerated().map { index, scene in
            composer.imageModelPrompt(
                scene,
                core: "从水上飞机高空俯瞰地面，马尔代夫",
                seed: 42 + index,
                model: "LLaDA-Image"
            )
        }
        guard Set(lladaBatch).count == 4 else {
            fatalError("LLaDA batch prompts must differ:\n\(lladaBatch.joined(separator: "\n"))")
        }
        print("LLADA_BATCH \(lladaBatch.joined(separator: " | "))")
        for model in ["LLaDA-Image", "Qwen-Image", "gpt-image-2", "flux-schnell"] {
            let batchPrompts = composer.uniqueScenePrompts(
                idea: "从水上飞机高空俯瞰地面，马尔代夫",
                channel: nil,
                emptySpace: .none,
                seedBase: 42,
                count: 4
            ).enumerated().map { index, scene in
                composer.imageModelPrompt(
                    scene,
                    core: "从水上飞机高空俯瞰地面，马尔代夫",
                    seed: 42 + index,
                    model: model
                )
            }
            guard Set(batchPrompts).count == 4 else {
                fatalError("\(model) batch prompts must differ:\n\(batchPrompts.joined(separator: "\n"))")
            }
            print("BATCH_\(model) \(batchPrompts.joined(separator: " | "))")
        }
        guard !PromptAgent.systemPrompt.contains("no text") else {
            fatalError("agent system prompt must not say no text")
        }
        guard !PromptAgent.systemPrompt.contains("没有文字") else {
            fatalError("agent system prompt must not say 没有文字")
        }
        for banned in ["不要整批", "空院子", "阴间", "女人", "黑板", "no text"] {
            guard !PromptAgent.systemPrompt.contains(banned) else {
                fatalError("agent system still steers with \(banned)")
            }
        }
        let lladaSystem = PromptAgent.systemPrompt(for: .llada)
        let qwenSystem = PromptAgent.systemPrompt(for: .qwen)
        guard lladaSystem.contains("一张电影感照片") else {
            fatalError("LLaDA agent must write a photo sentence")
        }
        for text in [lladaSystem, qwenSystem, PromptAgent.visualUserInput(
            PromptEnhancementContext(
                rawPrompt: "晶石", deterministicPrompt: "晶石",
                channelName: nil, channelEssence: nil, requiredElements: nil,
                excludedElements: "文字、水印", palette: nil, emptySpace: "无",
                displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
                coreKeywords: "晶石", imageModel: "LLaDA-Image"
            )
        )] {
            guard !text.contains("Those characters") else { fatalError("agent still sent Those characters") }
            guard !text.localizedCaseInsensitiveContains("this frame differs") else { fatalError("agent still sent This frame differs") }
            guard !text.contains("no text") else { fatalError("agent still sent no text") }
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

        let cafeInput = PromptAgent.visualUserInput(
            PromptEnhancementContext(
                rawPrompt: cafeCore, deterministicPrompt: cafeCore,
                channelName: nil, channelEssence: nil, requiredElements: nil,
                excludedElements: "文字、水印", palette: nil, emptySpace: "无",
                displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
                coreKeywords: cafeCore, imageModel: "LLaDA-Image"
            )
        )
        guard cafeInput.contains("主题：") else { fatalError("LLaDA agent input lost 主题： \(cafeInput)") }
        guard cafeInput.contains("光："), cafeInput.contains("看：") else { fatalError("LLaDA agent input lost 光/看: \(cafeInput)") }
        guard !cafeInput.contains("不要") else { fatalError("LLaDA agent input still said 不要: \(cafeInput)") }
        guard !cafeInput.contains("深色空板"), !cafeInput.contains("板面空白") else {
            fatalError("cafe agent input still steers the board: \(cafeInput)")
        }
        guard !cafeInput.contains("Those characters"), !cafeInput.localizedCaseInsensitiveContains("this frame differs") else {
            fatalError("LLaDA agent input leaked scaffold: \(cafeInput)")
        }
        let dirtyLlada = composer.finishAgentPrompt(
            "咖啡店门口，夜雾里一个剪影，黑板上写着qwennewbee欢迎",
            core: cafeCore,
            seed: 2,
            model: "LLaDA-Image"
        )
        guard dirtyLlada.contains("电影感照片") else { fatalError("dirty LLaDA agent last-mile lost photo sentence: \(dirtyLlada)") }
        guard dirtyLlada.contains("咖啡店") || dirtyLlada.contains("黑板") else { fatalError("dirty LLaDA agent last-mile lost cafe: \(dirtyLlada)") }
        guard !dirtyLlada.contains("写着"), !dirtyLlada.localizedCaseInsensitiveContains("qwennewbee") else {
            fatalError("dirty LLaDA agent last-mile kept painted letters: \(dirtyLlada)")
        }
        let qwenDragon = composer.finishAgentPrompt(
            "五爪金龙盘在岩上，鳞片反光，云海铺到画面四边",
            core: "五爪金龙",
            seed: 3,
            model: "Qwen-Image"
        )
        guard qwenDragon.contains("五爪金龙") else { fatalError("Qwen agent last-mile lost 五爪金龙: \(qwenDragon)") }
        guard qwenDragon.localizedCaseInsensitiveContains("photorealistic") else {
            fatalError("Qwen agent last-mile lost photorealistic wrap: \(qwenDragon)")
        }
        let moodInput = PromptAgent.visualUserInput(
            PromptEnhancementContext(
                rawPrompt: core, deterministicPrompt: core,
                channelName: nil, channelEssence: nil, requiredElements: nil,
                excludedElements: "文字、水印", palette: nil, emptySpace: "无",
                displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
                coreKeywords: core
            )
        )
        guard moodInput.contains("主题：") else { fatalError("mood agent input lost 主题： \(moodInput)") }
        guard !moodInput.contains("不要") else { fatalError("mood agent input still said 不要: \(moodInput)") }
        guard !moodInput.contains("看见：") else { fatalError("mood agent input still injected a sighting example: \(moodInput)") }
        let crystalInput = PromptAgent.visualUserInput(
            PromptEnhancementContext(
                rawPrompt: "晶石", deterministicPrompt: "晶石",
                channelName: nil, channelEssence: nil, requiredElements: nil,
                excludedElements: "文字、水印", palette: nil, emptySpace: "无",
                displayWidth: 2560, displayHeight: 1440, referenceImageCount: 0,
                coreKeywords: "晶石",
                dimensionCombo: "黄昏把海面烧成一条金色道路，超广角让近处浪很大",
                imageModel: "LLaDA-Image"
            )
        )
        guard crystalInput.contains("主题：晶石") else { fatalError("晶石 agent lost the mineral: \(crystalInput)") }
        guard !crystalInput.contains("不要") else { fatalError("LLaDA 晶石 input still instructed with 不要: \(crystalInput)") }
        guard !crystalInput.contains("This frame differs") else { fatalError("晶石 input leaked scaffold") }
        guard crystalInput.contains("这一张多看见：黄昏把海面烧成一条金色道路") || crystalInput.contains("黄昏") else {
            fatalError("LLaDA combo must stay a short Chinese clause: \(crystalInput)")
        }
        print("AGENT_LLADA_CRYSTAL_INPUT\n\(crystalInput)")
        print("AGENT_LLADA_DIRTY \(dirtyLlada)")
        print("AGENT_QWEN_DRAGON \(qwenDragon)")

        print("MOOD_PROMPT_OK ui=\(dirty)")
        print("IMAGE_MODEL_PROMPT \(imagePrompt)")
        print("SHOT_LANGUAGE \(shot)")
        print("SPOKEN_LIGHTHOUSE \(spoken)")
    }
}
