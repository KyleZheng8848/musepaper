import Foundation
import XCTest
@testable import Musepaper

@MainActor
final class StudioViewModelTests: XCTestCase {
    func testDefaultRealProviderRequiresAPIKey() {
        let model = makeModel()

        XCTAssertFalse(model.canGenerate)
        XCTAssertEqual(model.modelStatusTitle, "需要配置 API Key")
    }

    func testDemoProviderCanGenerateWithoutAPIKey() {
        let model = makeModel()
        let demo = try! XCTUnwrap(model.modelConfigurations.first { $0.provider == .demo })

        model.selectModelConfiguration(demo.id)

        XCTAssertTrue(model.canGenerate)
        XCTAssertEqual(model.modelStatusTitle, "离线演示已就绪")
    }

    func testEndpointPreviewShowsActualRequestURL() {
        let model = makeModel()

        XCTAssertEqual(
            model.generationEndpointPreview,
            "https://api.openai.com/v1/images/generations"
        )
    }

    func testInitialPromptIsNotHardcoded() {
        let model = makeModel()

        XCTAssertTrue(model.draft.input.isEmpty)
        XCTAssertTrue(model.finalPrompt.isEmpty)
    }

    func testCandidateSelectionControlsPreview() {
        let model = makeModel()
        let batchID = UUID()
        let first = makeRecord(path: "/tmp/first.png", batchID: batchID)
        let second = makeRecord(path: "/tmp/second.png", batchID: batchID)
        model.records = [first, second]
        model.batches = [GenerationBatch(
            id: batchID, seriesID: nil, recordIDs: [first.id, second.id], selectedRecordID: first.id,
            prompt: "test", trigger: .manual, state: .ready, createdAt: Date(), errorMessage: nil
        )]
        model.activeBatchID = batchID
        model.selectedCandidateID = first.id

        model.selectCandidate(second.id)

        XCTAssertEqual(model.selectedCandidateID, second.id)
        XCTAssertEqual(model.latestImageURL?.path, "/tmp/second.png")
        XCTAssertEqual(model.batches[0].selectedRecordID, first.id)
        XCTAssertFalse(model.canApplySelected)
        XCTAssertTrue(model.canAdoptSelected)
        XCTAssertFalse(model.isSelectedAdopted)
    }

    func testGenerationBlockReasonWhenMissingKey() {
        let model = makeModel()
        XCTAssertEqual(model.generationBlockReason, "还没连接图片模型。点「先用演示出图」可以立刻走完流程；真实出图去设置里填 API Key。")
    }

    func testUseOfflineDemoUnblocksGenerationWithoutLeavingCreate() {
        let model = makeModel()
        XCTAssertFalse(model.canGenerate)
        XCTAssertEqual(model.generateActionTitle, "先用演示出图")

        model.useOfflineDemo()

        XCTAssertTrue(model.canGenerate)
        XCTAssertEqual(model.activeModelConfiguration?.provider, .demo)
    }

    func testPreparingPromptShowsWorkspaceImmediately() {
        let model = makeModel()
        XCTAssertFalse(model.hasActiveResults)

        model.isOptimizingPrompt = true

        XCTAssertTrue(model.hasActiveResults)
        XCTAssertEqual(model.creationStageTitle, "正在想画面")
        XCTAssertEqual(model.stopActionTitle, "停止构思")

        model.cancelCreation()
        XCTAssertFalse(model.isOptimizingPrompt)
        XCTAssertFalse(model.isCreationBusy)
    }

    func testEmptyDirectPromptIsBlockedAfterDemoIsReady() {
        let model = makeModel()
        let demo = try! XCTUnwrap(model.modelConfigurations.first { $0.provider == .demo })
        model.selectModelConfiguration(demo.id)

        XCTAssertEqual(model.generationBlockReason, "先在下面写下想看的画面，再点出图。")

        model.draft.input = "雨后的上海"
        XCTAssertNil(model.generationBlockReason)
    }

