import XCTest
@testable import Musepaper

final class PromptComposerTests: XCTestCase {
    let composer = PromptComposer()

    func testFigureSubjectDetection() {
        XCTAssertTrue(composer.isFigureSubject("美女"))
        XCTAssertTrue(composer.isFigureSubject("人像写真"))
        XCTAssertFalse(composer.isFigureSubject("城市风景"))
        XCTAssertFalse(composer.isFigureSubject("峡湾"))
    }

    func testPortraitScenesKeepFigureCoreAndAvoidLandscapeAngles() {
        let prompts = composer.uniqueScenePrompts(
            idea: "美女", channel: nil, emptySpace: .none, seedBase: 17, count: 4
        )
        for prompt in prompts {
            XCTAssertTrue(prompt.contains("美女"), prompt)
            XCTAssertFalse(prompt.contains("航拍"), prompt)
            XCTAssertFalse(prompt.contains("开阔原野"), prompt)
            XCTAssertFalse(prompt.contains("俯瞰全貌"), prompt)
        }
    }

    func testEmptyDirectPromptRejected() {
        XCTAssertThrowsError(try composer.resolve(draft: PromptDraft(), channel: nil, display: .preview))
    }

    func testOriginalTreatmentPreservesInput() throws {
        var draft = PromptDraft(input: "雾中松林")
        draft.treatment = .original
        XCTAssertEqual(try composer.resolve(draft: draft, channel: nil, display: .preview), "雾中松林")
    }

    func testEnhancedDescribesTheSceneNotTheSpec() throws {
        let result = try composer.resolve(draft: PromptDraft(input: "海边"), channel: nil, display: .preview)
        XCTAssertTrue(result.contains("海边"))
        XCTAssertFalse(result.contains("电影感光影"))
        XCTAssertFalse(result.contains("景物铺到四边"))
        XCTAssertFalse(result.contains("2560:1600"))
        XCTAssertFalse(result.contains("避免："))
        XCTAssertFalse(result.contains("Dock"))
        XCTAssertFalse(result.contains("菜单栏"))
        XCTAssertFalse(result.contains("适合作为 macOS 桌面壁纸"))
    }

