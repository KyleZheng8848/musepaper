import Foundation

@main
struct BatchFlowSmoke {
    @MainActor
    static func main() async throws {
        guard AppVersion.marketing.split(separator: ".").count == 3, !AppVersion.display.isEmpty else {
            fatalError("App version must be managed and visible")
        }
        guard OpenAIImageProvider.looksLikeChatModel("Hy3"),
              !OpenAIImageProvider.looksLikeChatModel("Qwen-Image-2512-Lightning") else {
            fatalError("Chat models must not be accepted as image models")
        }
        guard !OpenAIImageProvider.usesOfficialOpenAIImageAPI(baseURL: "https://antchat.alipay.com/v1"),
              OpenAIImageProvider.usesOfficialOpenAIImageAPI(baseURL: "https://api.openai.com/v1") else {
            fatalError("Compatible image APIs must not use the official OpenAI image protocol")
        }

        let composer = PromptComposer()
        let pinned = composer.pinCore("马尔代夫的果冻海", onto: "黄昏时分开阔的热带浅海")
        guard pinned.contains("马尔代夫的果冻海") else {
            fatalError("pinCore must keep the user preset")
        }
        var used = Set<String>()
        let distinguished = composer.distinguish(
            "一句审美定义，分辨率 3600x2338", used: &used, index: 0, seed: 3, core: "马尔代夫的果冻海"
        )
        guard distinguished.contains("马尔代夫的果冻海"), !distinguished.contains("开阔的风景") else {
            fatalError("distinguish must fall back to the user core, not generic scenery")
        }
        for scene in composer.uniqueScenePrompts(idea: "马尔代夫的果冻海", channel: nil, emptySpace: .right, seedBase: 11, count: 4) {
            guard scene.contains("马尔代夫的果冻海") else {
                fatalError("Every candidate prompt must keep the typed preset: \(scene)")
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-batch-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioViewModel(
            store: JSONStore(fileURL: root.appendingPathComponent("state.json")),
            generationOutputDirectory: root.appendingPathComponent("images", isDirectory: true),
            credentialStore: CredentialStore(fileURL: root.appendingPathComponent("credentials.json"))
        )
        try await Task.sleep(for: .milliseconds(150))
        guard model.generationBlockReason?.contains("先用演示出图") == true else {
            fatalError("Missing-key state must keep the user on create and offer demo")
        }
        guard model.generateActionTitle == "先用演示出图" else {
            fatalError("Generate button must say demo, not send people to settings")
        }
        model.useOfflineDemo()
        guard model.canGenerate, model.activeModelConfiguration?.provider == .demo else {
            fatalError("Offline demo must unblock generation in place")
        }
        model.isOptimizingPrompt = true
        guard model.hasActiveResults, model.creationStageTitle == "正在想画面" else {
            fatalError("Clicking generate must immediately show the canvas workspace")
        }
        model.isOptimizingPrompt = false
        guard let demo = model.modelConfigurations.first(where: { $0.provider == .demo }) else {
            fatalError("Demo provider missing")
        }
        model.selectModelConfiguration(demo.id)
        model.beginNewSeries()
        guard model.creatingTaskFromComposer,
              model.shouldFocusComposer,
              model.generationBlockReason == "先在下面写下想看的画面，再点出图。" else {
            fatalError("New series must be a sentence plus generate, not a form")
        }
        model.startNewIdea()
        guard model.creatingTaskFromComposer,
              model.selectedChannelID == nil,
              model.generationBlockReason == "先在下面写下想看的画面，再点出图。" else {
            fatalError("Plus and 新系列 must be the same blank-series path")
        }
        model.channels[0].essence = "晨雾里的山谷，柔和而辽阔"
        model.selectChannel(model.channels[0].id)
        guard model.draft.input.contains("晨雾里的山谷") else {
            fatalError("Selecting a series must restore its saved prompt")
        }
        model.draft.input = "雨后的山谷，柔和而辽阔"
        model.rememberPromptOnSelectedSeries()
        guard model.channels[0].essence.contains("雨后的山谷") else {
            fatalError("Prompt typed on a series must be written back")
        }
        model.draft.input = "超级无敌峡湾地貌"
        model.rememberPromptOnSelectedSeries()
        guard model.channels[0].resolvedCoreKeywords == "超级无敌峡湾地貌" else {
            fatalError("A later short rewrite must become the series core")
        }
        model.draft.input = "一句审美定义，分辨率 3600x2338"
        model.rememberPromptOnSelectedSeries()
        guard model.channels[0].resolvedCoreKeywords == "超级无敌峡湾地貌" else {
            fatalError("An instruction essay must not steal the series core")
        }
        let fjord = composer.uniqueScenePrompts(
            idea: "超级无敌峡湾地貌", channel: nil, emptySpace: .none, seedBase: 21, count: 4
        )
        for scene in fjord {
            guard scene.contains("超级无敌峡湾地貌") else {
                fatalError("Fjord batch must keep the typed landform: \(scene)")
            }
            guard !scene.contains("玻璃幕墙"), !scene.contains("湿沥青"), !scene.contains("马尔代夫"),
                  !scene.contains("孤树"), !scene.contains("路灯"), !scene.contains("钟楼") else {
                fatalError("Fjord batch must vary dimensions, not add props: \(scene)")
            }
        }
        model.draft.input = ""
        guard model.generationBlockReason == nil else {
            fatalError("A selected task must allow generating without extra text")
        }
        let sketched = InspirationChannel(name: "", essence: "", coreKeywords: "")
            .completingMissingFields(idea: "潮湿、安静、有巨大空间感的未来上海")
        guard !sketched.name.isEmpty,
              sketched.essence.contains("未来上海") else {
            fatalError("One sentence must be enough to create a task")
        }
        model.setTaskSchedule(model.channels[0].id, enabled: true, count: 2, intervalHours: 4)
        guard model.channels[0].resolvedScheduleEnabled,
              model.channels[0].resolvedScheduleIntervalHours == 4,
              model.scheduleSummary(for: model.channels[0]).contains("下次") else {
            fatalError("Task schedule must continue the series on an interval")
        }
        model.selectChannel(nil)
        model.draft.input = "安静的海岸，保持主体一致"
        model.batchSize = 4
        model.refreshResolvedPrompt()
        model.generate()

        for _ in 0..<200 where model.isGenerating {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !model.isGenerating else { fatalError("Batch generation timed out") }
        guard model.activeCandidates.count == 4 else {
            fatalError("Expected 4 candidates, got \(model.activeCandidates.count): \(model.notice ?? "no notice")")
        }
        guard model.selectedCandidateID == model.activeCandidates.first?.id else {
            fatalError("First candidate was not selected by default")
        }
        guard model.activeCandidates.allSatisfy({ $0.state == .ready }) else {
            fatalError("Generation unexpectedly applied a candidate")
        }
        guard model.activeCandidates.allSatisfy({ $0.resolvedTags.count >= 2 }) else {
            fatalError("Generated artwork is missing multiple tags")
        }
        let collection = SmartCollection(name: "横向作品", includeTags: ["横向壁纸"])
        model.saveCollection(collection)
        guard model.filteredArtworks.count == 4 else {
            fatalError("Smart collection did not dynamically include generated artworks")
        }
        let playlist = WallpaperPlaylist(name: "全部轮播", source: .all)
        model.savePlaylist(playlist)
        guard model.playlistArtworkCount(playlist) == 4 else {
            fatalError("Playlist source did not resolve generated artworks")
        }
        let third = model.activeCandidates[2]
        model.selectCandidate(third.id)
        guard model.latestImageURL?.path == third.imagePath else {
            fatalError("Selecting candidate 3 did not update preview")
        }
        guard model.canAdoptSelected, model.canApplySelected else {
            fatalError("Selecting a candidate must unlock wallpaper and regenerate actions")
        }
        guard model.batches.first?.selectedRecordID != third.id else {
            fatalError("Selecting a candidate must not adopt it as the series seed yet")
        }
        model.applySelectedCandidate()
        guard model.batches.first?.selectedRecordID == third.id else {
            fatalError("Setting wallpaper must confirm the selected candidate in the batch")
        }
        model.useArtworkAsReference(third.id)
        guard model.displayedReferencePaths.contains(third.imagePath ?? "") || model.draft.referenceImagePaths == [third.imagePath ?? ""] else {
            fatalError("A generated artwork must be usable as the next series reference")
        }
        let paths = Set(model.activeCandidates.compactMap(\.imagePath))
        guard paths.count == 4 else { fatalError("Candidate files are not unique") }
        let prompts = model.activeCandidates.map(\.request.resolvedPrompt)
        guard Set(prompts).count == 4 else { fatalError("Batch resolvedPrompts must all differ: \(prompts)") }
        for prompt in prompts {
            if prompt.contains("用户原始想法") || prompt.contains("本地约束草稿")
                || prompt.contains("原初想法") || prompt.contains("避免：") || prompt.contains("没有文字") {
                fatalError("Image prompt leaked briefing: \(prompt)")
            }
        }
        let sample = model.activeCandidates[0]
        let excluded = SmartCollection(name: "排除已有标签", excludeTags: [sample.resolvedTags[0]])
        guard !excluded.includes(sample) else {
            fatalError("Exclude-tag collections must reject matching tags")
        }
        let doomed = sample
        model.deleteRecord(doomed.id)
        guard let trashed = model.records.first(where: { $0.id == doomed.id }), trashed.isTrashed else {
            fatalError("Artwork delete must move the record into trash")
        }
        guard !model.usableArtworks.contains(where: { $0.id == doomed.id }) else {
            fatalError("Trashed artwork must leave the usable library")
        }
        model.restoreFromTrash(doomed.id)
        guard model.records.contains(where: { $0.id == doomed.id && !$0.isTrashed }) else {
            fatalError("Trash restore must bring the artwork back")
        }
        model.deleteRecord(doomed.id)
        model.purgeFromTrash(doomed.id)
        guard !model.records.contains(where: { $0.id == doomed.id }) else {
            fatalError("Purge must permanently remove the record")
        }
        model.displayProbeOverride = [
            DisplayProbe(width: 3600, height: 2338, scale: 2),
            DisplayProbe(width: 1920, height: 1080, scale: 1)
        ]
        model.refreshDisplays()
        guard model.displayProfiles.count == 2,
              model.displayProfiles[0].name == "主显示器",
              model.displayProfiles[1].name == "显示器 2",
              model.wallpaperTargetLabel(for: model.displayProfiles[0]) == "只贴到：主显示器 · 3600×2338" else {
            fatalError("Display self-check must list main and extra screens in plain language")
        }
        model.selectWallpaperTarget("screen-1")
        guard model.settings.applyToAllDisplays == false,
              model.settings.selectedDisplayID == "screen-1",
              model.wallpaperApplyIntent == WallpaperApplyIntent(targetDisplayID: "screen-1", allDisplays: false) else {
            fatalError("Single-display wallpaper target must write settings and apply intent")
        }
        model.selectWallpaperTarget(StudioViewModel.allDisplaysTargetID)
        guard model.settings.applyToAllDisplays,
              model.wallpaperApplyIntent.allDisplays,
              model.wallpaperTargetID == StudioViewModel.allDisplaysTargetID else {
            fatalError("All-displays wallpaper target must write settings and apply intent")
        }
        let liveDisplays = DisplayService().profiles()
        guard !liveDisplays.isEmpty, liveDisplays[0].name == "主显示器" else {
            fatalError("Live display probe must find at least the main screen")
        }
        print("BATCH_FLOW_OK count=4 tags=multiple smart_collection=4 playlist_source=4 selected=3 applied=0 unique_files=4 schedule=task-level generate=explained displays=self-check")
    }
}