    func testSelectedTaskAllowsEmptyPrompt() {
        let model = makeModel()
        let demo = try! XCTUnwrap(model.modelConfigurations.first { $0.provider == .demo })
        model.selectModelConfiguration(demo.id)
        model.selectChannel(model.channels[0].id)
        model.draft.input = ""

        XCTAssertNil(model.generationBlockReason)
    }

    func testOneSentenceTaskFillsMissingFields() {
        let channel = InspirationChannel(name: "", essence: "", coreKeywords: "")
            .completingMissingFields(idea: "潮湿、安静、有巨大空间感的未来上海")

        XCTAssertEqual(channel.name, String("潮湿、安静、有巨大空间感的未来上海".prefix(16)))
        XCTAssertEqual(channel.essence, "潮湿、安静、有巨大空间感的未来上海")
        XCTAssertEqual(channel.resolvedCoreKeywords, "潮湿、安静、有巨大空间感的未来上海")
    }

    func testSelectingSeriesRestoresSavedPrompt() {
        let model = makeModel()
        model.channels[0].essence = "晨雾里的山谷，柔和而辽阔"
        model.selectChannel(model.channels[0].id)
        XCTAssertEqual(model.draft.input, "晨雾里的山谷，柔和而辽阔")
    }

    func testTypingCreatesSeriesWithoutEditor() {
        let model = makeModel()
        model.beginNewSeries()
        XCTAssertTrue(model.creatingTaskFromComposer)
        model.draft.input = "马尔代夫的果冻海"
        model.draftInputDidChange()
        XCTAssertFalse(model.creatingTaskFromComposer)
        XCTAssertEqual(model.selectedChannel?.essence, "马尔代夫的果冻海")
        XCTAssertTrue(model.channels.contains { $0.essence == "马尔代夫的果冻海" })
    }

    func testPromptTypedOnSeriesIsWrittenBack() {
        let model = makeModel()
        model.selectChannel(model.channels[0].id)
        model.draft.input = "晨雾里的山谷，柔和而辽阔"
        model.rememberPromptOnSelectedSeries()
        XCTAssertEqual(model.channels[0].essence, "晨雾里的山谷，柔和而辽阔")
    }

    func testShortRewriteBecomesTheCoreAndEssayCannotStealIt() {
        let model = makeModel()
        model.beginNewSeries()
        model.draft.input = "马尔代夫的果冻海"
        model.draftInputDidChange()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "马尔代夫的果冻海")