    func testMockupTriggerWordsAreStrippedFromPositivePrompt() throws {
        let draft = PromptDraft(input: "超清晰，4k，壁纸，桌面，千岛之国，悠闲，热带风景")
        let result = try composer.resolve(draft: draft, channel: nil, display: .preview)
        XCTAssertTrue(result.contains("千岛之国"))
        XCTAssertTrue(result.contains("热带风景"))
        XCTAssertFalse(result.contains("电影感光影"))
        XCTAssertFalse(result.contains("景物铺到四边"))
        XCTAssertFalse(result.localizedCaseInsensitiveContains("4k"))
        XCTAssertFalse(result.contains("超清晰"))
        XCTAssertFalse(result.contains("壁纸"))
        XCTAssertFalse(result.contains("桌面"))
        XCTAssertFalse(result.contains("Dock"))
        XCTAssertFalse(result.contains("菜单栏"))
        XCTAssertFalse(result.contains("避免："))
        let negative = composer.negativePrompt(draft: draft, channel: nil)
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("desktop screenshot"))
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("dock"))
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("menu bar"))
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("infographic") || negative.contains("说明书"))
        XCTAssertTrue(negative.contains("文字") || negative.localizedCaseInsensitiveContains("text"))
    }

    func testSanitizeStripsWallpaperDesktopAndMockupWords() {
        let cleaned = composer.sanitizeVisualPrompt("8k wallpaper，macos desktop mockup，样机，千岛之国")
        XCTAssertTrue(cleaned.contains("千岛之国"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("8k"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("wallpaper"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("desktop"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("mockup"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("macos"))
        XCTAssertFalse(cleaned.contains("样机"))
    }

    func testNegativesStayOutOfTheImagePrompt() throws {
        let draft = PromptDraft(input: "海边", negative: "人物")
        let result = try composer.resolve(draft: draft, channel: nil, display: .preview)
        XCTAssertFalse(result.contains("避免："))
        XCTAssertFalse(result.contains("人物"))
        let negative = composer.negativePrompt(draft: draft, channel: nil)
        XCTAssertTrue(negative.contains("人物"))
        XCTAssertTrue(negative.contains("文字") || negative.contains("text"))
    }

    func testUserNoTextPhraseIsStrippedFromImagePrompt() throws {
        var draft = PromptDraft(input: "宇宙的起源，超新星爆发，没有文字")
        draft.treatment = .original
        let result = try composer.resolve(draft: draft, channel: nil, display: .preview)
        XCTAssertTrue(result.contains("超新星爆发"))
        XCTAssertFalse(result.contains("没有文字"))
        XCTAssertFalse(result.contains("文字"))
    }

    func testInstructionEssayIsStripped() {
        let first = composer.enforcePureArtwork("电影感海边灯塔；避免：文字、水印；纯画面硬性要求：不要画 Dock")
        let second = composer.enforcePureArtwork(first)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.contains("海边灯塔"))
        XCTAssertTrue(first.contains("电影感"))
        XCTAssertFalse(first.contains("避免"))
        XCTAssertFalse(first.contains("纯画面硬性要求"))
        XCTAssertFalse(first.contains("Dock"))
        XCTAssertFalse(first.contains("no dock"))
    }

    func testEmptySpaceIsIgnored() throws {
        var draft = PromptDraft(input: "海边")
        draft.emptySpace = .left
        let resolved = try composer.resolve(draft: draft, channel: nil, display: .preview)
        XCTAssertEqual(resolved, "海边")
        XCTAssertFalse(resolved.contains("开阔疏朗"))
        XCTAssertFalse(resolved.contains("留白"))
    }

    func testInspirationUsesChannelWithoutInput() throws {
        var draft = PromptDraft()
        draft.mode = .inspiration
        let result = try composer.resolve(draft: draft, channel: .sample, display: .preview, seed: 0)
        XCTAssertTrue(result.contains("孤独") || result.contains("安静"))
    }

    func testInspirationSeedIsDeterministic() throws {
        var draft = PromptDraft(); draft.mode = .inspiration
        let a = try composer.resolve(draft: draft, channel: .sample, display: .preview, seed: 3)
        let b = try composer.resolve(draft: draft, channel: .sample, display: .preview, seed: 3)
        XCTAssertEqual(a, b)
    }

    func testHighVariationInstruction() throws {
        var draft = PromptDraft(); draft.mode = .inspiration
        var channel = InspirationChannel.sample; channel.variation = 0.9
        XCTAssertTrue(try composer.resolve(draft: draft, channel: channel, display: .preview, seed: 1).contains("更大的空间尺度"))
    }

    func testChannelExclusionsGoToNegativePrompt() throws {
        var draft = PromptDraft(); draft.mode = .inspiration
        var channel = InspirationChannel.sample; channel.exclude = "人物、文字"
        let result = try composer.resolve(draft: draft, channel: channel, display: .preview, seed: 1)
        XCTAssertFalse(result.contains("避免："))
        let negative = composer.negativePrompt(draft: draft, channel: channel)
        XCTAssertTrue(negative.contains("人物"))
        XCTAssertTrue(negative.contains("文字"))
    }

    func testBatchPromptsExploreDifferentDimensions() {
        let prompts = composer.uniqueScenePrompts(
            idea: "城市风景", channel: nil, emptySpace: .right, seedBase: 88, count: 4
        )
        XCTAssertEqual(prompts.count, 4)
        XCTAssertEqual(Set(prompts).count, 4, "一批 4 张的画面描述必须两两不同：\(prompts)")
        for prompt in prompts {
            XCTAssertFalse(prompt.isEmpty, prompt)
            XCTAssertFalse(composer.containsInstructionLeak(prompt), prompt)
            XCTAssertFalse(prompt.contains("避免"))
            XCTAssertFalse(prompt.contains("用户原始想法"))
            XCTAssertFalse(prompt.contains("本地约束草稿"))
            XCTAssertFalse(prompt.contains("没有文字"))
        }
        XCTAssertGreaterThanOrEqual(VariationPlanner.catalogSize, 25)
    }

    func testAgentBriefingLeakIsStrippedFromImagePrompt() {
        let leaked = """
        原初想法“魔幻世界风景” 本地约束草稿：孤独宇宙，深蓝配色
        禁止出现：文字、水印
        避免：Dock、菜单栏
        纯画面硬性要求：没有文字 no text
        """
        let cleaned = composer.enforcePureArtwork(leaked)
        XCTAssertFalse(composer.containsInstructionLeak(cleaned))
        XCTAssertFalse(cleaned.contains("原初想法"))
        XCTAssertFalse(cleaned.contains("本地约束草稿"))
        XCTAssertFalse(cleaned.contains("禁止出现"))
        XCTAssertFalse(cleaned.contains("避免"))
        XCTAssertFalse(cleaned.contains("没有文字"))
        XCTAssertFalse(cleaned.contains("no text"))
        XCTAssertFalse(cleaned.contains("Dock"))
    }

    func testBlueprintTemplateAndResolutionAreStripped() {
        let leaked = """
        简短系列名，一句审美定义，逗号分隔的不可变核心词
        一个分辨率为 3600x2338 的热带岛屿
        保留主题与审美，不要写留白绘图标
        """
        let cleaned = composer.enforcePureArtwork(leaked)
        XCTAssertFalse(composer.containsInstructionLeak(cleaned), cleaned)
        XCTAssertFalse(cleaned.contains("简短系列名"))
        XCTAssertFalse(cleaned.contains("一句审美定义"))
        XCTAssertFalse(cleaned.contains("不可变核心"))
        XCTAssertFalse(cleaned.contains("3600"))
        XCTAssertFalse(cleaned.contains("2338"))
        XCTAssertFalse(cleaned.contains("不要写"))
        XCTAssertTrue(cleaned.contains("热带岛屿"))
    }

    func testPlaceholderSeriesDoesNotEnterImagePrompt() throws {
        var draft = PromptDraft(input: "超清晰，4k，千岛之国")
        draft.mode = .inspiration
        let channel = InspirationChannel(
            name: "简短系列名",
            essence: "一句审美定义",
            coreKeywords: "逗号分隔的不可变核心词"
        )
        let result = try composer.resolve(draft: draft, channel: channel, display: .preview, seed: 1)
        XCTAssertTrue(result.contains("千岛之国"))
        XCTAssertFalse(result.contains("简短系列名"))
        XCTAssertFalse(result.contains("一句审美定义"))
        XCTAssertFalse(result.contains("不可变核心"))
        XCTAssertFalse(result.contains("4k"))
        XCTAssertFalse(result.contains("超清晰"))
        XCTAssertFalse(composer.containsInstructionLeak(result), result)
    }

    func testPinCoreKeepsChineseCoreOnEnglishScene() {
        let pinned = composer.pinCore("孤独宇宙", onto: "sparse stars over a curved planet, deep black")
        XCTAssertTrue(pinned.contains("孤独宇宙"), pinned)
        XCTAssertTrue(pinned.localizedCaseInsensitiveContains("planet") || pinned.localizedCaseInsensitiveContains("stars"), pinned)
        XCTAssertFalse(pinned.localizedCaseInsensitiveContains("afternoon"), pinned)
        XCTAssertFalse(pinned.localizedCaseInsensitiveContains("courtyard"), pinned)
    }

    func testAgentThenDistinguishKeepsSubjectAndStaysEnglish() {
        let enhanced = composer.spokenRewrite(
            "A quiet vast cosmos, a thin band of stars, no ground.",
            core: "孤独宇宙",
            seed: 4
        )
        var used = Set<String>()
        let distinguished = composer.distinguish(enhanced, used: &used, index: 0, seed: 4, core: "孤独宇宙")
        let api = composer.imageModelPrompt(distinguished, core: "孤独宇宙", seed: 4)
        XCTAssertTrue(distinguished.contains("孤独宇宙"), distinguished)
        XCTAssertTrue(api.contains("孤独宇宙"), api)
        XCTAssertFalse(api.localizedCaseInsensitiveContains("afternoon"), api)
        XCTAssertFalse(api.localizedCaseInsensitiveContains("courtyard"), api)
        XCTAssertFalse(distinguished.contains("院子"), distinguished)
    }

    func testPinCoreKeepsUserPresetWhenSceneDropsIt() {
        let pinned = composer.pinCore("马尔代夫的果冻海", onto: "黄昏时分开阔的热带浅海")
        XCTAssertTrue(pinned.hasPrefix("马尔代夫的果冻海"))
        XCTAssertTrue(pinned.contains("热带浅海"))
    }

    func testPinCoreRejectsSynonymOnlyRewrite() {
        let pinned = composer.pinCore("上海外滩", onto: "魔都江畔夜景，霓虹倒映在江面")
        XCTAssertTrue(pinned.hasPrefix("上海外滩"), pinned)
        XCTAssertTrue(composer.preservesCore("上海外滩", in: pinned))
    }

    func testPinCoreKeepsCommaSeparatedTokens() {
        let pinned = composer.pinCore("湿沥青、青蓝霓虹", onto: "雨后空旷街巷，远处楼影很淡")
        XCTAssertTrue(pinned.contains("湿沥青"), pinned)
        XCTAssertTrue(pinned.contains("青蓝霓虹"), pinned)
        XCTAssertTrue(composer.preservesCore("湿沥青、青蓝霓虹", in: pinned))
    }

    func testDistinguishLeakFallbackKeepsCoreNotGenericScenery() {
        var used = Set<String>()
        let scene = composer.distinguish(
            "一句审美定义，分辨率 3600x2338",
            used: &used,
            index: 0,
            seed: 3,
            core: "马尔代夫的果冻海"
        )
        XCTAssertTrue(scene.contains("马尔代夫的果冻海"))
        XCTAssertFalse(scene.contains("开阔的风景"))
        XCTAssertFalse(composer.containsInstructionLeak(scene), scene)
    }

    func testCurrentTypedIdeaIsTheOnlySubject() throws {
        var draft = PromptDraft(input: "超级无敌峡湾地貌")
        draft.mode = .inspiration
        let channel = InspirationChannel(
            name: "果冻海",
            essence: "马尔代夫的果冻海",
            coreKeywords: "马尔代夫的果冻海"
        )
        let result = try composer.resolve(draft: draft, channel: channel, display: .preview, seed: 2)
        XCTAssertTrue(result.contains("超级无敌峡湾地貌"))
        XCTAssertFalse(result.contains("马尔代夫"))
        XCTAssertFalse(result.contains("玻璃幕墙"))
        XCTAssertFalse(result.contains("湿沥青"))
        XCTAssertFalse(result.contains("路灯"))
    }

    func testMoodOnlyPromptGetsASpokenEmptyScene() {
        XCTAssertTrue(composer.isMoodTheme("温暖的春天的悠闲午后"))
        XCTAssertTrue(composer.isMoodTheme("温暖的午后，a woman sits"))
        XCTAssertTrue(composer.isMoodTheme("温暖的春天的悠闲午后，园子里的女人"))
        XCTAssertFalse(composer.isMoodTheme("美女"))
        XCTAssertFalse(composer.isMoodTheme("温暖的橘猫"))
        XCTAssertTrue(composer.needsGroundedScene("温暖的春天的悠闲午后"))
        XCTAssertFalse(composer.needsGroundedScene("雨夜的未来上海"))
        XCTAssertFalse(composer.needsGroundedScene("美女"))
        XCTAssertFalse(composer.needsGroundedScene("孤独宇宙"))
        XCTAssertFalse(composer.needsGroundedScene("安静、空旷、有探索感的宇宙场景"))
        XCTAssertFalse(composer.needsGroundedScene("宇宙"))
        let scene = composer.groundIfNeeded(
            "温暖的春天的悠闲午后，电影感，85mm，空气透视，巷口招牌上写着欢迎",
            core: "温暖的春天的悠闲午后",
            seed: 1
        )
        XCTAssertTrue(scene.hasPrefix("温暖的春天的悠闲午后"), scene)
        XCTAssertTrue(composer.hasConcretePlace(scene), scene)
        XCTAssertTrue(scene.contains("电影感") || scene.contains("85mm"), scene)
        XCTAssertFalse(scene.contains("没有文字"), scene)
        XCTAssertFalse(scene.contains("招牌"), scene)
        XCTAssertFalse(scene.contains("欢迎"), scene)
        XCTAssertFalse(scene.contains("， ，"), scene)
    }

    func testGlyphCarriersAreStrippedUnlessUserAsked() {
        let stripped = composer.stripUnrequestedGlyphCarriers(
            "温暖的春天的悠闲午后，巷口有招牌和海报",
            core: "温暖的春天的悠闲午后"
        )
        XCTAssertFalse(stripped.contains("招牌"), stripped)
        XCTAssertFalse(stripped.contains("海报"), stripped)
        let kept = composer.stripUnrequestedGlyphCarriers(
            "霓虹招牌的小巷，湿沥青",
            core: "霓虹招牌"
        )
        XCTAssertTrue(kept.contains("招牌"), kept)
    }

    func testSpokenRewriteTurnsChineseAgentEssayIntoEnglishScene() {
        let spoken = composer.spokenRewrite(
            "温暖的春天的悠闲午后，超广角机位，巷口招牌上写着欢迎",
            core: "温暖的春天的悠闲午后",
            seed: 1
        )
        XCTAssertFalse(composer.containsCJK(spoken), spoken)
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("spring") || spoken.localizedCaseInsensitiveContains("afternoon"), spoken)
        XCTAssertTrue(composer.hasConcreteSubject(spoken), spoken)
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("welcome"), spoken)
    }

    func testPortraitWrapDoesNotCallTheSceneUninhabited() {
        let prompt = composer.imageModelPrompt("a woman by a window", core: "美女")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("portrait") || prompt.localizedCaseInsensitiveContains("person"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("uninhabited"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("landscape photograph"), prompt)
    }

    func testSanitizeKeepsShotLanguageAndDropsPaintedWords() {
        let cleaned = composer.sanitizeVisualPrompt("孤独宇宙，低机位，35mm，电影感，没有文字，巷口招牌")
        XCTAssertTrue(cleaned.contains("孤独宇宙"), cleaned)
        XCTAssertTrue(cleaned.contains("低机位"), cleaned)
        XCTAssertTrue(cleaned.contains("35mm"), cleaned)
        XCTAssertTrue(cleaned.contains("电影感"), cleaned)
        XCTAssertFalse(cleaned.contains("没有文字"), cleaned)
        XCTAssertTrue(cleaned.contains("招牌"), cleaned)
    }

    func testEverydayObjectIsNotForcedIntoLandscapeOrCourtyard() {
        XCTAssertTrue(composer.hasConcreteSubject("橘猫"))
        XCTAssertTrue(composer.hasConcreteSubject("一杯咖啡"))
        XCTAssertTrue(composer.hasConcreteSubject("温暖的橘猫"))
        XCTAssertFalse(composer.needsGroundedScene("橘猫"))
        XCTAssertFalse(composer.needsGroundedScene("一杯咖啡"))
        XCTAssertFalse(composer.needsGroundedScene("温暖的橘猫"))
        XCTAssertTrue(composer.needsGroundedScene("温暖的春天的悠闲午后"))

        let cat = composer.imageModelPrompt("橘猫，低机位，35mm，电影感", core: "橘猫", seed: 2)
        XCTAssertTrue(cat.contains("橘猫"), cat)
        XCTAssertTrue(cat.contains("35mm") || cat.contains("电影感") || cat.localizedCaseInsensitiveContains("cinematic") || cat.contains("低机位"), cat)
        XCTAssertFalse(cat.localizedCaseInsensitiveContains("landscape photograph"), cat)
        XCTAssertFalse(cat.localizedCaseInsensitiveContains("uninhabited"), cat)
        XCTAssertFalse(cat.localizedCaseInsensitiveContains("courtyard"), cat)
        XCTAssertFalse(cat.localizedCaseInsensitiveContains("afternoon"), cat)
        XCTAssertFalse(cat.localizedCaseInsensitiveContains("no text"), cat)

        let coffee = composer.imageModelPrompt("一杯咖啡", core: "一杯咖啡", seed: 3)
        XCTAssertTrue(coffee.contains("一杯咖啡") || coffee.localizedCaseInsensitiveContains("coffee"), coffee)
        XCTAssertFalse(coffee.localizedCaseInsensitiveContains("landscape photograph"), coffee)
        XCTAssertFalse(coffee.localizedCaseInsensitiveContains("courtyard"), coffee)
    }

    func testNamedChineseSubjectSurvivesEnglishLastMile() {
        let dragon = "五爪金龙"
        let api = composer.imageModelPrompt(dragon, core: dragon, seed: 4)
        XCTAssertTrue(api.contains(dragon), api)
        XCTAssertFalse(api.localizedCaseInsensitiveContains("the given subject"), api)
        XCTAssertFalse(api.localizedCaseInsensitiveContains("courtyard"), api)

        let pinned = composer.pinCore(dragon, onto: "misty forest road, cinematic morning light")
        XCTAssertTrue(pinned.contains(dragon), pinned)

        let spoken = composer.spokenRewrite(
            "A quiet misty forest, wet road, morning light.",
            core: dragon,
            seed: 4
        )
        XCTAssertTrue(spoken.contains(dragon), spoken)

        let fromUI = composer.imageModelPrompt(
            "\(dragon)，开阔空间，空气里有一层薄雾，广角",
            core: dragon,
            seed: 4
        )
        XCTAssertTrue(fromUI.contains(dragon), fromUI)
        XCTAssertFalse(fromUI.localizedCaseInsensitiveContains("the given subject"), fromUI)
    }

    func testImageModelPromptIsPhotographNotLandscapeLock() {
        let ocean = composer.imageModelPrompt("a quiet ocean", core: "ocean")
        XCTAssertTrue(ocean.localizedCaseInsensitiveContains("photorealistic photograph"), ocean)
        XCTAssertFalse(ocean.localizedCaseInsensitiveContains("landscape photograph"), ocean)
        XCTAssertFalse(ocean.localizedCaseInsensitiveContains("uninhabited"), ocean)
    }

    func testImageModelPromptKeepsShortEnglishScene() {
        let prompt = composer.imageModelPrompt("a quiet ocean", core: "ocean")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("quiet") && prompt.localizedCaseInsensitiveContains("ocean"), prompt)
        XCTAssertFalse(composer.containsCJK(prompt), prompt)
    }

    func testImageModelPromptDropsCJKAndKeepsMoodMeaning() {
        let prompt = composer.imageModelPrompt(
            "温暖的春天的悠闲午后，电影感，巷口招牌上写着欢迎",
            core: "温暖的春天的悠闲午后",
            seed: 1
        )
        XCTAssertFalse(composer.containsCJK(prompt), prompt)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("spring") || prompt.localizedCaseInsensitiveContains("afternoon"), prompt)
        XCTAssertTrue(
            prompt.localizedCaseInsensitiveContains("balcony")
                || prompt.localizedCaseInsensitiveContains("courtyard")
                || prompt.localizedCaseInsensitiveContains("window")
                || prompt.localizedCaseInsensitiveContains("floor")
                || prompt.localizedCaseInsensitiveContains("person")
                || prompt.localizedCaseInsensitiveContains("cup")
                || prompt.localizedCaseInsensitiveContains("blanket")
                || prompt.localizedCaseInsensitiveContains("interior"),
            prompt
        )
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("no text"), prompt)
        XCTAssertFalse(prompt.contains("没有文字"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("welcome"), prompt)
    }

    func testImageModelPromptDoesNotPasteAfternoonOntoOtherSubjects() {
        let banned = ["afternoon", "courtyard", "balcony", "blanket", "spring afternoon"]
        for core in ["孤独宇宙", "安静、空旷、有探索感的宇宙场景", "雨夜的未来上海", "马尔代夫的果冻海"] {
            let prompt = composer.imageModelPrompt(core, core: core, seed: 3)
            XCTAssertTrue(prompt.contains(core) || (core.contains("宇宙") && prompt.contains("宇宙")) || prompt.localizedCaseInsensitiveContains("cosmos") || prompt.localizedCaseInsensitiveContains("shanghai") || prompt.localizedCaseInsensitiveContains("maldives"), prompt)
            for word in banned {
                XCTAssertFalse(prompt.localizedCaseInsensitiveContains(word), "\(core) leaked \(word): \(prompt)")
            }
        }
        XCTAssertTrue(
            composer.imageModelPrompt("孤独宇宙", core: "孤独宇宙", seed: 3).contains("孤独宇宙"),
            composer.imageModelPrompt("孤独宇宙", core: "孤独宇宙", seed: 3)
        )
    }

    func testWeaveDoesNotPinAfternoonCourtyardOntoCosmos() {
        let channel = InspirationChannel.sample
        var draft = PromptDraft(input: channel.essence)
        draft.mode = .inspiration
        let result = composer.weave(idea: channel.essence, combo: VariationPlanner().plan(idea: channel.essence, count: 1, seed: 4)[0], draft: draft, channel: channel)
        XCTAssertFalse(result.contains("院子"), result)
        XCTAssertFalse(result.contains("午后"), result)
        XCTAssertFalse(result.contains("春光"), result)
        XCTAssertFalse(result.contains("阳台"), result)
        XCTAssertTrue(result.contains("宇宙") || result.contains("空旷") || result.contains("孤独"), result)
    }

    func testImageModelPromptKeepsPlaceMeaningWithoutCJK() {
        let prompt = composer.imageModelPrompt(
            "马尔代夫的果冻海，黄昏时分开阔的热带浅海",
            core: "马尔代夫的果冻海",
            seed: 2
        )
        XCTAssertTrue(prompt.contains("马尔代夫的果冻海") || prompt.localizedCaseInsensitiveContains("maldives") || prompt.localizedCaseInsensitiveContains("lagoon"), prompt)
    }

    func testMoodFramesRotateSightingsAndKeepUserCore() {
        let core = "温暖的春天的悠闲午后"
        let prompts = composer.uniqueScenePrompts(
            idea: core, channel: nil, emptySpace: .none, seedBase: 11, count: 4
        )
        XCTAssertEqual(prompts.count, 4)
        var personHits = 0
        var emptyYardHits = 0
        var stillHits = 0
        var interiorHits = 0
        for prompt in prompts {
            XCTAssertTrue(prompt.contains(core), prompt)
            if composer.isFigureSubject(prompt) || prompt.contains("光里有一个人") { personHits += 1 }
            if prompt.contains("院子") || prompt.contains("阳台") || prompt.contains("空地方") { emptyYardHits += 1 }
            if prompt.contains("杯子") || prompt.contains("毯子") || prompt.contains("物件") { stillHits += 1 }
            if prompt.contains("室内") { interiorHits += 1 }
        }
        let kinds = [personHits, emptyYardHits, stillHits, interiorHits].filter { $0 > 0 }.count
        XCTAssertLessThan(personHits, 4, "心情句不能整批补人：\(prompts)")
        XCTAssertLessThan(emptyYardHits, 4, "心情句不能整批空院子：\(prompts)")
        XCTAssertGreaterThanOrEqual(kinds, 2, "心情句必须换看见什么：\(prompts)")
    }

    func testDistinguishUsesCoreSoWomanSceneDoesNotFlipTheme() {
        let core = "温暖的春天的悠闲午后"
        let polluted = "\(core)，窗边站着一个女人，全身站姿，人物是唯一亮部"
        var used: Set<String> = []
        let first = composer.distinguish(polluted, used: &used, index: 0, seed: 9, core: core)
        let second = composer.distinguish(polluted, used: &used, index: 1, seed: 9, core: core)
        XCTAssertTrue(first.contains(core), first)
        XCTAssertTrue(second.contains(core), second)
        let extra = VariationPlanner().plan(idea: core, count: 4, seed: 9 &+ 31)[2]
        XCTAssertEqual(extra.themeKey, "mood")
        XCTAssertNotEqual(extra.themeKey, "portrait")
    }

    func testShouldNotAdoptAgentFigureOntoMoodCore() {
        let locked = "温暖的春天的悠闲午后"
        XCTAssertFalse(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: "园子里的女人"))
        XCTAssertFalse(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: "\(locked)，园子里的女人"))
        XCTAssertFalse(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: "a woman sits in a sunlit courtyard"))
        XCTAssertTrue(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: "美女"))
        XCTAssertTrue(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: "橘猫"))
        XCTAssertTrue(composer.shouldAdoptTypedIdeaAsSeriesCore(locked: "", idea: locked))
    }

    func testMoodNegativesDoNotBanPerson() {
        let negative = composer.negativePrompt(draft: PromptDraft(input: "温暖的春天的悠闲午后"), channel: nil)
        XCTAssertFalse(negative.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains("人物"))
        XCTAssertFalse(negative.localizedCaseInsensitiveContains("person") && negative.split(whereSeparator: { $0 == "," }).contains(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "person" }))
    }

    func testNegativesIncludeSignageAndLanguage() {
        let negative = composer.negativePrompt(draft: PromptDraft(input: "温暖的春天的悠闲午后"), channel: nil)
        XCTAssertTrue(negative.contains("招牌"))
        XCTAssertTrue(negative.contains("中文") || negative.localizedCaseInsensitiveContains("chinese"))
        XCTAssertTrue(negative.contains("英文") || negative.localizedCaseInsensitiveContains("english"))
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("signage") || negative.contains("路牌"))
    }

    func testBatchPromptsKeepTheTypedPreset() {
        let prompts = composer.uniqueScenePrompts(
            idea: "马尔代夫的果冻海", channel: nil, emptySpace: .right, seedBase: 11, count: 4
        )
        XCTAssertEqual(prompts.count, 4)
        for prompt in prompts {
            XCTAssertTrue(prompt.contains("马尔代夫的果冻海"), prompt)
        }
    }

    func testLLaDAWrapUsesDaylightInsteadOfNoir() {
        let core = "一个咖啡店门口有一个黑板"
        let prompt = composer.imageModelPrompt(
            "夜雾里一个剪影，黑板上写着qwennewbee，volumetric fog, cinematic noir",
            core: core,
            seed: 2,
            model: "LLaDA-Image"
        )
        XCTAssertTrue(prompt.contains("电影感照片"), prompt)
        XCTAssertTrue(prompt.contains("咖啡店") || prompt.contains("黑板"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("those characters"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("this frame differs"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("photorealistic photograph"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("noir"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("volumetric fog"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("newbee"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("qwen"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("welcome"), prompt)
        XCTAssertFalse(prompt.contains("写着"), prompt)
    }

    func testLLaDAKeepsRequestedNightRain() {
        let core = "雨夜的未来上海"
        let prompt = composer.imageModelPrompt(
            "雨夜的未来上海，湿沥青倒映霓虹",
            core: core,
            seed: 3,
            model: "LLaDA-Image"
        )
        XCTAssertTrue(prompt.contains("雨") || prompt.contains("上海"), prompt)
        XCTAssertTrue(prompt.contains("电影感照片"), prompt)
        XCTAssertTrue(composer.containsCJK(prompt), prompt)
        XCTAssertFalse(prompt.contains("晴朗日光"), prompt)
        XCTAssertFalse(prompt.contains("正午强光"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("even daylight"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("bright natural daylight"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("sunny"), prompt)
        let plan = composer.framePlan(core: core, seed: 3, model: "LLaDA-Image")
        XCTAssertTrue(plan.wantsNight)
        XCTAssertTrue(plan.wantsRain)
        XCTAssertEqual(plan.dialect, .llada)
    }

    func testQwenWrapStaysPhotorealistic() {
        let ocean = composer.imageModelPrompt("a quiet ocean", core: "ocean", model: "Qwen-Image")
        XCTAssertTrue(ocean.localizedCaseInsensitiveContains("photorealistic photograph"), ocean)
        XCTAssertTrue(ocean.localizedCaseInsensitiveContains("fills the frame"), ocean)
        XCTAssertFalse(ocean.localizedCaseInsensitiveContains("even daylight, clean open space"), ocean)
    }

    func testChalkboardThemeIsTextRiskAndBlank() {
        let core = "一个咖啡店门口有一个黑板"
        XCTAssertTrue(composer.hasTextRisk(core))
        let plan = composer.framePlan(core: core, seed: 1, model: "LLaDA-Image")
        XCTAssertTrue(plan.textRisk)
        XCTAssertFalse(plan.wantsNight)
        XCTAssertTrue(plan.light.localizedCaseInsensitiveContains("daylight") || plan.light.localizedCaseInsensitiveContains("sun") || plan.light.localizedCaseInsensitiveContains("window"))
        let cleaned = composer.neutralizeSignLettering("黑板上写着welcome newbee", core: core)
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("welcome"), cleaned)
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("newbee"), cleaned)
        XCTAssertTrue(cleaned.contains("空白") || cleaned.localizedCaseInsensitiveContains("blank"), cleaned)
    }

    func testLLaDACrystalKeepsMineralNotAPerson() {
        let core = "晶石"
        let prompt = composer.imageModelPrompt(core, core: core, seed: 2, model: "LLaDA-Image")
        XCTAssertTrue(prompt.contains("晶石"), prompt)
        XCTAssertTrue(prompt.contains("电影感照片"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("given subject"), prompt)
        XCTAssertFalse(prompt.contains("女人"), prompt)
        XCTAssertFalse(prompt.contains("人像"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("person"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("woman"), prompt)
        let batch = (0..<4).map { index in
            composer.imageModelPrompt(core, core: core, seed: 42 + index, model: "LLaDA-Image")
        }
        XCTAssertEqual(Set(batch).count, 4, batch.joined(separator: "\n"))
        for item in batch {
            XCTAssertTrue(item.contains("晶石"), item)
        }
    }

    func testLLaDAAerialMaldivesDropsCJKAndInstructionEcho() {
        let core = "从水上飞机高空俯瞰地面，马尔代夫"
        let prompt = composer.imageModelPrompt(
            "\(core)，Those characters are the subject name. Keep them in the output. volumetric fog",
            core: core,
            seed: 2,
            model: "LLaDA-Image"
        )
        XCTAssertTrue(prompt.contains("电影感照片"), prompt)
        XCTAssertTrue(prompt.contains("马尔代夫") || prompt.contains("俯瞰"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("those characters"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("subject name"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("are the"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("volumetric fog"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("higher angle"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("from high above"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("looking down"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("this frame differs"), prompt)
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("natural-color photograph"), prompt)
        let batch = composer.uniqueScenePrompts(
            idea: core, channel: nil, emptySpace: .none, seedBase: 42, count: 4
        ).enumerated().map { index, scene in
            composer.imageModelPrompt(scene, core: core, seed: 42 + index, model: "LLaDA-Image")
        }
        XCTAssertEqual(Set(batch).count, 4, batch.joined(separator: "\n"))
        let qwenBatch = composer.uniqueScenePrompts(
            idea: core, channel: nil, emptySpace: .none, seedBase: 42, count: 4
        ).enumerated().map { index, scene in
            composer.imageModelPrompt(scene, core: core, seed: 42 + index, model: "Qwen-Image")
        }
        XCTAssertEqual(Set(qwenBatch).count, 4, qwenBatch.joined(separator: "\n"))
        let negative = composer.negativePrompt(
            draft: PromptDraft(input: core),
            channel: nil,
            model: "LLaDA-Image"
        )
        XCTAssertFalse(negative.localizedCaseInsensitiveContains("haze"), negative)
        XCTAssertFalse(negative.localizedCaseInsensitiveContains("blurry"), negative)
        XCTAssertFalse(negative.localizedCaseInsensitiveContains("letters"), negative)
        XCTAssertTrue(negative.localizedCaseInsensitiveContains("dock") || negative.localizedCaseInsensitiveContains("menu bar"), negative)
    }

    func testAlignVariationHintDropsFogWhenPlanIsDaylight() {
        let plan = composer.framePlan(core: "一个咖啡店门口有一个黑板", seed: 1, model: "LLaDA-Image")
        let aligned = composer.alignVariationHint("薄雾把后景削成淡色的层，广角强调空间深度", to: plan)
        XCTAssertFalse(aligned.contains("薄雾"), aligned)
        XCTAssertFalse(aligned.localizedCaseInsensitiveContains("mist"), aligned)
        XCTAssertTrue(aligned.contains("广角") || aligned.localizedCaseInsensitiveContains("wide"), aligned)
    }

    func testShortVisualClauseCutsEssayAndKeepsChinese() {
        XCTAssertEqual(composer.shortVisualClause("黄昏把海面烧成一条金色道路，超广角让近处浪很大"), "黄昏把海面烧成一条金色道路")
        XCTAssertTrue(composer.alignVariationHint("薄雾把后景削成淡色的层", to: composer.framePlan(core: "晨雾里的山谷", seed: 2)).contains("薄雾"))
    }

    func testFinishAgentPromptKeepsDialectAndChineseNames() {
        let llada = composer.finishAgentPrompt(
            "一张电影感照片，晶石，午后暖光，切面反光",
            core: "晶石",
            seed: 2,
            model: "LLaDA-Image"
        )
        XCTAssertTrue(llada.contains("晶石"), llada)
        XCTAssertTrue(llada.contains("电影感照片"), llada)
        XCTAssertFalse(llada.contains("女人"), llada)
        XCTAssertFalse(llada.localizedCaseInsensitiveContains("those characters"), llada)

        let dirtyLlada = composer.finishAgentPrompt(
            "主题：晶石\nThis frame differs by dusk\n黑板上写着qwennewbee",
            core: "晶石",
            seed: 2,
            model: "LLaDA-Image"
        )
        XCTAssertTrue(dirtyLlada.contains("晶石"), dirtyLlada)
        XCTAssertFalse(dirtyLlada.contains("主题："), dirtyLlada)
        XCTAssertFalse(dirtyLlada.localizedCaseInsensitiveContains("this frame differs"), dirtyLlada)
        XCTAssertFalse(dirtyLlada.localizedCaseInsensitiveContains("qwennewbee"), dirtyLlada)

        let qwen = composer.finishAgentPrompt(
            "五爪金龙盘在岩上，鳞片反光，云海铺到画面四边",
            core: "五爪金龙",
            seed: 3,
            model: "Qwen-Image"
        )
        XCTAssertTrue(qwen.contains("五爪金龙"), qwen)
        XCTAssertTrue(qwen.localizedCaseInsensitiveContains("photorealistic"), qwen)
        XCTAssertFalse(qwen.contains("女人"), qwen)
    }

    func testAlignVariationHintKeepsNamedFog() {
        let plan = composer.framePlan(core: "晨雾里的山谷", seed: 2, model: "LLaDA-Image")
        XCTAssertTrue(plan.wantsFog)
        let aligned = composer.alignVariationHint("薄雾把后景削成淡色的层", to: plan)
        XCTAssertTrue(aligned.contains("薄雾") || aligned.localizedCaseInsensitiveContains("mist") || aligned.contains("雾"), aligned)
    }
}