        model.draft.input = "超级无敌峡湾地貌"
        model.draftInputDidChange()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "超级无敌峡湾地貌")
        XCTAssertEqual(model.selectedChannel?.essence, "超级无敌峡湾地貌")
        XCTAssertEqual(model.selectedChannel?.name, "超级无敌峡湾地貌")

        let id = try! XCTUnwrap(model.selectedChannelID)
        model.draft.input = "一句审美定义，分辨率 3600x2338，开阔的风景铺到四边"
        model.rememberPromptOnSelectedSeries()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "超级无敌峡湾地貌")

        if let index = model.channels.firstIndex(where: { $0.id == id }) {
            model.channels[index].essence = "一句审美定义，分辨率 3600x2338，开阔的风景铺到四边"
        }
        model.selectChannel(id)
        XCTAssertEqual(model.draft.input, "超级无敌峡湾地貌")
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "超级无敌峡湾地貌")
    }

    func testMoodSeriesKeepsCoreWhenAgentWritesAWoman() {
        let model = makeModel()
        model.beginNewSeries()
        model.draft.input = "温暖的春天的悠闲午后"
        model.draftInputDidChange()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "温暖的春天的悠闲午后")

        model.draft.input = "园子里的女人"
        model.draftInputDidChange()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "温暖的春天的悠闲午后")
        XCTAssertEqual(model.selectedChannel?.essence, "温暖的春天的悠闲午后")

        model.draft.input = "橘猫"
        model.draftInputDidChange()
        XCTAssertEqual(model.selectedChannel?.resolvedCoreKeywords, "橘猫")
    }

    func testEditorIdeaBecomesSeriesEssence() {
        let saved = InspirationChannel(name: "简短系列名", essence: "一句审美定义", coreKeywords: "逗号分隔的不可变核心词")
            .completingMissingFields(idea: "晨雾里的山谷，柔和而辽阔")
        XCTAssertEqual(saved.essence, "晨雾里的山谷，柔和而辽阔")
        XCTAssertFalse(saved.name.contains("简短系列名"))
        XCTAssertTrue(saved.name.contains("晨雾"))
        XCTAssertFalse(saved.isSchemaTemplate)
    }

    func testSetTaskScheduleEnablesDailyIngest() {
        let model = makeModel()
        let id = model.channels[0].id

        model.setTaskSchedule(id, enabled: true, count: 2, intervalHours: 4)

        XCTAssertTrue(model.channels[0].resolvedScheduleEnabled)
        XCTAssertEqual(model.channels[0].resolvedScheduleIntervalHours, 4)
        XCTAssertEqual(model.channels[0].resolvedScheduledCandidateCount, 2)
        XCTAssertTrue(model.scheduleSummary(for: model.channels[0]).hasPrefix("下次 "))
        XCTAssertEqual(model.scheduleBadge(for: model.channels[0]), "自动")
    }

    func testBatchSizeAndCadenceAreWiderThanFourAndDaily() {
        let model = makeModel()
        model.selectChannel(model.channels[0].id)
        model.setBatchSize(12)
        XCTAssertEqual(model.batchSize, 12)
        XCTAssertEqual(model.channels[0].resolvedCandidateCount, 12)
        model.setTaskSchedule(model.channels[0].id, enabled: true, count: 6, intervalHours: 5)
        XCTAssertEqual(model.channels[0].resolvedScheduledCandidateCount, 6)
        XCTAssertEqual(model.channels[0].resolvedScheduleIntervalHours, 5)
        XCTAssertEqual(InspirationChannel.cadenceLabel(1), "每小时")
        XCTAssertEqual(InspirationChannel.cadenceLabel(5), "每 5 小时")
        XCTAssertEqual(InspirationChannel.cadenceLabel(48), "每 2 天")
        XCTAssertEqual(InspirationChannel.cadenceLabel(168), "每 7 天")
        XCTAssertEqual(InspirationChannel.cadenceLabel(seconds: 1), "每 10 秒")
        XCTAssertEqual(
            InspirationChannel.cadenceLabel(
                seconds: 1,
                minSeconds: WallpaperPlaylist.minIntervalSeconds,
                maxSeconds: WallpaperPlaylist.maxIntervalSeconds
            ),
            "每 1 秒"
        )
        XCTAssertEqual(InspirationChannel.clampedCount(12), 12)
        XCTAssertEqual(InspirationChannel.clampedCount(24), 24)
        XCTAssertEqual(InspirationChannel.clampedCount(128), 128)
        XCTAssertEqual(InspirationChannel.clampedCount(9999), 9999)
        XCTAssertEqual(InspirationChannel.clampedCount(100_000), 9_999)
        XCTAssertEqual(InspirationChannel.clampedInterval(0), 1)
        XCTAssertEqual(InspirationChannel.clampedInterval(200), 168)
        XCTAssertTrue(InspirationChannel.intervalRange.contains(5))
        XCTAssertEqual(InspirationChannel.clampedIntervalSeconds(3), 10)
        XCTAssertEqual(InspirationChannel.seconds(days: 0, hours: 0, minutes: 1, seconds: 30), 90)
        XCTAssertEqual(InspirationChannel.intervalComponents(90).minutes, 1)
        XCTAssertEqual(InspirationChannel.intervalComponents(90).seconds, 30)
    }

    func testSelectEnablesWallpaperWithoutAdopt() {
        let model = makeModel()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-adopt-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstPath = folder.appendingPathComponent("first.png").path
        let secondPath = folder.appendingPathComponent("second.png").path
        FileManager.default.createFile(atPath: firstPath, contents: Data([0x89, 0x50]), attributes: nil)
        FileManager.default.createFile(atPath: secondPath, contents: Data([0x89, 0x51]), attributes: nil)

        let taskID = model.channels[0].id
        let batchID = UUID()
        let first = makeRecord(path: firstPath, batchID: batchID, seriesID: taskID)
        let second = makeRecord(path: secondPath, batchID: batchID, seriesID: taskID)
        model.records = [first, second]
        model.batches = [GenerationBatch(
            id: batchID, seriesID: taskID, recordIDs: [first.id, second.id], selectedRecordID: first.id,
            prompt: "test", trigger: .manual, state: .ready, createdAt: Date(), errorMessage: nil
        )]
        model.activeBatchID = batchID
        model.selectedCandidateID = first.id
        model.selectChannel(taskID)
        model.channels[0].seedArtworkID = first.id
        model.channels[0].seedArtworkPath = firstPath
        model.setUseReferenceImages(true)

        XCTAssertEqual(model.displayedReferencePaths, [firstPath])

        model.selectCandidate(second.id)

        XCTAssertEqual(model.selectedCandidateID, second.id)
        XCTAssertEqual(model.channels[0].seedArtworkID, first.id)
        XCTAssertEqual(model.channels[0].seedArtworkPath, firstPath)
        XCTAssertEqual(model.displayedReferencePaths, [firstPath])
        XCTAssertEqual(model.batches[0].selectedRecordID, first.id)
        XCTAssertTrue(model.canApplySelected)
        XCTAssertTrue(model.canRegenerateSelected)
        XCTAssertEqual(model.adoptActionTitle, "重新生成")

        // Applying wallpaper adopts the seed; selecting alone does not.
        model.applySelectedCandidate()
        XCTAssertEqual(model.batches[0].selectedRecordID, second.id)
    }

    func testReferenceCanBeTurnedOffAndStaysOff() {
        let model = makeModel()
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("musepaper-ref-\(UUID().uuidString).png").path
        FileManager.default.createFile(atPath: path, contents: Data([0x89, 0x50]), attributes: nil)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let taskID = model.channels[0].id
        let batchID = UUID()
        let record = makeRecord(path: path, batchID: batchID, seriesID: taskID)
        model.records = [record]
        model.batches = [GenerationBatch(
            id: batchID, seriesID: taskID, recordIDs: [record.id], selectedRecordID: record.id,
            prompt: "test", trigger: .manual, state: .ready, createdAt: Date(), errorMessage: nil
        )]
        model.activeBatchID = batchID
        model.selectChannel(taskID)
        model.useArtworkAsReference(record.id)

        XCTAssertEqual(model.displayedReferencePaths, [path])

        model.setUseReferenceImages(false)
        XCTAssertTrue(model.displayedReferencePaths.isEmpty)
        XCTAssertFalse(model.useReferenceImages)

        model.selectCandidate(record.id)
        XCTAssertTrue(model.displayedReferencePaths.isEmpty)
        XCTAssertFalse(model.useReferenceImages)

        model.selectChannel(taskID)
        XCTAssertFalse(model.useReferenceImages)

        model.setUseReferenceImages(true)
        XCTAssertEqual(model.displayedReferencePaths, [path])
        XCTAssertTrue(model.useReferenceImages)

        model.setUseReferenceImages(false)
        model.adoptSeriesSeed(record, applyToDraft: true)
        XCTAssertTrue(model.useReferenceImages)
        XCTAssertEqual(model.displayedReferencePaths, [path])
    }

    func testIntervalScheduleFiresFromLastProduction() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 17
        components.hour = 10
        let now = Calendar.current.date(from: components)!
        let last = now.addingTimeInterval(-3600)
        let next = ScheduleService.nextFireDate(intervalHours: 4, lastProducedAt: last, from: now)
        XCTAssertEqual(next.timeIntervalSince(last), 4 * 3600, accuracy: 1)
        let overdue = ScheduleService.nextFireDate(intervalHours: 4, lastProducedAt: now.addingTimeInterval(-8 * 3600), from: now)
        XCTAssertGreaterThan(overdue, now)
        XCTAssertLessThan(overdue.timeIntervalSince(now), 120)
        let soon = ScheduleService.nextFireDate(intervalSeconds: 90, lastProducedAt: now, from: now)
        XCTAssertEqual(soon.timeIntervalSince(now), 90, accuracy: 1)
    }

    func testBatchResolvedPromptsAreAllDifferent() async throws {
        let model = makeModel()
        model.useOfflineDemo()
        model.draft.input = "魔幻世界风景"
        model.batchSize = 4
        model.refreshResolvedPrompt()
        model.generate()
        for _ in 0..<200 where model.isGenerating {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.activeCandidates.count, 4)
        let prompts = model.activeCandidates.map(\.request.resolvedPrompt)
        XCTAssertEqual(Set(prompts).count, 4, "同一批 resolvedPrompt 必须两两不同：\(prompts)")
        for prompt in prompts {
            XCTAssertFalse(prompt.contains("用户原始想法"), prompt)
            XCTAssertFalse(prompt.contains("本地约束草稿"), prompt)
            XCTAssertFalse(prompt.contains("原初想法"), prompt)
            XCTAssertFalse(prompt.contains("避免："), prompt)
            XCTAssertFalse(prompt.contains("没有文字"), prompt)
        }
    }

    func testWallpaperTargetWritesAllDisplaysAndSingleScreen() {
        let model = makeModel()
        model.displayProbeOverride = [
            DisplayProbe(width: 3600, height: 2338, scale: 2),
            DisplayProbe(width: 1920, height: 1080, scale: 1)
        ]
        model.refreshDisplays()

        XCTAssertEqual(model.displayProfiles.count, 2)
        XCTAssertEqual(model.displayProfiles[0].name, "主显示器")
        XCTAssertEqual(model.displayProfiles[1].name, "显示器 2")
        XCTAssertEqual(model.wallpaperTargetLabel(for: model.displayProfiles[0]), "只贴到：主显示器 · 3600×2338")

        model.selectWallpaperTarget("screen-1")
        XCTAssertFalse(model.settings.applyToAllDisplays)
        XCTAssertEqual(model.settings.selectedDisplayID, "screen-1")
        XCTAssertEqual(model.wallpaperApplyIntent, WallpaperApplyIntent(targetDisplayID: "screen-1", allDisplays: false))

        model.selectWallpaperTarget(StudioViewModel.allDisplaysTargetID)
        XCTAssertTrue(model.settings.applyToAllDisplays)
        XCTAssertEqual(model.wallpaperApplyIntent.allDisplays, true)
        XCTAssertEqual(model.wallpaperTargetID, StudioViewModel.allDisplaysTargetID)
    }

    func testCreatePageCanSwitchImageModel() {
        let model = makeModel()
        let demo = try! XCTUnwrap(model.modelConfigurations.first { $0.provider == .demo })
        XCTAssertTrue(model.imageModelPickerTitle(for: demo).contains("离线演示"))
        model.selectModelConfiguration(demo.id)
        XCTAssertEqual(model.activeModelConfigurationID, demo.id)
        XCTAssertEqual(model.imageModelCaption, "离线演示")
    }

    func testPathwayMismatchWhenImageModelDrifts() {
        let model = makeModel()
        var config = model.modelConfigurations[0]
        config.provider = .compatible
        config.baseURL = "https://antchat.alipay.com/v1"
        config.model = "Qwen-Image-2512-Lightning"
        model.updateActiveModelConfiguration(config)
        model.verifiedImageRoute = ImageRoute.from(config)
        XCTAssertNil(model.pathwayMismatchReason)
        XCTAssertTrue(model.imageModelCaption.contains("Qwen-Image-2512-Lightning"))

        config.model = "Hy3"
        model.updateActiveModelConfiguration(config)
        XCTAssertNotNil(model.pathwayMismatchReason)
        XCTAssertTrue(model.pathwayMismatchReason?.contains("Hy3") == true)
    }

    func testHistoricalRecordIsNotMistakenForActiveCandidate() {
        let model = makeModel()
        let historical = makeRecord(path: "/tmp/old.png", batchID: UUID())
        model.records = [historical]
        model.selectedCandidateID = historical.id

        XCTAssertNil(model.latestImageURL)
        XCTAssertFalse(model.canApplySelected)
    }

    func testSelectingSeriesShowsAllSeriesImagesChronologically() throws {
        let model = makeModel()
        let seriesID = try XCTUnwrap(model.channels.first?.id)
        let olderPath = try touchTempPNG()
        let newerPath = try touchTempPNG()
        let olderBatch = UUID()
        let newerBatch = UUID()
        let older = makeRecord(
            path: olderPath,
            batchID: olderBatch,
            seriesID: seriesID,
            createdAt: Date().addingTimeInterval(-3600)
        )
        let newer = makeRecord(
            path: newerPath,
            batchID: newerBatch,
            seriesID: seriesID,
            createdAt: Date()
        )
        let other = makeRecord(path: try touchTempPNG(), batchID: UUID(), seriesID: UUID())
        model.records = [newer, older, other]
        model.batches = [
            GenerationBatch(
                id: newerBatch, seriesID: seriesID, recordIDs: [newer.id], selectedRecordID: newer.id,
                prompt: "n", trigger: .manual, state: .ready, createdAt: Date(), errorMessage: nil
            ),
            GenerationBatch(
                id: olderBatch, seriesID: seriesID, recordIDs: [older.id], selectedRecordID: older.id,
                prompt: "o", trigger: .manual, state: .ready, createdAt: Date().addingTimeInterval(-3600), errorMessage: nil
            )
        ]
        // Wrong active batch on purpose — selecting the series must still show both images.
        model.activeBatchID = olderBatch
        model.selectedCandidateID = older.id

        model.selectChannel(seriesID)

        XCTAssertEqual(model.activeCandidates.map(\.id), [older.id, newer.id])
        XCTAssertEqual(model.selectedCandidateID, newer.id)
        XCTAssertEqual(model.latestImageURL?.path, newerPath)
    }

    func testStartNewIdeaClearsSeriesAndPreview() throws {
        let model = makeModel()
        let seriesID = try XCTUnwrap(model.channels.first?.id)
        let path = try touchTempPNG()
        let batchID = UUID()
        let record = makeRecord(path: path, batchID: batchID, seriesID: seriesID)
        model.records = [record]
        model.batches = [
            GenerationBatch(
                id: batchID, seriesID: seriesID, recordIDs: [record.id], selectedRecordID: record.id,
                prompt: "x", trigger: .manual, state: .ready, createdAt: Date(), errorMessage: nil
            )
        ]
        model.selectChannel(seriesID)
        XCTAssertFalse(model.activeCandidates.isEmpty)
        model.useOfflineDemo()

        model.startNewIdea()

        XCTAssertNil(model.selectedChannelID)
        XCTAssertNil(model.activeBatchID)
        XCTAssertNil(model.selectedCandidateID)
        XCTAssertTrue(model.activeCandidates.isEmpty)
        XCTAssertTrue(model.draft.input.isEmpty)
        XCTAssertTrue(model.creatingTaskFromComposer)
        XCTAssertTrue(model.shouldFocusComposer)
        XCTAssertEqual(model.generationBlockReason, "先在下面写下想看的画面，再点出图。")
        XCTAssertEqual(model.generateActionTitle, "先写下画面")
        XCTAssertTrue(model.creationStageDetail.contains("写下想看的画面"))
        XCTAssertTrue(model.creationStageDetail.contains("点出图"))
        XCTAssertTrue(model.creationStageDetail.contains("设为壁纸"))
    }

    func testLibrarySortOrderByCreatedAt() throws {
        let model = makeModel()
        let a = makeRecord(path: try touchTempPNG(), batchID: UUID(), createdAt: Date().addingTimeInterval(-100))
        let b = makeRecord(path: try touchTempPNG(), batchID: UUID(), createdAt: Date())
        model.records = [a, b]

        model.setLibrarySortOrder(.newestFirst)
        XCTAssertEqual(model.filteredArtworks.map(\.id), [b.id, a.id])

        model.setLibrarySortOrder(.oldestFirst)
        XCTAssertEqual(model.filteredArtworks.map(\.id), [a.id, b.id])
    }

    func testDesktopDeleteTrashesTheClickedScreenNotLastApplied() throws {
        let model = makeTwoScreenDesktopModel()
        let primary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        let secondary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        model.records = [primary, secondary]
        model.settings.lastAppliedArtworkID = primary.id
        model.settings.lastAppliedArtworkIDsByDisplay = [
            "screen-0": primary.id,
            "screen-1": secondary.id
        ]

        model.deleteCurrentDesktopWallpaper(displayID: "screen-1")

        XCTAssertNotNil(model.records.first { $0.id == secondary.id }?.trashedAt)
        XCTAssertNil(model.records.first { $0.id == primary.id }?.trashedAt)
        XCTAssertEqual(model.settings.lastAppliedArtworkIDsByDisplay?["screen-0"], primary.id)
        XCTAssertNil(model.settings.lastAppliedArtworkIDsByDisplay?["screen-1"])
    }

    func testDesktopDeleteUsesPlaylistCursorWhenSettingsMapMissing() throws {
        let model = makeTwoScreenDesktopModel()
        let primary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        let secondary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        let spare = makeRecord(path: try touchTempPNG(), batchID: UUID())
        model.records = [primary, secondary, spare]
        model.settings.lastAppliedArtworkID = primary.id
        model.settings.lastAppliedArtworkIDsByDisplay = nil
        model.playlists = [
            WallpaperPlaylist(
                name: "双屏",
                source: .all,
                order: .newest,
                enabled: true,
                lastArtworkID: primary.id,
                lastArtworkIDsByDisplay: [
                    "screen-0": primary.id,
                    "screen-1": secondary.id
                ]
            )
        ]

        model.deleteCurrentDesktopWallpaper(displayID: "screen-1")

        XCTAssertNotNil(model.records.first { $0.id == secondary.id }?.trashedAt)
        XCTAssertNil(model.records.first { $0.id == primary.id }?.trashedAt)
    }

    func testDesktopDeleteDoesNotTrashAnotherScreensWallpaper() throws {
        let model = makeTwoScreenDesktopModel()
        let primary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        model.records = [primary]
        model.settings.lastAppliedArtworkID = primary.id
        model.settings.lastAppliedArtworkIDsByDisplay = ["screen-0": primary.id]

        model.deleteCurrentDesktopWallpaper(displayID: "screen-1")

        XCTAssertNil(model.records.first { $0.id == primary.id }?.trashedAt)
        XCTAssertEqual(model.notice, "这块屏上还不是 Musepaper 作品，没法删除。")
    }

    func testDesktopLikeTargetsTheClickedScreen() throws {
        let model = makeTwoScreenDesktopModel()
        let primary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        let secondary = makeRecord(path: try touchTempPNG(), batchID: UUID())
        model.records = [primary, secondary]
        model.settings.lastAppliedArtworkID = primary.id
        model.settings.lastAppliedArtworkIDsByDisplay = [
            "screen-0": primary.id,
            "screen-1": secondary.id
        ]

        model.likeCurrentDesktopWallpaper(displayID: "screen-1")

        XCTAssertTrue(model.records.first { $0.id == secondary.id }?.isFavorite == true)
        XCTAssertFalse(model.records.first { $0.id == primary.id }?.isFavorite == true)
    }

    func testLowerPriorityPlaylistTimerDoesNotClaimOwnedScreens() throws {
        let model = makeTwoScreenDesktopModel()
        let primary = makeRecord(
            path: try touchTempPNG(),
            batchID: UUID(),
            createdAt: Date().addingTimeInterval(-30)
        )
        let secondary = makeRecord(path: try touchTempPNG(), batchID: UUID(), createdAt: Date())
        model.records = [primary, secondary]
        model.settings.lastAppliedArtworkID = primary.id
        model.settings.lastAppliedArtworkIDsByDisplay = ["screen-0": primary.id]
        let high = WallpaperPlaylist(
            name: "工作",
            source: .all,
            order: .newest,
            enabled: true,
            lastArtworkID: primary.id,
            lastArtworkIDsByDisplay: ["screen-0": primary.id],
            priority: 3
        )
        let low = WallpaperPlaylist(
            name: "随机",
            source: .all,
            order: .newest,
            enabled: true,
            lastArtworkID: primary.id,
            priority: 1
        )
        model.playlists = [low, high]

        model.playPlaylistNow(low.id, respectPriority: true)

        XCTAssertEqual(model.settings.lastAppliedArtworkID, primary.id)
        XCTAssertEqual(model.settings.lastAppliedArtworkIDsByDisplay?["screen-0"], primary.id)
        XCTAssertNil(model.playlists.first { $0.name == "随机" }?.lastArtworkIDsByDisplay?["screen-0"])
    }

    func testRaisePriorityLetsLowerTaskTakeTheScreen() throws {
        let model = makeTwoScreenDesktopModel()
        let low = WallpaperPlaylist(name: "随机", enabled: true, priority: 1)
        let high = WallpaperPlaylist(name: "工作", enabled: true, priority: 2)
        model.playlists = [low, high]

        XCTAssertEqual(model.playlistRank(high), 1)
        XCTAssertFalse(model.canRaisePlaylistPriority(high.id))
        model.movePlaylistPriority(low.id, higher: true)
        XCTAssertEqual(model.playlists.first { $0.name == "随机" }?.resolvedPriority, 2)
        XCTAssertEqual(model.playlistRank(low), 1)
    }

    private func makeTwoScreenDesktopModel() -> StudioViewModel {
        let model = makeModel()
        model.displayProbeOverride = [
            DisplayProbe(width: 3600, height: 2338, scale: 2),
            DisplayProbe(width: 1920, height: 1080, scale: 1)
        ]
        model.refreshDisplays()
        return model
    }

    private func makeModel() -> StudioViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return StudioViewModel(
            store: JSONStore(fileURL: root.appendingPathComponent("state.json")),
            credentialStore: CredentialStore(fileURL: root.appendingPathComponent("credentials.json"))
        )
    }

    private func touchTempPNG() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url.path
    }

    private func makeRecord(
        path: String,
        batchID: UUID,
        seriesID: UUID? = nil,
        createdAt: Date = Date()
    ) -> GenerationRecord {
        let request = GenerationRequest(
            id: UUID(), rawInput: "", resolvedPrompt: "test", negativePrompt: "",
            display: .preview, createdAt: createdAt, batchID: batchID, seriesID: seriesID
        )
        return GenerationRecord(id: request.id, request: request, state: .ready, imagePath: path, isFavorite: false, updatedAt: createdAt)
    }
}
