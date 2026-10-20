import AppKit
import Foundation
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

@MainActor
final class StudioViewModel: ObservableObject {
    @Published var draft = PromptDraft()
    @Published var finalPrompt = ""
    @Published var channels: [InspirationChannel] = [.sample]
    @Published var selectedChannelID: UUID?
    @Published var records: [GenerationRecord] = []
    @Published var batches: [GenerationBatch] = []
    @Published var smartCollections: [SmartCollection] = []
    @Published var playlists: [WallpaperPlaylist] = []
    @Published var activeCollectionID: UUID?
    @Published var libraryShowsTrash = false
    @Published var selectedLibraryTags: Set<String> = []
    @Published var isRetagging = false
    @Published var retagDone = 0
    @Published var retagTotal = 0
    @Published var activeBatchID: UUID?
    @Published var selectedCandidateID: UUID?
    @Published var batchSize = 4
    @Published var settings = AppSettings()
    @Published var selectedDisplay = DisplayProfile.preview
    @Published var displayProfiles: [DisplayProfile] = [.preview]
    @Published var isGenerating = false
    @Published var notice: String?
    @Published var showingChannelEditor = false
    @Published var modelConfigurations: [ModelConfiguration] = [ModelConfiguration(), .demo]
    @Published var activeModelConfigurationID: UUID?
    @Published var apiKeyDraft = ""
    @Published var apiKeyConfigured = false
    @Published var isTestingConnection = false
    @Published var connectionNotice: String?
    @Published var verifiedConfigurationID: UUID?
    @Published var verifiedImageRoute: ImageRoute?
    @Published var promptModelConfigurations: [PromptModelConfiguration] = [PromptModelConfiguration()]
    @Published var promptAgentRouting = PromptAgentRouting()
    @Published var promptAPIKeyDraft = ""
    @Published var promptModelsTextDraft = ""
    @Published var promptAPIKeyConfigured = false
    @Published var activePromptAPIKeyConfigured = false
    @Published var isOptimizingPrompt = false
    @Published var isTestingPromptModel = false
    @Published var promptAgentNotice: String?
    @Published var promptAgentVerified = false
    @Published var promptWasAIOptimized = false
    /// Last resolved text model name used by Agent (for notices / tag summaries).
    @Published var lastUsedPromptModelName: String?
    @Published var isExpandingSeries = false
    @Published var seriesNotice: String?
    @Published var channelBeingEdited: InspirationChannel?
    @Published var creatingTaskFromComposer = false
    @Published var shouldFocusComposer = false
    private var pendingNewSeriesID: UUID?
    private var persistSeriesTask: Task<Void, Never>?
    private var persistDebounceTask: Task<Void, Never>?
    private var persistGeneration = 0
    private var weatherCityDebounceTask: Task<Void, Never>?
    @Published var useReferenceImages = false
    @Published var generationIndex = 0
    @Published var generationTotal = 0
    @Published var diskWallpaperCount = 0
    @Published var diskRawCount = 0
    @Published var diskTotalFileCount = 0
    /// 最近一次更新检查结果（设置页 / 横幅 / 顶栏共用）。
    @Published var updateCheckResult: UpdateCheckResult?
    @Published var isCheckingUpdate = false
    /// 是否显示顶栏内联更新横幅。
    @Published var showsUpdateBanner = false

    var libraryCountCaption: String {
        if libraryShowsTrash {
            let count = trashedArtworks.count
            return count == 0 ? "回收箱是空的" : "回收箱 \(count) 张 · 可还原或永久删除"
        }
        let shown = filteredArtworks.count
        if diskTotalFileCount == 0 {
            return "\(shown) 张壁纸"
        }
        return "\(shown) 张壁纸 · 磁盘 \(diskTotalFileCount) 个文件（壁纸 \(diskWallpaperCount) + 原图 \(diskRawCount)）"
    }

    private let composer = PromptComposer()
    private let variationPlanner = VariationPlanner()
    private let artworkTagger = ArtworkTagger()
    private let displayService = DisplayService()
    private let wallpaper = WallpaperController()
    private let store: JSONStore
    private let credentials: CredentialStore
    private let providerFactory = ProviderFactory()
    private let scheduler = ScheduleService()
    private let playback = PlaybackService()
    private let menuBar = MenuBarController()
    private let desktopControls = DesktopControlOverlay()
    private let livingWallpaper = LivingWallpaperController(role: .desktop)
    private let desktopClock = DesktopClockOverlay()
    private let desktopWeather = DesktopWeatherOverlay()
    private let networkMonitor = NetworkMonitor()
    private let generationOutputDirectory: URL
    private var snapshot = AppSnapshot()
    /// Blocks writes until the first load finishes — prevents wiping a good
    /// on-disk library with in-memory defaults when decode fails.
    private var persistenceEnabled = false
    /// Only write model/prompt API blocks after they were loaded from disk or edited by the user.
    private var allowPersistingModelConfigurations = false
    private var generationTask: Task<Void, Never>?
    private var promptOptimizationTask: Task<Void, Never>?
    private var retagTask: Task<Void, Never>?
    private var lastDesktopControlAt: Date?
    private var pendingScheduledTaskIDs: [UUID] = []
    private var preparingBatchID: UUID?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    static let allDisplaysTargetID = "all-displays"
    var displayProbeOverride: [DisplayProbe]?

    init(
        store: JSONStore = JSONStore(), generationOutputDirectory: URL? = nil,
        credentialStore: CredentialStore? = nil
    ) {
        self.store = store
        self.credentials = credentialStore ?? CredentialStore()
        self.generationOutputDirectory = generationOutputDirectory
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Musepaper", isDirectory: true)
        activeModelConfigurationID = modelConfigurations.first?.id
        refreshDisplays()
        observeScreenChanges()
        refreshResolvedPrompt()
        Task { await load() }
    }

    deinit {
        let observer = screenObserver
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var selectedChannel: InspirationChannel? { channels.first { $0.id == selectedChannelID } }
    var activeBatch: GenerationBatch? { batches.first { $0.id == activeBatchID } }
    /// 创作页胶片：选中系列时展示该系列全部可用图（新→旧，倒序；新图插在最前）；
    /// 「新建」会话只展示当前批次（同为新→旧）。
    var activeCandidates: [GenerationRecord] {
        if let seriesID = selectedChannelID {
            return records
                .filter {
                    !$0.isTrashed
                        && $0.state != .failed
                        && $0.request.seriesID == seriesID
                        && $0.hasUsableImageFile
                }
                .sorted {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString > $1.id.uuidString
                }
        }
        guard let batch = activeBatch else { return [] }
        return batch.recordIDs.reversed().compactMap { id in
            records.first {
                $0.id == id && !$0.isTrashed && $0.state != .failed && $0.hasUsableImageFile
            }
        }
    }
    /// 本批已落盘张数（占位格用，避免系列历史图把「还在出」的空位算没）。
    var currentBatchReadyCount: Int {
        guard let batch = activeBatch else { return 0 }
        return batch.recordIDs.reduce(0) { partial, id in
            partial + (records.contains { $0.id == id && $0.hasUsableImageFile } ? 1 : 0)
        }
    }
    var selectedCandidate: GenerationRecord? {
        guard let id = selectedCandidateID else { return nil }
        return activeCandidates.first { $0.id == id }
    }
    var activeModelConfiguration: ModelConfiguration? {
        modelConfigurations.first { $0.id == activeModelConfigurationID }
    }
    var latestImageURL: URL? {
        selectedCandidate?.imagePath.map(URL.init(fileURLWithPath:))
    }
    var adoptedCandidateID: UUID? { activeBatch?.selectedRecordID }
    var isSelectedAdopted: Bool {
        guard let selected = selectedCandidateID else { return false }
        return selected == adoptedCandidateID
    }
    var canAdoptSelected: Bool { selectedCandidate?.hasUsableImageFile == true }
    var canApplySelected: Bool { selectedCandidate?.hasUsableImageFile == true }
    var canRegenerateSelected: Bool {
        selectedCandidate?.hasUsableImageFile == true && !isCreationBusy
    }
    var adoptActionTitle: String { "重新生成" }
    var adoptHint: String {
        if canApplySelected { return "可直接设为壁纸；「重新生成」会用这张的最终提示词重出并替换它。" }
        if isCreationBusy && activeCandidates.isEmpty { return "图还没出来。出来后点选一张即可设为壁纸。" }
        if activeCandidates.isEmpty { return "先出一组图，再点选一张。" }
        return "先点选一张图。"
    }
    var canGenerate: Bool { activeModelConfiguration?.provider == .demo || apiKeyConfigured }

    /// Honest top-bar status — Key on disk ≠ pathway verified.
    var connectionBadgeTitle: String {
        guard let config = activeModelConfiguration else { return "未配置" }
        if config.provider == .demo { return "离线演示" }
        if let route = verifiedImageRoute, route.matches(config) { return "已验证" }
        if apiKeyConfigured { return "Key 已存" }
        return "未配置"
    }

    var connectionBadgeIsReady: Bool {
        guard let config = activeModelConfiguration else { return false }
        if config.provider == .demo { return true }
        guard let route = verifiedImageRoute else { return false }
        return route.matches(config)
    }
    var isCreationBusy: Bool { isGenerating || isOptimizingPrompt }
    var shouldSurfaceCreationNotice: Bool {
        guard let notice, !notice.isEmpty, !isCreationBusy else { return false }
        return batches.first(where: { $0.id == activeBatchID })?.state == .failed
            || notice.contains("失败")
            || notice.contains("取消")
            || notice.contains("停止")
    }
    var hasActiveResults: Bool { isCreationBusy || !activeCandidates.isEmpty }
    var generationBlockReason: String? {
        if !canGenerate {
            return "还没连接图片模型。点「先用演示出图」可以立刻走完流程；真实出图去设置里填 API Key。"
        }
        let hasInput = !draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isBlankSeriesSession && !hasInput {
            return "先在下面写下想看的画面，再点出图。"
        }
        return nil
    }
    var generateActionTitle: String {
        if !canGenerate { return "先用演示出图" }
        if isBlankSeriesSession && draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "先写下画面"
        }
        if !displayedReferencePaths.isEmpty { return "再出 \(batchSize) 张" }
        return "出 \(batchSize) 张图"
    }
    var stopActionTitle: String {
        if isOptimizingPrompt { return "停止构思" }
        if generationTotal > 0 { return "停止出图 \(generationIndex)/\(generationTotal)" }
        return "停止出图"
    }
    var continueActionTitle: String {
        selectedCandidate == nil ? "再出一组" : "按这张再出一组"
    }
    var creationStageTitle: String {
        if isOptimizingPrompt { return "正在想画面" }
        if isGenerating { return generationTotal > 0 ? "正在出图 \(generationIndex)/\(generationTotal)" : "正在出图" }
        if !activeCandidates.isEmpty { return "选出一张" }
        if isBlankSeriesSession { return "新系列" }
        return "壁纸会出现在这里"
    }
    var creationStageDetail: String {
        if isOptimizingPrompt { return "先写构图。现在的桌面不会被换掉。" }
        if isGenerating { return "图会一张张出来。你没点「设为壁纸」之前，桌面不变。" }
        if !activeCandidates.isEmpty {
            return "点小图或大图两侧箭头切换；←→ 键也可。再点「设为壁纸」。双击大图也可设壁纸。"
        }
        if isBlankSeriesSession {
            return "1. 在下面写下想看的画面，例如：温暖的春天的悠闲午后\n2. 点出图\n3. 喜欢的再点设为壁纸。桌面不会自己换。"
        }
        return "点左边系列继续出，或点「新系列」另写一句。桌面不会自己换。"
    }

    var isBlankSeriesSession: Bool {
        selectedChannelID == nil || creatingTaskFromComposer
    }
    var displayedReferencePaths: [String] {
        guard useReferenceImages else { return [] }
        return existingImagePaths(draft.referenceImagePaths ?? defaultSeriesReferences(for: selectedChannelID))
    }
    var suggestedReferencePaths: [String] {
        existingImagePaths(
            defaultSeriesReferences(for: selectedChannelID) + [selectedCandidate?.imagePath].compactMap { $0 }
        )
    }
    var showsReferenceStrip: Bool {
        !displayedReferencePaths.isEmpty || !suggestedReferencePaths.isEmpty
    }
    var referencePickerArtworks: [GenerationRecord] {
        let available = usableArtworks
        let taskOnes = available.filter { $0.request.seriesID == selectedChannelID }
        let rest = available.filter { $0.request.seriesID != selectedChannelID }
        return taskOnes + rest
    }
    var composerSupportText: String {
        if isCreationBusy { return "可以按停止，已完成的图会留下来" }
        if !canGenerate { return "未连接模型，这次用离线演示" }
        if promptAgentRouting.enabled && promptAPIKeyConfigured { return "每张都会单独写成不同画面再出图" }
        return "每张先按内置纯场景改写，互不相同"
    }
    var modelStatusTitle: String {
        guard let config = activeModelConfiguration else { return "未选择文生图模型" }
        if config.provider == .demo { return "离线演示已就绪" }
        if !apiKeyConfigured { return "需要配置 API Key" }
        if let route = verifiedImageRoute, route.matches(config) { return "出图通路已验证" }
        return "API Key 已保存，尚未验证（点「保存并测试」）"
    }
    var modelStatusDetail: String {
        guard let config = activeModelConfiguration else { return "进入模型与自动化，添加一个 Provider。" }
        return "\(config.name) · \(config.model) · \(config.size.rawValue) · \(config.quality.rawValue)"
    }
    var imageModelCaption: String {
        if let route = verifiedImageRoute {
            return "出图通路：\(route.model) → \(route.host)/images/generations"
        }
        guard let config = activeModelConfiguration else { return "还没选图片模型" }
        if config.provider == .demo { return "离线演示" }
        return "出图通路未锁定：\(config.model)（先保存并测试）"
    }

    var textModelCaption: String {
        guard promptAgentRouting.enabled else { return "文本通路：关着，用内置构图" }
        switch promptAgentRouting.mode {
        case .fixed:
            guard let ref = promptAgentRouting.activeRef,
                  let config = promptModelConfigurations.first(where: { $0.id == ref.configurationID }) else {
                return "文本通路：未选模型"
            }
            let host = URL(string: config.baseURL)?.host ?? config.baseURL
            return "文本通路：\(config.selectionLabel(forModel: ref.model)) → \(host)/\(config.endpointPath)"
        case .random:
            let count = promptAgentRouting.eligibleRefs.count
            return "文本通路：随机（\(count) 个候选）"
        }
    }

    var activePromptModelConfiguration: PromptModelConfiguration? {
        if let id = promptAgentRouting.activeRef?.configurationID,
           let match = promptModelConfigurations.first(where: { $0.id == id }) {
            return match
        }
        return promptModelConfigurations.first
    }

    /// Flattened Agent choices as `厂商:模型`.
    var promptAgentSelectionOptions: [(ref: PromptAgentModelRef, label: String)] {
        promptModelConfigurations.flatMap { config in
            config.agentModelRefs.map { ref in
                (ref, config.selectionLabel(forModel: ref.model))
            }
        }
    }

    var pathwayMismatchReason: String? {
        guard let config = activeModelConfiguration, config.provider != .demo else { return nil }
        guard let route = verifiedImageRoute else { return nil }
        if route.matches(config) { return nil }
        return "出图通路没对齐。测过的是 \(route.model) @ \(route.host)，现在要用的是 \(config.model) @ \(ImageRoute.from(config).host)。请再点一次文生图的「保存并测试」。"
    }

    var generationEndpointPreview: String {
        guard let config = activeModelConfiguration, config.provider != .demo else { return "本地生成，不发送网络请求" }
        return config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/images/generations"
    }
    var promptEndpointPreview: String {
        guard let config = activePromptModelConfiguration else { return "" }
        return config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + config.endpointPath
    }
    var canOptimizePrompt: Bool {
        promptAgentRouting.enabled && promptAPIKeyConfigured &&
            (!draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedChannel != nil)
    }
    var allArtworkTags: [String] {
        let counts = Dictionary(grouping: records.flatMap(\.resolvedTags), by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    func artworkCount(for collection: SmartCollection) -> Int {
        usableArtworks.reduce(0) { $0 + (collection.includes($1) ? 1 : 0) }
    }
    var usableArtworks: [GenerationRecord] {
        records.filter { !$0.isTrashed && $0.state != .failed && $0.hasUsableImageFile }
    }

    var trashedArtworks: [GenerationRecord] {
        records
            .filter { $0.isTrashed && $0.hasUsableImageFile }
            .sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
    }

    var librarySortOrder: LibrarySortOrder {
        settings.librarySortOrder ?? .newestFirst
    }

    var filteredArtworks: [GenerationRecord] {
        if libraryShowsTrash { return trashedArtworks }
        var values = usableArtworks
        if let id = activeCollectionID, let collection = smartCollections.first(where: { $0.id == id }) {
            values = values.filter { collection.includes($0) }
        }
        if !selectedLibraryTags.isEmpty {
            values = values.filter { selectedLibraryTags.isSubset(of: Set($0.resolvedTags)) }
        }
        switch librarySortOrder {
        case .newestFirst:
            return values.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString > $1.id.uuidString
            }
        case .oldestFirst:
            return values.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    func setLibrarySortOrder(_ order: LibrarySortOrder) {
        var next = settings
        next.librarySortOrder = order
        settings = next
        persist()
    }

    func showLibraryTrash(_ on: Bool) {
        libraryShowsTrash = on
        if on { activeCollectionID = nil }
    }

    static func artworkTimeCaption(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    var wallpaperTargetID: String {
        settings.applyToAllDisplays ? Self.allDisplaysTargetID : selectedDisplay.id
    }

    var wallpaperApplyIntent: WallpaperApplyIntent {
        WallpaperApplyIntent(targetDisplayID: selectedDisplay.id, allDisplays: settings.applyToAllDisplays)
    }

    func wallpaperTargetLabel(for display: DisplayProfile) -> String {
        "只贴到：\(display.name) · \(display.width)×\(display.height)"
    }

    func refreshDisplays() {
        let detected = displayProbeOverride.map { DisplayService.profiles(from: $0) } ?? displayService.profiles()
        guard !detected.isEmpty else { return }
        displayProfiles = detected
        if let saved = settings.selectedDisplayID, let match = detected.first(where: { $0.id == saved }) {
            selectedDisplay = match
        } else if let match = detected.first(where: { $0.id == selectedDisplay.id }) {
            selectedDisplay = match
            settings.selectedDisplayID = match.id
        } else {
            selectedDisplay = detected[0]
            settings.selectedDisplayID = detected[0].id
        }
    }

    func selectWallpaperTarget(_ id: String) {
        refreshDisplays()
        if id == Self.allDisplaysTargetID {
            settings.applyToAllDisplays = true
        } else if let display = displayProfiles.first(where: { $0.id == id }) {
            settings.applyToAllDisplays = false
            selectedDisplay = display
            settings.selectedDisplayID = display.id
        }
        persist()
    }

    func refreshResolvedPrompt(seed: Int? = nil) {
        do {
            let next = try composer.resolve(draft: draft, channel: selectedChannel, display: selectedDisplay, seed: seed)
            if finalPrompt != next { finalPrompt = next }
            promptWasAIOptimized = false
        } catch {
            if !finalPrompt.isEmpty { finalPrompt = "" }
        }
    }

    func optimizePromptWithAI() {
        guard !isOptimizingPrompt else { return }
        guard promptAgentRouting.enabled else {
            promptAgentNotice = "先在“模型与自动化”启用 Prompt Agent。"
            return
        }
        isOptimizingPrompt = true
        promptAgentNotice = "正在由文本模型重构画面语言…"
        let context = promptEnhancementContext()
        promptOptimizationTask = Task {
            do {
                guard let agent = await makePromptAgentIfAvailable() else {
                    throw MusepaperError.missingAPIKey
                }
                let modelName = lastUsedPromptModelName ?? agent.configuration.model
                promptAgentNotice = "正在由 \(modelName) 重构画面语言…"
                let core = context.coreKeywords.isEmpty ? context.rawPrompt : context.coreKeywords
                finalPrompt = try await agent.enhance(context)
                let englishCore = composer.spokenHint(core)
                promptWasAIOptimized = !composer.containsInstructionLeak(finalPrompt)
                    && (composer.preservesCore(core, in: finalPrompt)
                        || composer.preservesCore(englishCore, in: finalPrompt)
                        || (!composer.containsCJK(finalPrompt) && finalPrompt.count >= 12))
                promptAgentNotice = promptWasAIOptimized
                    ? "已写成能看见的画面（\(modelName)）。出图时按这段走。"
                    : "已写出画面，请看一眼是否还是你要的主题。"
            } catch { promptAgentNotice = error.localizedDescription }
            isOptimizingPrompt = false
            promptOptimizationTask = nil
        }
    }

    func cancelPromptOptimization() {
        promptOptimizationTask?.cancel()
        promptOptimizationTask = nil
        isOptimizingPrompt = false
        promptAgentNotice = "已取消 Prompt 优化。"
        if let id = preparingBatchID { abandonPreparingBatch(id) }
    }

    func selectPromptModelConfiguration(_ id: UUID) {
        if activePromptModelConfiguration?.id != id {
            commitPromptModelsTextDraft()
        }
        guard let config = promptModelConfigurations.first(where: { $0.id == id }) else { return }
        let modelName = config.resolvedModels.first ?? ""
        let ref = PromptAgentModelRef(configurationID: id, model: modelName)
        promptAgentRouting.activeRef = ref
        if promptAgentRouting.mode == .fixed, !promptAgentRouting.eligibleRefs.contains(ref) {
            promptAgentRouting.eligibleRefs.append(ref)
        }
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        promptAPIKeyDraft = ""
        syncPromptModelsTextDraft()
        promptAgentVerified = false
        persist()
        Task { await refreshPromptKeyStatus() }
    }

    func selectPromptAgentRef(_ ref: PromptAgentModelRef) {
        if activePromptModelConfiguration?.id != ref.configurationID {
            commitPromptModelsTextDraft()
        }
        promptAgentRouting.activeRef = ref
        if promptAgentRouting.mode == .fixed, !promptAgentRouting.eligibleRefs.contains(ref) {
            promptAgentRouting.eligibleRefs.append(ref)
        }
        // Keep settings editor on that vendor.
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        promptAPIKeyDraft = ""
        syncPromptModelsTextDraft()
        promptAgentVerified = false
        persist()
        Task { await refreshPromptKeyStatus() }
    }

    func updateActivePromptModelConfiguration(_ configuration: PromptModelConfiguration) {
        guard let index = promptModelConfigurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        promptModelConfigurations[index] = configuration
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        promptAgentVerified = false
        allowPersistingModelConfigurations = true
    }

    func addPromptModelConfiguration() {
        let base = activePromptModelConfiguration
        var config = PromptModelConfiguration(
            name: PromptModelConfiguration.inferredVendorName(for: base?.baseURL ?? "https://api.openai.com/v1"),
            baseURL: base?.baseURL ?? "https://api.openai.com/v1",
            models: ["new-model"],
            apiFormat: base?.apiFormat ?? .responses
        )
        config.enabled = false
        promptModelConfigurations.append(config)
        selectPromptModelConfiguration(config.id)
        allowPersistingModelConfigurations = true
        persist()
        promptAgentNotice = "已新增厂商连接。在模型列表里填多个模型名，共用一把 AK。"
    }

    func setActivePromptModelsFromMultilineText(_ text: String) {
        guard var current = activePromptModelConfiguration else { return }
        let oldModels = current.resolvedModels
        let parsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let next = PromptModelConfiguration.normalizedModelList(parsed)
        guard !next.isEmpty else {
            promptAgentNotice = "至少保留一个模型名。"
            syncPromptModelsTextDraft()
            return
        }
        guard next != oldModels else {
            promptModelsTextDraft = next.joined(separator: "\n")
            return
        }
        current.models = next
        updateActivePromptModelConfiguration(current)

        let oldSet = Set(oldModels)
        let newSet = Set(next)
        promptAgentRouting.eligibleRefs = promptAgentRouting.eligibleRefs.compactMap { ref in
            guard ref.configurationID == current.id else { return ref }
            return newSet.contains(ref.model) ? ref : nil
        }
        for name in next where !oldSet.contains(name) {
            let ref = PromptAgentModelRef(configurationID: current.id, model: name)
            if !promptAgentRouting.eligibleRefs.contains(ref) {
                promptAgentRouting.eligibleRefs.append(ref)
            }
        }
        if let active = promptAgentRouting.activeRef,
           active.configurationID == current.id,
           !newSet.contains(active.model) {
            promptAgentRouting.activeRef = current.agentModelRefs.first
        }
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        promptModelsTextDraft = next.joined(separator: "\n")
        persist()
    }

    func syncPromptModelsTextDraft() {
        promptModelsTextDraft = (activePromptModelConfiguration?.resolvedModels ?? []).joined(separator: "\n")
    }

    func commitPromptModelsTextDraft() {
        setActivePromptModelsFromMultilineText(promptModelsTextDraft)
    }

    func deleteActivePromptModelConfiguration() {
        guard let id = activePromptModelConfiguration?.id else { return }
        guard promptModelConfigurations.count > 1 else {
            promptAgentNotice = "至少保留一个厂商连接。"
            return
        }
        promptModelConfigurations.removeAll { $0.id == id }
        promptAgentRouting.eligibleRefs.removeAll { $0.configurationID == id }
        if promptAgentRouting.activeRef?.configurationID == id {
            promptAgentRouting.activeRef = nil
        }
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        promptAPIKeyDraft = ""
        syncPromptModelsTextDraft()
        promptAgentVerified = false
        allowPersistingModelConfigurations = true
        persist()
        Task { await refreshPromptKeyStatus() }
    }

    func setPromptAgentMode(_ mode: PromptAgentModelMode) {
        promptAgentRouting.mode = mode
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        persist()
    }

    func setPromptModelEligible(_ ref: PromptAgentModelRef, eligible: Bool) {
        if eligible {
            if !promptAgentRouting.eligibleRefs.contains(ref) {
                promptAgentRouting.eligibleRefs.append(ref)
            }
        } else {
            promptAgentRouting.eligibleRefs.removeAll { $0 == ref }
            if promptAgentRouting.activeRef == ref {
                promptAgentRouting.activeRef = promptAgentRouting.eligibleRefs.first
                    ?? promptModelConfigurations.flatMap(\.agentModelRefs).first
            }
        }
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        persist()
        Task { await refreshPromptKeyStatus() }
    }

    func savePromptModelConfiguration() {
        commitPromptModelsTextDraft()
        guard var current = activePromptModelConfiguration else { return }
        do { current = try current.validated() }
        catch { promptAgentNotice = error.localizedDescription; return }
        updateActivePromptModelConfiguration(current)
        allowPersistingModelConfigurations = true
        promptAgentVerified = false
        Task {
            do {
                let transient = promptAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transient.isEmpty {
                    try await savePromptAPIKey(transient, for: current)
                    promptAPIKeyDraft = ""
                }
                await refreshPromptKeyStatus()
                persist()
                let shared = promptConfigsSharingCredential(with: current).count
                promptAgentNotice = shared > 1
                    ? "文本模型已保存；同一 Base URL 下 \(shared) 个模型共用这把 AK。"
                    : "文本模型已保存；AK 位于本机私有凭据文件。"
            } catch { promptAgentNotice = error.localizedDescription }
        }
    }

    func saveAndTestPromptModel() {
        commitPromptModelsTextDraft()
        guard var current = activePromptModelConfiguration else { return }
        do { current = try current.validated() }
        catch { promptAgentNotice = error.localizedDescription; return }
        updateActivePromptModelConfiguration(current)
        isTestingPromptModel = true
        promptAgentNotice = "正在保存并测试 \(current.model)…"
        allowPersistingModelConfigurations = true
        Task {
            do {
                let transient = promptAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !transient.isEmpty {
                    try await savePromptAPIKey(transient, for: current)
                    promptAPIKeyDraft = ""
                }
                guard let key = try await readPromptAPIKey(for: current), !key.isEmpty else {
                    throw MusepaperError.missingAPIKey
                }
                let agent = try PromptAgent(configuration: current, apiKey: key)
                try await agent.testConnection()
                await refreshPromptKeyStatus()
                promptAgentVerified = true
                persist()
                promptAgentNotice = "连接成功：\(current.model) 可以优化 Prompt（\(current.apiFormat.rawValue)）。"
            } catch {
                promptAgentVerified = false
                promptAgentNotice = error.localizedDescription
            }
            isTestingPromptModel = false
        }
    }

    func reuseImageAPIKeyForPromptModel() {
        guard let imageID = activeModelConfigurationID,
              let current = activePromptModelConfiguration else { return }
        Task {
            do {
                guard let key = try await credentials.read(for: imageID), !key.isEmpty else {
                    throw MusepaperError.missingAPIKey
                }
                try await savePromptAPIKey(key, for: current)
                await refreshPromptKeyStatus()
                persist()
                let shared = promptConfigsSharingCredential(with: current).count
                promptAgentNotice = shared > 1
                    ? "已复用图片 Provider 的 Key，并同步到同 Base URL 的 \(shared) 个文本模型。"
                    : "已安全复用当前图片 Provider 的 Key。"
            } catch { promptAgentNotice = error.localizedDescription }
        }
    }

    func removePromptAPIKey() {
        guard let current = activePromptModelConfiguration else { return }
        Task {
            do {
                try await deletePromptAPIKey(for: current)
                promptAPIKeyDraft = ""
                await refreshPromptKeyStatus()
                let shared = promptConfigsSharingCredential(with: current).count
                promptAgentNotice = shared > 1
                    ? "已删除同 Base URL 下 \(shared) 个文本模型共用的 AK。"
                    : "文本模型 AK 已从本机凭据删除。"
            } catch { promptAgentNotice = error.localizedDescription }
        }
    }

    func selectChannel(_ id: UUID?) {
        if selectedChannelID != id { rememberPromptOnSelectedSeries() }
        if id != nil { creatingTaskFromComposer = false }
        selectedChannelID = id
        draft.mode = id == nil ? .direct : .inspiration
        settings.selectedChannelID = id
        if let channel = selectedChannel {
            batchSize = channel.resolvedCandidateCount
            draft.referenceImagePaths = nil
            let shown = restoredSeriesPrompt(channel)
            if !shown.isEmpty { draft.input = shown }
            syncCreationFocusToSeries(channel.id)
        }
        refreshResolvedPrompt()
        persist()
        refreshMenuBar()
    }

    /// 打开系列：胶片切到该系列全部图，预览落在最新一张（或保留仍属于该系列的当前选中）。
    private func syncCreationFocusToSeries(_ seriesID: UUID) {
        if let latestBatch = batches.first(where: { $0.seriesID == seriesID }) {
            activeBatchID = latestBatch.id
        }
        let seriesImages = activeCandidates
        if let selected = selectedCandidateID,
           seriesImages.contains(where: { $0.id == selected }) {
            return
        }
        selectedCandidateID = seriesImages.first?.id
    }

    func setBatchSize(_ count: Int) {
        let next = InspirationChannel.clampedCount(count)
        batchSize = next
        if let id = selectedChannelID, let index = channels.firstIndex(where: { $0.id == id }) {
            channels[index].defaultCandidateCount = next
            persist()
        }
    }

    func setActiveImageSize(_ size: GeneratedImageSize) {
        guard var config = activeModelConfiguration else { return }
        config.size = size
        updateActiveModelConfiguration(config)
    }

    func setActiveImageQuality(_ quality: ImageQuality) {
        guard var config = activeModelConfiguration else { return }
        config.quality = quality
        updateActiveModelConfiguration(config)
    }

    func setPromptAgentEnabled(_ enabled: Bool) {
        promptAgentRouting.enabled = enabled
        if enabled {
            promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        }
        allowPersistingModelConfigurations = true
        promptAgentVerified = false
        persist()
    }

    func draftInputDidChange() {
        adoptComposerAsNewSeriesIfNeeded()
        rememberPromptOnSelectedSeries()
        persistSeriesSoon()
    }

    func rememberPromptOnSelectedSeries() {
        guard let id = selectedChannelID, let index = channels.firstIndex(where: { $0.id == id }) else { return }
        let idea = draft.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty, !composer.containsInstructionLeak(idea) else { return }
        var channel = channels[index]
        let locked = channel.resolvedCoreKeywords
        guard composer.shouldAdoptTypedIdeaAsSeriesCore(locked: locked, idea: idea) else { return }
        channel.essence = idea
        channel.coreKeywords = idea
        if shouldAutofillSeriesName(channel, idea: idea, locked: locked) {
            channel.name = InspirationChannel.title(from: idea)
        }
        channels[index] = channel
    }

    func renameChannel(_ id: UUID, to name: String) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        channels[index].name = trimmed
        persist()
    }

    func seriesArtworkCount(_ channel: InspirationChannel) -> Int {
        records.filter {
            !$0.isTrashed && $0.hasUsableImageFile && $0.request.seriesID == channel.id
        }.count
    }

    /// Auto-name only when the title is still empty, a placeholder, or the last auto title.
    private func shouldAutofillSeriesName(_ channel: InspirationChannel, idea: String, locked: String) -> Bool {
        let current = channel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || composer.isSchemaPlaceholder(current) { return true }
        let autoTitles = [
            InspirationChannel.title(from: locked),
            InspirationChannel.title(from: channel.essence)
        ]
        return autoTitles.contains(current)
    }

    private func restoredSeriesPrompt(_ channel: InspirationChannel) -> String {
        let healed = healedSeries(channel)
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = healed
        }
        let essence = healed.essence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !essence.isEmpty, !composer.isSchemaPlaceholder(essence), !composer.containsInstructionLeak(essence) {
            return essence
        }
        return healed.lockedCore
    }

    private func healedSeries(_ channel: InspirationChannel) -> InspirationChannel {
        var copy = channel
        let essence = copy.essence.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.resolvedCoreKeywords.isEmpty || composer.isSchemaPlaceholder(copy.resolvedCoreKeywords) {
            if let visual = composer.usableVisual(essence) {
                copy.coreKeywords = visual
            }
        }
        let core = copy.lockedCore
        if !core.isEmpty,
           composer.containsInstructionLeak(essence)
            || essence.count > max(core.count + 80, 160)
            || !composer.shouldAdoptTypedIdeaAsSeriesCore(locked: core, idea: essence) {
            copy.essence = core
        }
        return copy
    }

    private func adoptComposerAsNewSeriesIfNeeded() {
        guard creatingTaskFromComposer else { return }
        let idea = draft.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { return }
        let id = pendingNewSeriesID ?? UUID()
        pendingNewSeriesID = nil
        creatingTaskFromComposer = false
        let channel = InspirationChannel(id: id, name: "", essence: idea, coreKeywords: "")
            .completingMissingFields(idea: idea)
        if let index = channels.firstIndex(where: { $0.id == id }) {
            channels[index] = channel
        } else {
            channels.append(channel)
        }
        selectedChannelID = id
        settings.selectedChannelID = id
        draft.mode = .inspiration
        configureAutomations()
    }

    private func persistSeriesSoon() {
        persistSeriesTask?.cancel()
        persistSeriesTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persist()
            refreshMenuBar()
        }
    }

    func addChannel(_ channel: InspirationChannel, generateNow: Bool = false) {
        let ready = channel.completingMissingFields(idea: channel.essence)
        if let index = channels.firstIndex(where: { $0.id == ready.id }) { channels[index] = ready }
        else { channels.append(ready) }
        channelBeingEdited = nil
        selectChannel(ready.id)
        configureAutomations()
        if generateNow { designAndGenerate() }
    }

    func setTaskSchedule(_ id: UUID, enabled: Bool? = nil, hour: Int? = nil, count: Int? = nil, intervalHours: Int? = nil, intervalSeconds: Int? = nil) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        if let enabled {
            channels[index].scheduleEnabled = enabled
            if enabled, channels[index].scheduleIntervalSeconds == nil, channels[index].scheduleIntervalHours == nil {
                channels[index].scheduleIntervalSeconds = InspirationChannel.defaultIntervalSeconds
            }
            if enabled { syncSeriesTimeline(id) }
        }
        if let hour { channels[index].scheduleHour = min(max(hour, 0), 23) }
        if let count { channels[index].scheduledCandidateCount = InspirationChannel.clampedCount(count) }
        if let intervalSeconds {
            channels[index].scheduleIntervalSeconds = InspirationChannel.clampedIntervalSeconds(intervalSeconds)
        } else if let intervalHours {
            channels[index].scheduleIntervalSeconds = InspirationChannel.clampedIntervalSeconds(intervalHours * 3600)
        }
        persist()
        configureAutomations()
    }

    func scheduleSummary(for channel: InspirationChannel) -> String {
        if channel.resolvedScheduleEnabled {
            let last = effectiveLastProducedAt(for: channel)
            let next = ScheduleService.nextFireCaption(
                intervalSeconds: channel.resolvedScheduleIntervalSeconds, lastProducedAt: last
            )
            return "下次 \(next)"
        }
        return "打开后按间隔自动出图，只进作品库。"
    }

    func scheduleBadge(for channel: InspirationChannel) -> String {
        channel.resolvedScheduleEnabled ? "自动" : "定时"
    }

    func useOfflineDemo() {
        guard let demo = modelConfigurations.first(where: { $0.provider == .demo }) else { return }
        selectModelConfiguration(demo.id)
        notice = "已切换到离线演示。这次不花额度，用来走完生成和选图。"
    }

    func requestGeneration() {
        guard !isCreationBusy else { return }
        if !canGenerate { useOfflineDemo() }
        draftInputDidChange()
        if creatingTaskFromComposer, draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notice = "先在下面写下想看的画面，再点出图。"
            shouldFocusComposer = true
            return
        }
        designAndGenerate()
    }

    /// One blank-series path: clear the bench, wait for a sentence, then the first generate owns a series.
    func startNewIdea() {
        startBlankSeries()
    }

    func beginNewSeries() {
        startBlankSeries()
    }

    func startBlankSeries() {
        rememberPromptOnSelectedSeries()
        channelBeingEdited = nil
        showingChannelEditor = false
        pendingNewSeriesID = UUID()
        creatingTaskFromComposer = true
        selectedChannelID = nil
        settings.selectedChannelID = nil
        draft.input = ""
        draft.referenceImagePaths = nil
        useReferenceImages = false
        draft.mode = .direct
        activeBatchID = nil
        selectedCandidateID = nil
        notice = nil
        shouldFocusComposer = true
        refreshResolvedPrompt()
        persist()
        refreshMenuBar()
    }

    func beginEditingSeries(_ channel: InspirationChannel) {
        showingChannelEditor = false
        channelBeingEdited = nil
        selectChannel(channel.id)
        notice = "灵感词就在上面输入框，改了会自动记住。"
    }

    func expandSeriesBlueprint(_ idea: String) async throws -> WallpaperBlueprintSuggestion {
        guard promptAgentRouting.enabled else {
            throw MusepaperError.invalidConfiguration("请先启用 Prompt Agent")
        }
        isExpandingSeries = true
        defer { isExpandingSeries = false }
        guard let agent = await makePromptAgentIfAvailable() else {
            throw MusepaperError.missingAPIKey
        }
        let suggestion = try await agent.expandBlueprint(idea: idea)
        let modelName = lastUsedPromptModelName ?? agent.configuration.model
        seriesNotice = "AI 已拆解不可变内核与可变维度（\(modelName)）。"
        return suggestion
    }

    func selectCandidate(_ id: UUID) {
        guard activeCandidates.contains(where: { $0.id == id }) else { return }
        selectedCandidateID = id
    }

    var selectedCandidateIndex: Int? {
        guard let id = selectedCandidateID else { return nil }
        return activeCandidates.firstIndex(where: { $0.id == id })
    }

    var canSelectPreviousCandidate: Bool {
        guard let index = selectedCandidateIndex else { return !activeCandidates.isEmpty }
        return index > 0
    }

    var canSelectNextCandidate: Bool {
        guard let index = selectedCandidateIndex else { return !activeCandidates.isEmpty }
        return index + 1 < activeCandidates.count
    }

    /// step < 0 往更新（左），step > 0 往更早（右）。胶片为新→旧倒序。
    func selectAdjacentCandidate(_ step: Int) {
        let list = activeCandidates
        guard !list.isEmpty, step != 0 else { return }
        if let index = selectedCandidateIndex {
            let next = min(max(index + step, 0), list.count - 1)
            selectedCandidateID = list[next].id
        } else {
            selectedCandidateID = step < 0 ? list.first?.id : list.last?.id
        }
    }

    func selectFirstCandidate() {
        selectedCandidateID = activeCandidates.first?.id
    }

    func selectLastCandidate() {
        selectedCandidateID = activeCandidates.last?.id
    }

    var candidatePositionCaption: String {
        let total = activeCandidates.count
        guard total > 0 else { return "" }
        let current = (selectedCandidateIndex ?? -1) + 1
        return "\(max(current, 1)) / \(total)"
    }

    func adoptSelectedCandidate() {
        // Legacy entry: now regenerates the selected candidate in place.
        regenerateSelectedCandidate()
    }

    /// Re-run the selected candidate's final image prompt and replace that slot.
    func regenerateSelectedCandidate() {
        guard !isCreationBusy else { return }
        guard let record = selectedCandidate else {
            notice = "请先点选一张要重出的图。"
            return
        }
        let recordID = record.id
        let finalImagePrompt = record.request.resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalImagePrompt.isEmpty else {
            notice = "这张图没有可用的最终提示词。"
            return
        }
        let oldPath = record.imagePath
        var request = record.request
        request.id = UUID()
        request.resolvedPrompt = finalImagePrompt
        request.createdAt = Date()
        request.variationSeed = (record.request.variationSeed ?? Int.random(in: 1...1_000_000)) &+ 17

        isGenerating = true
        generationTotal = 1
        generationIndex = 0
        notice = "正在用最终提示词重新生成…"
        generationTask = Task {
            defer {
                isGenerating = false
                generationTotal = 0
                generationIndex = 0
                generationTask = nil
            }
            do {
                guard var config = activeModelConfiguration else {
                    throw MusepaperError.invalidConfiguration("没有活动模型配置")
                }
                if let route = verifiedImageRoute {
                    config.baseURL = route.baseURL
                    config.model = route.model
                    config.provider = route.provider
                }
                config.imageCount = 1
                let key = try await credentials.read(for: config.id)
                let provider = try providerFactory.make(configuration: config, apiKey: key)
                let pipeline = GenerationPipeline(provider: provider)
                generationIndex = 1
                let urls = try await pipeline.run(request, outputDirectory: generationOutputDirectory)
                guard let url = urls.first else { throw MusepaperError.missingImage }
                guard let index = records.firstIndex(where: { $0.id == recordID }) else {
                    notice = "原图已不在列表里，重出结果未替换。"
                    return
                }
                records[index].request.resolvedPrompt = finalImagePrompt
                records[index].request.variationSeed = request.variationSeed
                records[index].request.display = request.display
                records[index].imagePath = url.path
                records[index].state = .ready
                records[index].errorMessage = nil
                records[index].updatedAt = Date()
                records[index].tags = artworkTagger.fallbackTags(
                    prompt: finalImagePrompt,
                    task: records[index].request.seriesID.flatMap { id in channels.first { $0.id == id } }
                )
                ArtworkPromptSidecar.write(
                    finalPrompt: finalImagePrompt,
                    rawInput: records[index].request.rawInput,
                    negativePrompt: records[index].request.negativePrompt,
                    coreKeywords: records[index].request.coreKeywords ?? artworkCoreKeywords(records[index]),
                    nextTo: url
                )
                if let batchIndex = batches.firstIndex(where: { $0.id == activeBatchID }) {
                    batches[batchIndex].selectedRecordID = recordID
                }
                selectedCandidateID = recordID
                if let oldPath, oldPath != url.path {
                    _ = deleteArtworkFilesOnDisk(relatedTo: oldPath)
                }
                WallpaperImageCache.shared.evict(path: url.path)
                persist()
                refreshDiskLibraryStats()
                refreshDesktopControls()
                notice = "已用最终提示词重出，并替换了这张图。"
            } catch is CancellationError {
                notice = "已取消重新生成。"
            } catch {
                notice = "重新生成失败：\(error.localizedDescription)"
            }
        }
    }

    func activateBatch(_ id: UUID) {
        guard let batch = batches.first(where: { $0.id == id }) else { return }
        activeBatchID = id
        selectedCandidateID = batch.selectedRecordID ?? batch.recordIDs.first
        persist()
    }

    func chooseReferenceFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        guard panel.runModal() == .OK else { return }
        var current = displayedReferencePaths
        current.append(contentsOf: panel.urls.map(\.path))
        useReferenceImages = true
        draft.referenceImagePaths = Array(existingImagePaths(current).prefix(4))
        refreshResolvedPrompt()
    }

    func toggleReference(path: String) {
        var current = displayedReferencePaths
        if current.contains(path) {
            current.removeAll { $0 == path }
        } else if current.count < 4 {
            current.append(path)
        }
        useReferenceImages = !current.isEmpty
        draft.referenceImagePaths = current
        if useReferenceImages, let record = records.first(where: { $0.imagePath == path }) {
            adoptSeriesSeed(record, applyToDraft: true)
        }
        refreshResolvedPrompt()
    }

    func setUseReferenceImages(_ on: Bool) {
        if on {
            useReferenceImages = true
            if draft.referenceImagePaths?.isEmpty != false {
                draft.referenceImagePaths = nil
            }
            if displayedReferencePaths.isEmpty, let path = suggestedReferencePaths.first {
                draft.referenceImagePaths = [path]
            }
        } else {
            useReferenceImages = false
            draft.referenceImagePaths = []
        }
        refreshResolvedPrompt()
    }

    func clearReferenceImages() {
        setUseReferenceImages(false)
    }

    func enableSuggestedReference() {
        setUseReferenceImages(true)
    }

    func continueFromSelected() {
        if let record = selectedCandidate {
            useArtworkAsReference(record.id)
        }
        requestGeneration()
    }

    func useArtworkAsReference(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), let path = record.imagePath else { return }
        if let seriesID = record.request.seriesID {
            selectChannel(seriesID)
            adoptSeriesSeed(record, applyToDraft: true)
        } else {
            selectChannel(nil)
        }
        useReferenceImages = true
        draft.referenceImagePaths = [path]
        let core = artworkCoreKeywords(record)
        let prompt = record.finalPromptText
        draft.input = core.isEmpty ? prompt : core
        finalPrompt = prompt
        promptWasAIOptimized = !prompt.isEmpty
        notice = prompt.isEmpty
            ? "已用这张当起点。再出一组会按它继续。"
            : "已载入这张的最终 Prompt。点生成会按它再出。"
        // Keep loaded Prompt — do not rebuild from draft.
    }

    /// Core keywords shown in library / loaded for 再出.
    func artworkCoreKeywords(_ record: GenerationRecord) -> String {
        let stored = record.coreKeywordsText
        if !stored.isEmpty { return stored }
        if let seriesID = record.request.seriesID,
           let series = channels.first(where: { $0.id == seriesID }) {
            let locked = series.lockedCore.trimmingCharacters(in: .whitespacesAndNewlines)
            if !locked.isEmpty { return locked }
            let core = series.resolvedCoreKeywords
            if !core.isEmpty { return core }
        }
        return ""
    }

    func selectModelConfiguration(_ id: UUID) {
        activeModelConfigurationID = id
        connectionNotice = nil
        apiKeyDraft = ""
        if let config = modelConfigurations.first(where: { $0.id == id }),
           let route = verifiedImageRoute,
           route.matches(config)
        {
            verifiedConfigurationID = id
        } else {
            verifiedConfigurationID = nil
            verifiedImageRoute = nil
        }
        persist()
        Task { await refreshKeyStatus() }
    }

    func imageModelPickerTitle(for configuration: ModelConfiguration) -> String {
        if configuration.provider == .demo { return "离线演示" }
        let name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return model }
        if model.isEmpty || name == model { return name }
        return "\(name) · \(model)"
    }

    func updateActiveModelConfiguration(_ configuration: ModelConfiguration) {
        guard let index = modelConfigurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        let previous = modelConfigurations[index]
        modelConfigurations[index] = configuration
        verifiedConfigurationID = nil
        allowPersistingModelConfigurations = true
        if previous.baseURL != configuration.baseURL
            || previous.model != configuration.model
            || previous.provider != configuration.provider
        {
            clearImageVerification(notice: nil)
        }
        persistSoon()
    }

    func addModelConfiguration() {
        let config = ModelConfiguration(name: "新的图片模型", provider: .compatible)
        modelConfigurations.append(config)
        allowPersistingModelConfigurations = true
        selectModelConfiguration(config.id)
    }

    func deleteActiveModelConfiguration() {
        guard let id = activeModelConfigurationID else { return }
        modelConfigurations.removeAll { $0.id == id }
        activeModelConfigurationID = modelConfigurations.first?.id
        allowPersistingModelConfigurations = true
        clearImageVerification(notice: nil)
        persist()
        Task { try? await credentials.delete(for: id); await refreshKeyStatus() }
    }

    func saveModelConfiguration() {
        guard let config = activeModelConfiguration else { return }
        do { _ = try config.validated() }
        catch { connectionNotice = error.localizedDescription; return }
        allowPersistingModelConfigurations = true
        Task {
            do {
                if config.provider != .demo, !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await credentials.save(apiKeyDraft, for: config.id)
                    apiKeyDraft = ""
                }
                await refreshKeyStatus()
                persist()
                connectionNotice = config.provider == .demo ? "离线演示配置已保存。" : "配置已保存；Key 在，但还没验证出图。请点「保存并测试」。"
            } catch { connectionNotice = error.localizedDescription }
        }
    }

    func removeActiveAPIKey() {
        guard let id = activeModelConfigurationID else { return }
        Task {
            do {
                try await credentials.delete(for: id)
                apiKeyDraft = ""
                verifiedConfigurationID = nil
                await refreshKeyStatus()
                connectionNotice = "AK 已从本机凭据删除。"
            } catch { connectionNotice = error.localizedDescription }
        }
    }

    func saveAndTestModelConnection() {
        guard let config = activeModelConfiguration else { return }
        do { _ = try config.validated() }
        catch { connectionNotice = error.localizedDescription; return }
        isTestingConnection = true
        connectionNotice = "正在用图片模型 \(config.model) 真正试出一张…"
        allowPersistingModelConfigurations = true
        Task {
            do {
                let transient = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if config.provider != .demo, !transient.isEmpty {
                    try await credentials.save(transient, for: config.id)
                    apiKeyDraft = ""
                }
                let stored = try await credentials.read(for: config.id)
                let fingerprint = OpenAIImageProvider.fingerprint(stored ?? "")
                connectionNotice = "令牌 \(fingerprint)；正在用 \(config.model) 试出一张…"
                let provider = try providerFactory.make(configuration: config, apiKey: stored)
                try await provider.testConnection()
                await refreshKeyStatus()
                verifiedConfigurationID = config.id
                verifiedImageRoute = ImageRoute.from(config)
                persist()
                connectionNotice = "连接成功：出图测试通过。\(config.model) → \(ImageRoute.from(config).generationsURL)（令牌 \(fingerprint)；尺寸 \(OpenAIImageProvider.normalizedSize(config.size, dialect: OpenAIImageProvider.imageAPIDialect(baseURL: config.baseURL)))）"
            } catch {
                clearImageVerification(notice: error.localizedDescription)
            }
            isTestingConnection = false
        }
    }

    private func clearImageVerification(notice: String?) {
        verifiedConfigurationID = nil
        verifiedImageRoute = nil
        if let notice {
            connectionNotice = notice
        }
    }

    func generate() {
        guard !isGenerating else { return }
        guard canGenerate else {
            notice = generationBlockReason
            return
        }
        let promptToGenerate = finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptToGenerate.isEmpty else { notice = MusepaperError.emptyPrompt.localizedDescription; return }
        startGeneration(prompt: promptToGenerate, trigger: .manual, variationSeed: nil)
    }

    /// The product-level creation action. Every candidate is rewritten into a
    /// unique pure-scene prompt before it reaches the image model.
    func designAndGenerate() {
        guard !isGenerating, !isOptimizingPrompt else { return }
        if let reason = generationBlockReason {
            notice = reason
            return
        }
        rememberPromptOnSelectedSeries()
        persist()
        let reuseLoadedPrompt = promptWasAIOptimized
            && !finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !reuseLoadedPrompt {
            refreshResolvedPrompt()
        }
        let fallbackPrompt = finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackPrompt.isEmpty else {
            notice = MusepaperError.emptyPrompt.localizedDescription
            return
        }

        let batchID = beginPreparingBatch(trigger: .manual, seriesID: selectedChannelID, prompt: fallbackPrompt)
        generationTotal = InspirationChannel.clampedCount(batchSize)
        generationIndex = 0
        notice = reuseLoadedPrompt
            ? "正在按已载入的最终 Prompt 再出一组。"
            : (canOptimizePrompt
                ? "正在为每一张单独设计不同画面。"
            : (promptAgentRouting.enabled
                ? "文字模型还没连上，已改用内置纯场景改写，每张都会不同。"
                : "正在按内置纯场景改写生成这一组，每张都会不同。"))
        startGeneration(
            prompt: fallbackPrompt,
            trigger: .manual,
            variationSeed: nil,
            reuseBatchID: batchID,
            preferExactPrompt: reuseLoadedPrompt
        )
    }

    func cancelCreation() {
        if isOptimizingPrompt { cancelPromptOptimization() }
        if isGenerating { cancelGeneration() }
    }

    private func startGeneration(
        prompt: String, trigger: GenerationTrigger, variationSeed: Int?,
        seriesID: UUID? = nil, candidateCount: Int? = nil, rawInput: String? = nil,
        referenceImagePaths: [String]? = nil, reuseBatchID: UUID? = nil,
        preferExactPrompt: Bool = false
    ) {
        if let mismatch = pathwayMismatchReason {
            notice = mismatch
            return
        }
        if let modelName = activeModelConfiguration?.model, OpenAIImageProvider.looksLikeChatModel(modelName) {
            notice = "「\(modelName)」是对话模型，出图会 404。去设置把「图片模型」改成文生图模型。"
            return
        }
        guard !isGenerating else {
            if trigger == .scheduled, let id = seriesID ?? selectedChannelID {
                enqueueScheduledTask(id)
            }
            return
        }
        let resolvedSeriesID = seriesID ?? selectedChannelID
        let providerPrompt = composer.enforcePureArtwork(prompt)
        let batchID = reuseBatchID ?? beginPreparingBatch(
            trigger: trigger, seriesID: resolvedSeriesID, prompt: providerPrompt
        )
        if let index = batches.firstIndex(where: { $0.id == batchID }) {
            batches[index].prompt = providerPrompt
            batches[index].seriesID = resolvedSeriesID
            batches[index].trigger = trigger
            batches[index].state = .preparing
        }
        let refs = existingImagePaths(referenceImagePaths ?? referencesForNextGeneration(seriesID: resolvedSeriesID))
        let seriesForNegative = resolvedSeriesID.flatMap { id in channels.first { $0.id == id } }
        let ideaForRequest = rawInput ?? draft.input
        let seriesForCore = resolvedSeriesID
            .flatMap { id in channels.first { $0.id == id } }
            .flatMap { $0.isSchemaTemplate ? nil : $0 }
        let coreForRecord = composer.userCore(idea: ideaForRequest, channel: seriesForCore)
        let request = GenerationRequest(
            id: UUID(), rawInput: ideaForRequest, resolvedPrompt: providerPrompt,
            negativePrompt: composer.negativePrompt(draft: draft, channel: seriesForNegative),
            display: selectedDisplay, createdAt: Date(),
            referenceImagePaths: refs.isEmpty ? nil : refs, batchID: batchID,
            seriesID: resolvedSeriesID, variationSeed: variationSeed,
            coreKeywords: coreForRecord
        )
        activeBatchID = batchID
        // 系列续出：保留当前预览，直到第一张新图落盘；新建会话则清空选中。
        if resolvedSeriesID == nil {
            selectedCandidateID = nil
        } else if let id = selectedCandidateID,
                  !records.contains(where: {
                      $0.id == id && $0.request.seriesID == resolvedSeriesID && $0.hasUsableImageFile
                  }) {
            selectedCandidateID = nil
        }
        isGenerating = true
        notice = nil
        persist()

        generationTask = Task {
            var candidateIDs: [UUID] = []
            do {
                updateBatch(batchID, state: .generating)
                guard var config = activeModelConfiguration else { throw MusepaperError.invalidConfiguration("没有活动模型配置") }
                if let route = verifiedImageRoute {
                    config.baseURL = route.baseURL
                    config.model = route.model
                    config.provider = route.provider
                }
                let targetCount = InspirationChannel.clampedCount(candidateCount ?? batchSize)
                generationTotal = targetCount
                generationIndex = 0
                // Many compatible image APIs silently ignore `n`. One request per
                // candidate makes the promised batch size deterministic and keeps
                // every candidate's variation seed and retry history explicit.
                config.imageCount = 1
                let key = try await credentials.read(for: config.id)
                let provider = try providerFactory.make(configuration: config, apiKey: key)
                let pipeline = GenerationPipeline(provider: provider)
                let output = generationOutputDirectory
                let series = resolvedSeriesID
                    .flatMap { id in channels.first { $0.id == id } }
                    .flatMap { $0.isSchemaTemplate ? nil : $0 }
                let requestSeed = batchID.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
                let seedBase = (variationSeed ?? requestSeed) &* 10
                let idea = ideaForRequest
                let themeSource = coreForRecord
                let combos = variationPlanner.plan(
                    idea: themeSource, count: targetCount, seed: seedBase,
                    customAxes: series?.resolvedVariationAxes ?? ""
                )
                let promptAgentEnabled = !preferExactPrompt
                let sharedAgent = promptAgentEnabled ? await makePromptAgentIfAvailable() : nil
                let textGate = AdaptiveConcurrencyGate(
                    initial: min(4, targetCount),
                    minimum: 1,
                    maximum: min(6, max(1, targetCount))
                )
                let imageGate = AdaptiveConcurrencyGate(
                    initial: min(3, targetCount),
                    minimum: 1,
                    maximum: min(4, max(1, targetCount))
                )
                let deduper = PromptDeduper()
                let draftSnapshot = draft
                let displaySnapshot = selectedDisplay
                var usedAgent = false
                var firstFailure: String?

                try await withThrowingTaskGroup(of: ParallelCandidateResult.self) { group in
                    for candidateIndex in 0..<targetCount {
                        let combo = combos[candidateIndex]
                        let baseRequest = request
                        let theme = themeSource
                        let ideaSnapshot = idea
                        let seriesSnapshot = series
                        let exactPrompt = preferExactPrompt
                        let providerPromptSnapshot = providerPrompt
                        let seed = seedBase
                        group.addTask {
                            try await Self.buildParallelCandidate(
                                candidateIndex: candidateIndex,
                                baseRequest: baseRequest,
                                themeSource: theme,
                                idea: ideaSnapshot,
                                series: seriesSnapshot,
                                combo: combo,
                                draft: draftSnapshot,
                                display: displaySnapshot,
                                preferExactPrompt: exactPrompt,
                                providerPrompt: providerPromptSnapshot,
                                seedBase: seed,
                                sharedAgent: sharedAgent,
                                textGate: textGate,
                                imageGate: imageGate,
                                deduper: deduper,
                                pipeline: pipeline,
                                outputDirectory: output,
                                artworkTagger: ArtworkTagger()
                            )
                        }
                    }

                    for try await built in group {
                        guard !Task.isCancelled else { throw CancellationError() }
                        if let err = built.errorMessage {
                            if firstFailure == nil { firstFailure = err }
                            continue
                        }
                        guard let record = built.record, let urlPath = record.imagePath else { continue }
                        if built.usedAgent { usedAgent = true }
                        if let noticeText = built.agentNotice, promptAgentNotice == nil {
                            promptAgentNotice = noticeText
                        }
                        records.insert(record, at: 0)
                        candidateIDs.append(record.id)
                        if let index = batches.firstIndex(where: { $0.id == batchID }) {
                            batches[index].recordIDs = candidateIDs
                        }
                        generationIndex = candidateIDs.count
                        selectedCandidateID = record.id
                        ArtworkPromptSidecar.write(
                            finalPrompt: record.request.resolvedPrompt,
                            rawInput: record.request.rawInput,
                            negativePrompt: record.request.negativePrompt,
                            coreKeywords: themeSource,
                            nextTo: URL(fileURLWithPath: urlPath)
                        )
                        persist()
                    }
                }
                if candidateIDs.isEmpty, let firstFailure {
                    throw MusepaperError.generationFailed(firstFailure)
                }
                if let index = batches.firstIndex(where: { $0.id == batchID }) {
                    batches[index].state = .ready
                    if candidateIDs.count < targetCount, let firstFailure {
                        batches[index].errorMessage = "完成 \(candidateIDs.count)/\(targetCount)：\(firstFailure)"
                    }
                }
                isGenerating = false
                promptWasAIOptimized = usedAgent || preferExactPrompt
                pruneHistory()
                persist()
                await enrichTags(candidateIDs, task: series)
                notice = candidateIDs.count < targetCount
                    ? "本批完成 \(candidateIDs.count)/\(targetCount)\(firstFailure.map { "，其余失败：\($0)" } ?? "")"
                    : nil
                markSeriesProgress(seriesID: resolvedSeriesID)
                if trigger == .scheduled, settings.scheduledApplyMode == .applyFirst { applySelectedCandidate() }
            } catch is CancellationError {
                updateBatch(batchID, state: candidateIDs.isEmpty ? .cancelled : .ready, error: candidateIDs.isEmpty ? nil : "生成已取消，保留已完成的 \(candidateIDs.count) 张")
                isGenerating = false
                notice = candidateIDs.isEmpty ? "已取消本次生成，没有替换壁纸。" : "已停止继续生成，保留已完成的 \(candidateIDs.count) 张供选择。"
            } catch {
                updateBatch(batchID, state: candidateIDs.isEmpty ? .failed : .ready, error: error.localizedDescription)
                isGenerating = false
                notice = candidateIDs.isEmpty
                    ? error.localizedDescription
                    : "本批只完成 \(candidateIDs.count) 张，其余失败：\(error.localizedDescription)"
            }
            preparingBatchID = nil
            drainScheduledQueue()
        }
    }

    private struct ParallelCandidateResult: Sendable {
        var record: GenerationRecord?
        var usedAgent: Bool
        var agentNotice: String?
        var errorMessage: String?
    }

    private nonisolated static func buildParallelCandidate(
        candidateIndex: Int,
        baseRequest: GenerationRequest,
        themeSource: String,
        idea: String,
        series: InspirationChannel?,
        combo: VariationCombo,
        draft: PromptDraft,
        display: DisplayProfile,
        preferExactPrompt: Bool,
        providerPrompt: String,
        seedBase: Int,
        sharedAgent: PromptAgent?,
        textGate: AdaptiveConcurrencyGate,
        imageGate: AdaptiveConcurrencyGate,
        deduper: PromptDeduper,
        pipeline: GenerationPipeline,
        outputDirectory: URL,
        artworkTagger: ArtworkTagger
    ) async throws -> ParallelCandidateResult {
        let composer = PromptComposer()
        var candidateRequest = baseRequest
        candidateRequest.id = UUID()
        candidateRequest.variationSeed = seedBase + candidateIndex
        candidateRequest.coreKeywords = themeSource
        candidateRequest.display = display

        let fallback = composer.weave(idea: themeSource, combo: combo, draft: draft, channel: series)
        var scene: String
        var usedAgent = false
        var agentNotice: String?

        if preferExactPrompt {
            scene = composer.withVisualVariation(providerPrompt, cue: combo.visualPhrase)
            scene = composer.pinCore(themeSource, onto: scene)
        } else {
            scene = fallback
            if let promptAgent = sharedAgent {
                do {
                    let context = PromptEnhancementContext.makeParallel(
                        idea: idea,
                        themeSource: themeSource,
                        deterministic: fallback,
                        channel: series,
                        draft: draft,
                        display: display,
                        seed: seedBase + candidateIndex,
                        dimensionCombo: combo.visualPhrase,
                        referenceImageCount: baseRequest.referenceImagePaths?.count ?? 0
                    )
                    let enhanced = try await textGate.runWithPressureRetry {
                        try await promptAgent.enhance(context)
                    }
                    if !composer.containsInstructionLeak(enhanced), enhanced.count >= 12 {
                        scene = composer.pinCore(themeSource, onto: enhanced)
                        usedAgent = true
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    agentNotice = error.localizedDescription
                    scene = fallback
                }
            }
        }

        candidateRequest.resolvedPrompt = await deduper.distinguish(
            scene, index: candidateIndex, seed: seedBase, core: themeSource
        )

        let finalRequest = candidateRequest
        do {
            let urls = try await imageGate.runWithPressureRetry {
                try await pipeline.run(finalRequest, outputDirectory: outputDirectory)
            }
            guard let url = urls.first else {
                return ParallelCandidateResult(record: nil, usedAgent: usedAgent, agentNotice: agentNotice, errorMessage: MusepaperError.missingImage.localizedDescription)
            }
            let record = GenerationRecord(
                id: candidateRequest.id, request: candidateRequest, state: .ready,
                imagePath: url.path, isFavorite: false, updatedAt: Date(),
                tags: artworkTagger.fallbackTags(prompt: candidateRequest.resolvedPrompt, task: series),
                tagSummary: "基于主题与生成 Prompt 自动标注"
            )
            return ParallelCandidateResult(record: record, usedAgent: usedAgent, agentNotice: agentNotice, errorMessage: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ParallelCandidateResult(record: nil, usedAgent: usedAgent, agentNotice: agentNotice, errorMessage: error.localizedDescription)
        }
    }

    private func beginPreparingBatch(trigger: GenerationTrigger, seriesID: UUID?, prompt: String) -> UUID {
        if let existing = preparingBatchID, let index = batches.firstIndex(where: { $0.id == existing }) {
            batches[index].seriesID = seriesID
            batches[index].prompt = prompt
            batches[index].trigger = trigger
            batches[index].state = .preparing
            activeBatchID = existing
            return existing
        }
        let batchID = UUID()
        let batch = GenerationBatch(
            id: batchID, seriesID: seriesID, recordIDs: [], selectedRecordID: nil,
            prompt: prompt, trigger: trigger, state: .preparing, createdAt: Date(), errorMessage: nil
        )
        batches.insert(batch, at: 0)
        preparingBatchID = batchID
        activeBatchID = batchID
        persist()
        return batchID
    }

    private func abandonPreparingBatch(_ id: UUID) {
        guard let index = batches.firstIndex(where: { $0.id == id }) else { return }
        guard batches[index].recordIDs.isEmpty else { return }
        batches.remove(at: index)
        if preparingBatchID == id { preparingBatchID = nil }
        if activeBatchID == id {
            activeBatchID = batches.first?.id
            selectedCandidateID = batches.first?.selectedRecordID ?? batches.first?.recordIDs.first
        }
        persist()
    }

    private func enqueueScheduledTask(_ id: UUID) {
        if !pendingScheduledTaskIDs.contains(id) {
            pendingScheduledTaskIDs.append(id)
        }
        notice = "当前这组还在生成，到点的任务已排队，不会丢掉。"
    }

    private func drainScheduledQueue() {
        guard !isCreationBusy, let next = pendingScheduledTaskIDs.first else { return }
        pendingScheduledTaskIDs.removeFirst()
        runScheduledGeneration(taskID: next)
    }

    func adoptSeriesSeed(_ record: GenerationRecord, applyToDraft: Bool = false) {
        guard let path = record.imagePath else { return }
        if let seriesID = record.request.seriesID, let index = channels.firstIndex(where: { $0.id == seriesID }) {
            channels[index].seedArtworkPath = path
            channels[index].seedArtworkID = record.id
        }
        guard applyToDraft else { return }
        useReferenceImages = true
        draft.referenceImagePaths = existingImagePaths([path])
    }

    private func markSeriesProgress(seriesID: UUID?) {
        if let seriesID, let index = channels.firstIndex(where: { $0.id == seriesID }) {
            channels[index].lastProducedAt = Date()
            persist()
            configureAutomations()
        }
    }

    private func syncSeriesTimeline(_ id: UUID) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else { return }
        if channels[index].lastProducedAt == nil {
            channels[index].lastProducedAt = records
                .filter { $0.request.seriesID == id && $0.imagePath != nil }
                .map(\.updatedAt)
                .max()
        }
        if channels[index].seedArtworkPath == nil,
           let latest = records.first(where: { $0.request.seriesID == id && $0.imagePath != nil }) {
            channels[index].seedArtworkPath = latest.imagePath
            channels[index].seedArtworkID = latest.id
        }
    }

    private func effectiveLastProducedAt(for channel: InspirationChannel) -> Date? {
        channel.lastProducedAt ?? records
            .filter { $0.request.seriesID == channel.id && $0.imagePath != nil }
            .map(\.updatedAt)
            .max()
    }

    private func defaultSeriesReferences(for seriesID: UUID?) -> [String] {
        guard let seriesID, let channel = channels.first(where: { $0.id == seriesID }) else { return [] }
        let seed = channel.resolvedSeedPath
            ?? records.first(where: { $0.request.seriesID == seriesID })?.imagePath
        return existingImagePaths([seed].compactMap { $0 } + channel.resolvedReferenceImagePaths)
    }

    private func referencesForNextGeneration(seriesID: UUID?, ignoreOptOut: Bool = false) -> [String] {
        if !ignoreOptOut && !useReferenceImages { return [] }
        if let explicit = draft.referenceImagePaths, selectedChannelID == seriesID || seriesID == nil {
            return existingImagePaths(explicit)
        }
        return defaultSeriesReferences(for: seriesID)
    }

    private func existingImagePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path), !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    func retry(_ record: GenerationRecord) {
        guard !isGenerating else { return }
        draft.input = record.request.rawInput
        draft.referenceImagePaths = record.request.referenceImagePaths
        finalPrompt = record.request.resolvedPrompt
        selectedDisplay = record.request.display
        if let batchID = record.request.batchID,
           let batch = batches.first(where: { $0.id == batchID }) {
            batchSize = max(batch.recordIDs.count, 1)
        }
        generate()
    }

    func applySelectedCandidate() {
        guard let record = selectedCandidate, let path = record.imagePath else {
            notice = "请先在这一批候选中选中一张壁纸。"; return
        }
        if let index = batches.firstIndex(where: { $0.id == activeBatchID }) {
            batches[index].selectedRecordID = record.id
        }
        enqueueWallpaperApply(path: path, recordID: record.id, adopt: true)
    }

    func applyLatest() { applySelectedCandidate() }

    func applyArtwork(_ id: UUID, displayIDs: [String]? = nil) {
        guard let record = records.first(where: { $0.id == id }), let path = record.imagePath else { return }
        enqueueWallpaperApply(path: path, recordID: record.id, adopt: true, displayIDs: displayIDs)
    }

    func restorePrevious() {
        Task {
            do {
                try await wallpaper.restore(
                    paths: snapshot.previousWallpaperPaths,
                    transition: settings.wallpaperTransition ?? WallpaperTransition.none
                )
                notice = "已恢复替换前的壁纸。"
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private struct WallpaperApplyJob {
        var assignments: [(displayID: String, path: String, recordID: UUID)]
        var adopt: Bool
        var playlistID: UUID?
        var playlistName: String?

        var primaryRecordID: UUID { assignments[0].recordID }
    }

    private var pendingWallpaperJob: WallpaperApplyJob?
    private var isDrainingWallpaperJobs = false

    private func enqueueWallpaperApply(
        path: String,
        recordID: UUID,
        adopt: Bool,
        playlistID: UUID? = nil,
        playlistName: String? = nil,
        displayIDs: [String]? = nil
    ) {
        refreshDisplays()
        let targets: [String]
        if let displayIDs, !displayIDs.isEmpty {
            targets = displayIDs
        } else if wallpaperApplyIntent.allDisplays {
            targets = displayProfiles.map(\.id)
        } else {
            targets = [wallpaperApplyIntent.targetDisplayID]
        }
        let assignments = targets.map { (displayID: $0, path: path, recordID: recordID) }
        enqueueWallpaperApply(
            assignments: assignments,
            adopt: adopt,
            playlistID: playlistID,
            playlistName: playlistName
        )
    }

    private func enqueueWallpaperApply(
        assignments: [(displayID: String, path: String, recordID: UUID)],
        adopt: Bool,
        playlistID: UUID? = nil,
        playlistName: String? = nil
    ) {
        guard !assignments.isEmpty else { return }
        pendingWallpaperJob = WallpaperApplyJob(
            assignments: assignments,
            adopt: adopt,
            playlistID: playlistID,
            playlistName: playlistName
        )
        Task { await drainWallpaperJobs() }
    }

    private func drainWallpaperJobs() async {
        guard !isDrainingWallpaperJobs else { return }
        isDrainingWallpaperJobs = true
        defer { isDrainingWallpaperJobs = false }
        while let job = pendingWallpaperJob {
            pendingWallpaperJob = nil
            await applyWallpaper(job)
        }
    }

    private func applyWallpaper(_ job: WallpaperApplyJob) async {
        do {
            refreshDisplays()
            if snapshot.previousWallpaperPaths.isEmpty { snapshot.previousWallpaperPaths = wallpaper.currentPaths() }
            let screenAssignments = job.assignments.map {
                WallpaperController.ScreenAssignment(
                    displayID: $0.displayID,
                    imageURL: URL(fileURLWithPath: $0.path)
                )
            }
            try await wallpaper.apply(assignments: screenAssignments, transition: WallpaperTransition.none)
            for item in job.assignments {
                updateRecord(item.recordID, state: .applied)
            }
            rememberAppliedAssignments(
                job.assignments.map { (displayID: $0.displayID, artworkID: $0.recordID) }
            )
            if let playlistID = job.playlistID,
               let live = playlists.firstIndex(where: { $0.id == playlistID }) {
                playlists[live].rememberAssignments(
                    job.assignments.map { (displayID: $0.displayID, artworkID: $0.recordID) }
                )
            }
            if job.adopt, let record = records.first(where: { $0.id == job.primaryRecordID }) {
                if let index = batches.firstIndex(where: { $0.id == activeBatchID }) {
                    batches[index].selectedRecordID = job.primaryRecordID
                    batches[index].state = .applied
                }
                adoptSeriesSeed(record, applyToDraft: false)
            }
            persist()
            refreshDesktopControls()
            if let name = job.playlistName {
                let screens = Set(job.assignments.map(\.displayID)).count
                let images = Set(job.assignments.map(\.recordID)).count
                if screens > 1, images > 1 {
                    notice = "轮播“\(name)”已为 \(screens) 块屏换上不同壁纸。"
                } else if screens > 1 {
                    notice = "轮播“\(name)”已更新 \(screens) 块屏。"
                } else {
                    notice = "轮播“\(name)”已切换到下一张。"
                }
            } else {
                notice = "桌面已换好。"
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isFavorite.toggle(); persist()
        refreshDesktopControls()
    }

    /// Desktop corner: mark this screen's wallpaper with favorite +「喜欢」tag.
    func likeCurrentDesktopWallpaper(displayID: String? = nil) {
        let screenID = resolvedDesktopDisplayID(displayID)
        guard let record = resolveWallpaperRecord(on: screenID) else {
            notice = "这块屏上还不是 Musepaper 作品，没法标记喜欢。"
            return
        }
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let tag = DesktopControlOverlay.likedTag
        var tags = records[index].resolvedTags
        let alreadyLiked = records[index].isFavorite || tags.contains(tag)
        if alreadyLiked {
            records[index].isFavorite = false
            tags.removeAll { $0 == tag }
            notice = "已取消喜欢这块屏的壁纸。"
        } else {
            records[index].isFavorite = true
            if !tags.contains(tag) { tags.insert(tag, at: 0) }
            notice = "已喜欢这块屏的壁纸，并加上 #\(tag)。"
        }
        records[index].tags = tags
        records[index].updatedAt = Date()
        persist()
        refreshDesktopControls()
    }

    /// Desktop corner: trash this screen's wallpaper, then advance only that screen.
    func deleteCurrentDesktopWallpaper(displayID: String? = nil) {
        let now = Date()
        if let last = lastDesktopControlAt, now.timeIntervalSince(last) < 0.7 {
            return
        }
        lastDesktopControlAt = now
        let screenID = resolvedDesktopDisplayID(displayID)
        guard let record = resolveWallpaperRecord(on: screenID) else {
            notice = "这块屏上还不是 Musepaper 作品，没法删除。"
            return
        }
        let doomedID = record.id
        moveToTrash(doomedID, announce: false)
        if let running = owningPlaylist(for: screenID) {
            playPlaylistNow(running.id, excluding: doomedID, displayIDs: [screenID])
            notice = "已把这块屏的壁纸移入回收箱，并换上下一张。"
            return
        }
        if let advance = prepareLibraryAdvance(afterRemoving: doomedID) {
            enqueueWallpaperApply(
                path: advance.path,
                recordID: advance.recordID,
                adopt: false,
                displayIDs: [screenID]
            )
            notice = "已把这块屏的壁纸移入回收箱，并换上下一张。"
        } else {
            notice = "已把这块屏的壁纸移入回收箱。暂时没有可换的下一张了。"
        }
    }

    private struct DesktopAdvance {
        var path: String
        var recordID: UUID
    }

    private func prepareLibraryAdvance(afterRemoving doomedID: UUID) -> DesktopAdvance? {
        let ordered = records
            .filter { !$0.isTrashed && $0.hasUsableImageFile }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard let position = ordered.firstIndex(where: { $0.id == doomedID }) else {
            let fallback = ordered.first { $0.id != doomedID }
            guard let next = fallback, let path = next.imagePath else { return nil }
            return DesktopAdvance(path: path, recordID: next.id)
        }
        let remaining = ordered.filter { $0.id != doomedID }
        guard !remaining.isEmpty else { return nil }
        var next = ordered[(position + 1) % ordered.count]
        if next.id == doomedID { next = remaining[0] }
        guard let path = next.imagePath else { return nil }
        return DesktopAdvance(path: path, recordID: next.id)
    }

    private func pickPlaylistSuccessor(
        from pool: [GenerationRecord],
        order: PlaylistOrder,
        currentID: UUID
    ) -> GenerationRecord {
        switch order {
        case .shuffle:
            return pool.filter { $0.id != currentID }.randomElement() ?? pool[0]
        case .newest:
            let ordered = pool.sorted { $0.updatedAt > $1.updatedAt }
            if let position = ordered.firstIndex(where: { $0.id == currentID }) {
                return ordered[(position + 1) % ordered.count]
            }
            return ordered[0]
        case .oldest:
            let ordered = pool.sorted { $0.updatedAt < $1.updatedAt }
            if let position = ordered.firstIndex(where: { $0.id == currentID }) {
                return ordered[(position + 1) % ordered.count]
            }
            return ordered[0]
        }
    }

    /// Desktop corner: advance this screen only.
    func playNextDesktopWallpaper(displayID: String? = nil) {
        let now = Date()
        if let last = lastDesktopControlAt, now.timeIntervalSince(last) < 0.7 {
            return
        }
        lastDesktopControlAt = now
        let screenID = resolvedDesktopDisplayID(displayID)
        if let running = owningPlaylist(for: screenID) {
            playPlaylistNow(running.id, displayIDs: [screenID])
            return
        }
        let candidates = records.filter { !$0.isTrashed && $0.hasUsableImageFile }
        guard !candidates.isEmpty else {
            notice = "作品集里还没有可换的壁纸。"
            return
        }
        let currentID = resolveWallpaperRecord(on: screenID)?.id
        let ordered = candidates.sorted { $0.updatedAt > $1.updatedAt }
        let next: GenerationRecord
        if let currentID, let position = ordered.firstIndex(where: { $0.id == currentID }) {
            next = ordered[(position + 1) % ordered.count]
        } else {
            next = ordered[0]
        }
        applyArtwork(next.id, displayIDs: [screenID])
    }

    func toggleLibraryTag(_ tag: String) {
        if selectedLibraryTags.contains(tag) { selectedLibraryTags.remove(tag) }
        else { selectedLibraryTags.insert(tag) }
    }

    /// Retag every artwork currently visible under library filters (incl. selected tags).
    func retagFilteredArtworks() {
        let ids = filteredArtworks.map(\.id)
        guard !ids.isEmpty else {
            notice = "当前筛选下没有可重打标签的作品。"
            return
        }
        startRetag(ids: ids, dropTags: selectedLibraryTags)
    }

    func retagArtwork(_ id: UUID) {
        startRetag(ids: [id], dropTags: [])
    }

    func cancelRetag() {
        retagTask?.cancel()
        retagTask = nil
        isRetagging = false
        notice = retagTotal > 0
            ? "已停止重打标签（完成 \(retagDone)/\(retagTotal)）。"
            : "已停止重打标签。"
    }

    private func startRetag(ids: [UUID], dropTags: Set<String>) {
        guard !isRetagging else { return }
        retagTask?.cancel()
        isRetagging = true
        retagDone = 0
        retagTotal = ids.count
        let useAgent = promptAgentRouting.enabled && promptAPIKeyConfigured
        notice = useAgent
            ? "正在并行用 Agent 重打标签 \(ids.count) 张（遇阻塞自动降并发）…"
            : "正在并行重打标签 \(ids.count) 张…"
        retagTask = Task { @MainActor in
            defer {
                isRetagging = false
                retagTask = nil
            }
            await retagRecords(ids, dropTags: dropTags, useAgent: useAgent)
        }
    }

    private func retagRecords(_ ids: [UUID], dropTags: Set<String>, useAgent: Bool) async {
        var failures = 0
        let gate = AdaptiveConcurrencyGate(
            initial: useAgent ? min(4, ids.count) : min(8, ids.count),
            minimum: 1,
            maximum: useAgent ? min(6, max(1, ids.count)) : min(12, max(1, ids.count))
        )
        let agent = useAgent ? await makePromptAgentIfAvailable() : nil
        let agentName = lastUsedPromptModelName ?? agent?.configuration.model
        let stale: Set<String> = dropTags.union([ArtworkTagger.userLikedTag, "磁盘恢复", "磁盘找回"])

        struct RetagWork: Sendable {
            let id: UUID
            let tags: [String]
            let tagSummary: String
            let title: String?
            let failedAgent: Bool
        }

        await withTaskGroup(of: RetagWork?.self) { group in
            for id in ids {
                let snapshot: (prompt: String, imagePath: String?, series: InspirationChannel?, rawInput: String)? = {
                    guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
                    let series = records[index].request.seriesID.flatMap { sid in channels.first { $0.id == sid } }
                    return (
                        retagPromptText(for: records[index], series: series),
                        records[index].imagePath,
                        series,
                        records[index].request.rawInput
                    )
                }()
                group.addTask {
                    guard let snapshot else { return nil }
                    var failedAgent = false
                    var tags: [String]
                    var summary: String
                    if let agent {
                        do {
                            let jpeg: Data? = await Task.detached(priority: .utility) {
                                guard let path = snapshot.imagePath, !path.isEmpty else { return nil }
                                return WallpaperImageCache.jpegThumbnail(path: path, maxPixel: 512, quality: 0.55)
                            }.value
                            tags = try await gate.runWithPressureRetry {
                                try await agent.suggestTags(
                                    prompt: snapshot.prompt,
                                    taskName: snapshot.series?.name,
                                    imageJPEG: jpeg
                                )
                            }
                            let usedName = agentName ?? agent.configuration.model
                            summary = jpeg == nil
                                ? "由 \(usedName) 重新标注"
                                : "由 \(usedName) 看图标注（压缩预览）"
                        } catch is CancellationError {
                            return nil
                        } catch {
                            failedAgent = true
                            tags = ArtworkTagger().fallbackTags(prompt: snapshot.prompt, task: snapshot.series)
                            summary = "Agent 失败，已用本地标签重标"
                        }
                    } else {
                        tags = ArtworkTagger().fallbackTags(prompt: snapshot.prompt, task: snapshot.series)
                        summary = "本地重新标注"
                    }
                    tags = ArtworkTagger.mergeRetag(
                        generated: tags,
                        existing: [],
                        isFavorite: false,
                        dropping: stale
                    )
                    return RetagWork(id: id, tags: tags, tagSummary: summary, title: nil, failedAgent: failedAgent)
                }
            }

            for await work in group {
                if Task.isCancelled { break }
                guard let work else {
                    retagDone += 1
                    continue
                }
                guard let index = records.firstIndex(where: { $0.id == work.id }) else {
                    retagDone += 1
                    continue
                }
                if work.failedAgent { failures += 1 }
                records[index].tags = ArtworkTagger.mergeRetag(
                    generated: work.tags,
                    existing: records[index].resolvedTags,
                    isFavorite: records[index].isFavorite,
                    dropping: stale
                )
                records[index].tagSummary = work.tagSummary
                if shouldRefreshArtworkTitle(records[index].request.rawInput) {
                    records[index].request.rawInput = shortArtworkTitle(from: records[index].resolvedTags)
                }
                records[index].updatedAt = Date()
                retagDone += 1
                if retagDone % 25 == 0 || retagDone == retagTotal {
                    let limit = await gate.currentLimit
                    notice = useAgent
                        ? "正在并行重打标签 \(retagDone)/\(retagTotal)（并发 \(limit)）…"
                        : "正在重打标签 \(retagDone)/\(retagTotal)…"
                    persist()
                }
            }
        }
        persist()
        if Task.isCancelled { return }
        var parts = ["已重打标签 \(retagDone)/\(retagTotal)"]
        if failures > 0 { parts.append("其中 \(failures) 张 Agent 失败已回落本地") }
        if !dropTags.isEmpty {
            parts.append("已去掉筛选标签「\(dropTags.sorted().joined(separator: "、"))」")
        }
        notice = parts.joined(separator: "。") + "。"
    }

    private func retagPromptText(for record: GenerationRecord, series: InspirationChannel?) -> String {
        let resolved = record.request.resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = record.request.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if composer.usableVisual(resolved) != nil { return resolved }
        if !raw.isEmpty, raw != "磁盘恢复", raw != "磁盘找回", !looksLikeAssetFilename(raw),
           composer.usableVisual(raw) != nil {
            return raw
        }
        if let essence = series?.essence, composer.usableVisual(essence) != nil {
            return essence
        }
        if let name = series?.name, !name.isEmpty, name != "未命名任务" {
            return name
        }
        return "横向壁纸，开阔风景"
    }

    private func shouldRefreshArtworkTitle(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        if text == "磁盘恢复" || text == "磁盘找回" { return true }
        return looksLikeAssetFilename(text)
    }

    private func looksLikeAssetFilename(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") {
            return true
        }
        if lower.contains(".wallpaper") { return true }
        if text.count >= 32, text.contains("-"), text.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "." || $0 == "_" }) {
            return true
        }
        return false
    }

    private func shortArtworkTitle(from tags: [String]) -> String {
        let skip: Set<String> = ["横向壁纸", "AI 创作", "原图", "磁盘恢复", "磁盘找回", ArtworkTagger.userLikedTag]
        let parts = tags.filter { !skip.contains($0) }.prefix(3)
        if parts.isEmpty { return "壁纸作品" }
        return parts.joined(separator: " · ")
    }

    func saveCollection(_ collection: SmartCollection) {
        if let index = smartCollections.firstIndex(where: { $0.id == collection.id }) { smartCollections[index] = collection }
        else { smartCollections.append(collection) }
        activeCollectionID = collection.id
        persist()
        configureAutomations()
    }

    func deleteCollection(_ id: UUID) {
        smartCollections.removeAll { $0.id == id }
        playlists.removeAll { $0.source == .collection && $0.sourceID == id }
        if activeCollectionID == id { activeCollectionID = nil }
        persist(); configureAutomations()
    }

    func savePlaylist(_ playlist: WallpaperPlaylist) {
        var next = playlist
        if playlists.contains(where: { $0.id == next.id }) == false, next.priority == nil {
            next.priority = (playlists.map(\.resolvedPriority).max() ?? 0) + 1
        }
        if let index = playlists.firstIndex(where: { $0.id == next.id }) { playlists[index] = next }
        else { playlists.append(next) }
        persist(); configureAutomations()
    }

    var rankedPlaylists: [WallpaperPlaylist] {
        WallpaperPlaylist.ranked(playlists)
    }

    func playlistRank(_ playlist: WallpaperPlaylist) -> Int {
        WallpaperPlaylist.rank(of: playlist.id, among: playlists) ?? 1
    }

    func canRaisePlaylistPriority(_ id: UUID) -> Bool {
        playlistRankPosition(id).map { $0 > 0 } ?? false
    }

    func canLowerPlaylistPriority(_ id: UUID) -> Bool {
        guard let position = playlistRankPosition(id) else { return false }
        return position < playlists.count - 1
    }

    func movePlaylistPriority(_ id: UUID, higher: Bool) {
        let order = rankedPlaylists.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        let neighbor = higher ? index - 1 : index + 1
        guard order.indices.contains(neighbor) else { return }
        var next = order
        next.swapAt(index, neighbor)
        var weight = next.count
        for playlistID in next {
            guard let live = playlists.firstIndex(where: { $0.id == playlistID }) else { continue }
            playlists[live].priority = weight
            weight -= 1
        }
        persist()
        configureAutomations()
        refreshDesktopControls()
    }

    private func playlistRankPosition(_ id: UUID) -> Int? {
        rankedPlaylists.firstIndex { $0.id == id }
    }

    func setPlaylistEnabled(_ id: UUID, enabled: Bool) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].enabled = enabled
        if enabled && artworks(for: playlists[index]).isEmpty {
            notice = "这个轮播还没有作品。先生成一组，或换一个有图的来源。"
        }
        persist()
        configureAutomations()
    }

    func deletePlaylist(_ id: UUID) {
        if id == WallpaperPlaylist.presetID {
            guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
            playlists[index].enabled = false
            notice = "预设换壁纸任务会一直保留，已改为暂停。"
            persist()
            configureAutomations()
            return
        }
        playlists.removeAll { $0.id == id }
        if ensurePresetPlaylist() {
            notice = "已保留预设「随机」换壁纸任务。"
        }
        persist()
        configureAutomations()
    }

    /// Keep exactly one built-in all-library shuffle rule available.
    @discardableResult
    private func ensurePresetPlaylist() -> Bool {
        if playlists.contains(where: \.isPreset) { return false }
        if let index = playlists.firstIndex(where: { $0.source == .all && $0.sourceID == nil }) {
            let old = playlists[index]
            playlists[index] = WallpaperPlaylist(
                id: WallpaperPlaylist.presetID,
                name: old.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "随机" : old.name,
                source: .all,
                order: old.order,
                intervalSeconds: old.intervalSeconds,
                enabled: old.enabled,
                lastArtworkID: old.lastArtworkID,
                lastArtworkIDsByDisplay: old.lastArtworkIDsByDisplay,
                targetDisplayIDs: old.targetDisplayIDs,
                atmosphere: old.atmosphere,
                priority: old.priority ?? WallpaperPlaylist.minPriority
            )
            return true
        }
        playlists.insert(.libraryShufflePreset, at: 0)
        return true
    }

    func playPlaylistNow(
        _ id: UUID,
        excluding excludedID: UUID? = nil,
        displayIDs: [String]? = nil,
        respectPriority: Bool = true
    ) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        refreshDisplays()
        let playlist = playlists[index]
        let pool = artworks(for: playlist).filter { $0.id != excludedID }
        guard !pool.isEmpty else { notice = "这个轮播来源中还没有可用作品。"; return }
        let connected = displayProfiles.map(\.id)
        let available = playlist.resolvedTargetDisplayIDs(available: connected)
        let owned = WallpaperPlaylist.ownedDisplayIDs(for: playlist, among: playlists, available: connected)
        let scope = respectPriority ? owned : available
        let targets: [String]
        if let displayIDs, !displayIDs.isEmpty {
            targets = displayIDs.filter { scope.contains($0) }
        } else {
            targets = scope
        }
        if targets.isEmpty {
            if !respectPriority {
                notice = "找不到可用屏幕。"
            }
            return
        }

        var usedIDs = Set<UUID>()
        var assignments: [(displayID: String, path: String, recordID: UUID)] = []
        for displayID in targets {
            let currentID = playlist.lastArtworkID(on: displayID) ?? excludedID
            let preferFresh = pool.filter { !usedIDs.contains($0.id) }
            let candidates = preferFresh.isEmpty ? pool : preferFresh
            let next = pickPlaylistSuccessor(
                from: candidates,
                order: playlist.order,
                currentID: currentID ?? UUID()
            )
            guard let path = next.imagePath else { continue }
            usedIDs.insert(next.id)
            assignments.append((displayID: displayID, path: path, recordID: next.id))
        }
        guard !assignments.isEmpty else { return }
        enqueueWallpaperApply(
            assignments: assignments,
            adopt: false,
            playlistID: id,
            playlistName: playlist.name
        )
    }

    func playlistArtworkCount(_ playlist: WallpaperPlaylist) -> Int { artworks(for: playlist).count }

    func playlistSourceName(_ playlist: WallpaperPlaylist) -> String {
        switch playlist.source {
        case .all: return "全部作品"
        case .task: return channels.first(where: { $0.id == playlist.sourceID })?.name ?? "未选择任务"
        case .collection: return smartCollections.first(where: { $0.id == playlist.sourceID })?.name ?? "未选择作品集"
        }
    }

    /// Soft-delete: keep files, hide from library / playlists until restored or purged.
    func deleteRecord(_ id: UUID) {
        moveToTrash(id)
    }

    func moveToTrash(_ id: UUID, announce: Bool = true) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].trashedAt == nil else { return }
        records[index].trashedAt = Date()
        records[index].updatedAt = Date()
        detachArtworkReferences(id)
        removeFromActiveBatches(id)
        persist()
        refreshDesktopControls()
        if announce {
            notice = "已移入回收箱。可在作品集「回收箱」还原，或永久删除。"
        }
    }

    /// Drop a trashed/purged id from open batches and keep selection on a visible candidate.
    private func removeFromActiveBatches(_ id: UUID) {
        var preferredNext: UUID?
        if let batchIndex = batches.firstIndex(where: { $0.id == activeBatchID }),
           let position = batches[batchIndex].recordIDs.firstIndex(of: id) {
            let ids = batches[batchIndex].recordIDs
            if position + 1 < ids.count {
                preferredNext = ids[position + 1]
            } else if position > 0 {
                preferredNext = ids[position - 1]
            }
        }
        for index in batches.indices {
            batches[index].recordIDs.removeAll { $0 == id }
            if batches[index].selectedRecordID == id {
                batches[index].selectedRecordID = batches[index].recordIDs.first
            }
        }
        if selectedCandidateID == id || selectedCandidateID.map({ id in
            !activeCandidates.contains(where: { $0.id == id })
        }) == true {
            if let preferredNext, activeCandidates.contains(where: { $0.id == preferredNext }) {
                selectedCandidateID = preferredNext
            } else {
                selectedCandidateID = activeCandidates.first?.id ?? activeBatch?.selectedRecordID
            }
        }
    }

    func restoreFromTrash(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].trashedAt != nil else { return }
        records[index].trashedAt = nil
        records[index].updatedAt = Date()
        persist()
        refreshDesktopControls()
        notice = "已从回收箱还原。"
    }

    /// Permanent delete: remove record + disk files + tombstone stem.
    func purgeFromTrash(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        let path = record.imagePath
        detachArtworkReferences(id)
        records.removeAll { $0.id == id }
        removeFromActiveBatches(id)

        var deletedFiles = 0
        if let path {
            let stem = Self.fileStem(from: URL(fileURLWithPath: path).lastPathComponent)
            rememberDeletedStem(stem)
            deletedFiles = deleteArtworkFilesOnDisk(relatedTo: path)
        }
        persist()
        refreshDiskLibraryStats()
        refreshDesktopControls()
        if deletedFiles > 0 {
            notice = "已永久删除（\(deletedFiles) 个文件）。"
        } else {
            notice = "已永久删除这张图。"
        }
    }

    func emptyTrash() {
        let ids = trashedArtworks.map(\.id)
        guard !ids.isEmpty else {
            notice = "回收箱已经是空的。"
            return
        }
        for id in ids { purgeFromTrash(id) }
        notice = "已清空回收箱（\(ids.count) 张）。"
    }

    func revealArtworkInFinder(_ id: UUID, preferSource: Bool = false) {
        guard let record = records.first(where: { $0.id == id }) else {
            notice = "找不到这张作品。"
            return
        }
        let url: URL?
        if preferSource, let source = sourceImageURL(for: record) {
            url = source
        } else if let path = record.imagePath {
            url = URL(fileURLWithPath: path)
        } else {
            url = nil
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            notice = preferSource ? "找不到原图文件。" : "找不到壁纸文件。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func sourceImageURL(for record: GenerationRecord) -> URL? {
        guard let path = record.imagePath else { return nil }
        return Self.companionSourceURL(forWallpaperPath: path)
    }

    func hasDistinctSourceImage(_ record: GenerationRecord) -> Bool {
        guard let source = sourceImageURL(for: record)?.standardizedFileURL.path,
              let wallpaper = record.imagePath else { return false }
        return source != URL(fileURLWithPath: wallpaper).standardizedFileURL.path
    }

    private func detachArtworkReferences(_ id: UUID) {
        for index in channels.indices where channels[index].seedArtworkID == id {
            channels[index].seedArtworkID = nil
            channels[index].seedArtworkPath = nil
        }
        for index in playlists.indices {
            if playlists[index].lastArtworkID == id {
                playlists[index].lastArtworkID = nil
            }
            if var map = playlists[index].lastArtworkIDsByDisplay {
                let keys = map.filter { $0.value == id }.map(\.key)
                for key in keys { map.removeValue(forKey: key) }
                playlists[index].lastArtworkIDsByDisplay = map.isEmpty ? nil : map
            }
        }
        if settings.lastAppliedArtworkID == id {
            settings.lastAppliedArtworkID = nil
        }
        if var map = settings.lastAppliedArtworkIDsByDisplay {
            let keys = map.filter { $0.value == id }.map(\.key)
            for key in keys { map.removeValue(forKey: key) }
            settings.lastAppliedArtworkIDsByDisplay = map.isEmpty ? nil : map
        }
    }

    private func rememberDeletedStem(_ stem: String) {
        var stems = Set(settings.deletedArtworkStems ?? [])
        stems.insert(stem)
        // Bound growth; oldest stems drop first via sorted trim.
        settings.deletedArtworkStems = Array(stems).sorted().suffix(20_000).map { $0 }
    }

    /// Removes raw + wallpaper companion files that share the same stem.
    @discardableResult
    private func deleteArtworkFilesOnDisk(relatedTo path: String) -> Int {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let stem = Self.fileStem(from: url.lastPathComponent)
        WallpaperImageCache.shared.evict(path: path)

        let candidates: [URL]
        if let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates = files.filter { Self.fileStem(from: $0.lastPathComponent) == stem }
        } else {
            candidates = FileManager.default.fileExists(atPath: path) ? [url] : []
        }

        var removed = 0
        for file in candidates {
            WallpaperImageCache.shared.evict(path: file.path)
            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                // Keep trying the rest; tombstone still blocks reindex resurrection.
            }
        }
        return removed
    }

    /// Prefer the non-wallpaper companion next to a wallpaper file (the generation raw).
    static func companionSourceURL(forWallpaperPath path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let stem = fileStem(from: url.lastPathComponent)
        let name = url.lastPathComponent
        if !name.contains(".wallpaper-") {
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let companions = files.filter { file in
            let n = file.lastPathComponent
            guard fileStem(from: n) == stem else { return false }
            return !n.contains(".wallpaper-")
        }
        return companions.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    func deleteChannel(_ id: UUID) {
        channels.removeAll { $0.id == id }
        playlists.removeAll { $0.source == .task && $0.sourceID == id }
        if channels.isEmpty { channels = [.sample] }
        if selectedChannelID == id { selectChannel(channels.first?.id) }
        persist()
        configureAutomations()
        notice = "已删掉这个系列。图还在图库里，可以单独删。"
    }

    func saveSettings() {
        if settings.scheduledApplyMode == nil { settings.scheduledApplyMode = .review }
        if settings.scheduledSeriesID == nil { settings.scheduledSeriesID = selectedChannelID ?? channels.first?.id }
        settings.generateBeforeApplying = settings.scheduledApplyMode != .applyFirst
        settings.autoApply = settings.scheduledApplyMode == .applyFirst
        persist(); configureAutomations()
    }

    var launchAtLoginEnabled: Bool {
        LoginLaunchService.isEnabled
    }

    var launchAtLoginNeedsApproval: Bool {
        LoginLaunchService.needsApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginLaunchService.setEnabled(enabled)
            if LoginLaunchService.needsApproval {
                notice = "系统还需要你批准登录项。已打开「登录项」设置页。"
                LoginLaunchService.openLoginItemsSettings()
            } else {
                notice = enabled ? "已设为开机启动。登录后会自动打开 Musepaper。" : "已关闭开机启动。"
            }
            objectWillChange.send()
        } catch {
            notice = "开机启动设置失败：\(error.localizedDescription)。请把 App 放到「应用程序」后再试，或到系统设置 → 通用 → 登录项里手动添加。"
            LoginLaunchService.openLoginItemsSettings()
        }
    }

    func runScheduledGeneration(taskID: UUID? = nil) {
        if settings.skipWhenLowPower ?? true, ProcessInfo.processInfo.isLowPowerModeEnabled {
            notice = "已跳过自动生成：Mac 正处于低电量模式。"
            return
        }
        guard networkMonitor.isOnline || activeModelConfiguration?.provider == .demo else {
            notice = "已跳过自动生成：当前没有网络连接。"
            return
        }
        guard let seriesID = taskID ?? settings.scheduledSeriesID ?? selectedChannelID,
              let series = channels.first(where: { $0.id == seriesID }) else {
            notice = "自动出图已跳过：先给一个系列打开自动出图。"
            return
        }
        if isCreationBusy {
            enqueueScheduledTask(series.id)
            return
        }
        let produced = records.filter { $0.request.seriesID == series.id }.count
        let seed = (series.lastProducedAt.map { Int($0.timeIntervalSince1970) } ?? 0) &+ produced
        let refs = referencesForNextGeneration(seriesID: series.id, ignoreOptOut: true)
        var scheduledDraft = PromptDraft()
        scheduledDraft.mode = .inspiration
        scheduledDraft.treatment = .enhanced
        scheduledDraft.emptySpace = draft.emptySpace
        do {
            let baseline = try composer.resolve(draft: scheduledDraft, channel: series, display: selectedDisplay, seed: seed)
            let count = taskID == nil
                ? InspirationChannel.clampedCount(settings.scheduledCandidateCount ?? series.resolvedCandidateCount)
                : series.resolvedScheduledCandidateCount
            let batchID = beginPreparingBatch(trigger: .scheduled, seriesID: series.id, prompt: baseline)
            generationTotal = count
            generationIndex = 0
            notice = "到点了，正在接着「\(series.name)」上一张继续；每张画面都会不同。"
            startGeneration(
                prompt: baseline, trigger: .scheduled, variationSeed: seed,
                seriesID: series.id, candidateCount: count, rawInput: "",
                referenceImagePaths: refs, reuseBatchID: batchID
            )
        } catch { notice = error.localizedDescription }
    }

    private func updateRecord(_ id: UUID, state: GenerationState, path: String? = nil, error: String? = nil) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].state = state
        if let path { records[index].imagePath = path }
        records[index].errorMessage = error
        records[index].updatedAt = Date()
        if state == .ready { pruneHistory() }
        persist()
    }

    private func updateBatch(_ id: UUID, state: BatchState, error: String? = nil) {
        guard let index = batches.firstIndex(where: { $0.id == id }) else { return }
        batches[index].state = state
        batches[index].errorMessage = error
        persist()
    }

    private func load() async {
        do {
            snapshot = try await store.load()
            channels = snapshot.channels.isEmpty ? [.sample] : snapshot.channels.map { healedSeries($0) }
            records = snapshot.records.sorted { $0.updatedAt > $1.updatedAt }
            let removedMissing = scrubMissingArtworkRecords(persistAfter: false)
            for index in records.indices where records[index].resolvedTags.isEmpty {
                let task = records[index].request.seriesID.flatMap { id in channels.first { $0.id == id } }
                records[index].tags = artworkTagger.fallbackTags(prompt: records[index].request.resolvedPrompt, task: task)
                records[index].tagSummary = "已为旧作品补充本地策展标签"
            }
            backfillPromptSidecars()
            hydratePromptsFromSidecars()
            batches = (snapshot.batches ?? []).sorted { $0.createdAt > $1.createdAt }
            smartCollections = snapshot.smartCollections ?? []
            playlists = snapshot.playlists ?? []
            var shouldPersistBootstrap = ensurePresetPlaylist()
            settings = snapshot.settings
            if settings.wallpaperTransition == nil {
                settings.wallpaperTransition = WallpaperTransition.none
            } else if settings.wallpaperTransition != WallpaperTransition.none {
                // Desktop overlays were removed — keep stored value as none so UI/state agree.
                settings.wallpaperTransition = WallpaperTransition.none
            }
            // Tiny clock / corner buttons are OK with desktop interaction.
            if settings.desktopControlsEnabled == nil {
                settings.desktopControlsEnabled = true
            }
            // Atmosphere + pointer parallax — restore after temporary kill-switch.
            if settings.livingWallpaperEnabled == nil || settings.livingWallpaperEnabled == false {
                settings.livingWallpaperEnabled = true
            }
            if settings.livingWallpaperStyle == nil {
                settings.livingWallpaperStyle = .kenBurns
            }
            if settings.desktopClockEnabled == nil {
                settings.desktopClockEnabled = true
            }
            if settings.desktopClockFace == nil {
                settings.desktopClockFace = .desktop
            }
            if settings.desktopWeatherEnabled == nil {
                settings.desktopWeatherEnabled = true
            }
            if settings.desktopWeatherUnit == nil {
                settings.desktopWeatherUnit = .celsius
            }
            if let limit = settings.historyLimit, limit <= 200 {
                settings.historyLimit = 10_000
            } else if settings.historyLimit == nil {
                settings.historyLimit = 10_000
            }
            if settings.scheduledApplyMode == nil {
                settings.scheduledApplyMode = settings.autoApply && !settings.generateBeforeApplying ? .applyFirst : .review
            }
            if settings.scheduledSeriesID == nil { settings.scheduledSeriesID = settings.selectedChannelID ?? channels.first?.id }
            if let saved = snapshot.modelConfigurations, !saved.isEmpty {
                modelConfigurations = saved
            }
            // Missing prompt config: keep in-memory default but do NOT mark dirty for persist
            // unless something else already needs writing — avoids wiping antchat with openai.com.
            if let savedList = snapshot.promptModelConfigurations, !savedList.isEmpty {
                promptModelConfigurations = savedList.map { (try? $0.validated()) ?? $0 }
                if var routing = snapshot.promptAgentRouting {
                    routing.ensureConsistency(with: promptModelConfigurations)
                    promptAgentRouting = routing
                } else {
                    promptAgentRouting = PromptAgentRouting(
                        enabled: false,
                        mode: .fixed,
                        eligibleRefs: promptModelConfigurations.flatMap(\.agentModelRefs),
                        activeRef: promptModelConfigurations.flatMap(\.agentModelRefs).first
                    )
                }
            } else if let legacy = snapshot.promptModelConfiguration {
                let migrated = PromptAgentRouting.migrating(from: (try? legacy.validated()) ?? legacy)
                promptModelConfigurations = migrated.configs
                promptAgentRouting = migrated.routing
                shouldPersistBootstrap = true
            } else {
                promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
            }
            activeModelConfigurationID = snapshot.activeModelConfigurationID.flatMap { id in modelConfigurations.contains(where: { $0.id == id }) ? id : nil } ?? modelConfigurations.first?.id
            verifiedImageRoute = snapshot.verifiedImageRoute
            if let route = verifiedImageRoute,
               let config = activeModelConfiguration,
               route.matches(config)
            {
                verifiedConfigurationID = config.id
            } else if verifiedImageRoute != nil {
                // Stale lock from a previous host/model — don't pretend it's still verified.
                verifiedImageRoute = nil
                verifiedConfigurationID = nil
                shouldPersistBootstrap = true
            }
            selectedChannelID = settings.selectedChannelID
            if let channel = selectedChannel {
                batchSize = channel.resolvedCandidateCount
                let shown = restoredSeriesPrompt(channel)
                if !shown.isEmpty { draft.input = shown }
                syncCreationFocusToSeries(channel.id)
            } else {
                activeBatchID = batches.first(where: { $0.seriesID == nil })?.id ?? batches.first?.id
                selectedCandidateID = activeBatch?.selectedRecordID ?? activeBatch?.recordIDs.first
            }
            let imported = reindexLibraryFromDisk(persistAfter: false)
            refreshDisplays()
            refreshResolvedPrompt()
            configureAutomations()
            let loadedModelsFromDisk = !(snapshot.modelConfigurations ?? []).isEmpty
            let loadedPromptFromDisk = !(snapshot.promptModelConfigurations ?? []).isEmpty
                || snapshot.promptModelConfiguration != nil
            allowPersistingModelConfigurations = loadedModelsFromDisk || loadedPromptFromDisk
            var sizeBumpNotice: String?
            if loadedModelsFromDisk {
                var bumped = false
                for index in modelConfigurations.indices {
                    let preferred = OpenAIImageProvider.preferredSize(for: modelConfigurations[index])
                    if preferred != modelConfigurations[index].size {
                        modelConfigurations[index].size = preferred
                        bumped = true
                    }
                }
                if bumped {
                    shouldPersistBootstrap = true
                    sizeBumpNotice = "AntChat 出图尺寸已升到更高清（如 2048×1152），避免拉到大屏发糊"
                }
            }
            var reclaimedKeys = 0
            if loadedModelsFromDisk {
                var credentialTargets = modelConfigurations.filter { $0.provider != .demo }.map(\.id)
                credentialTargets.append(contentsOf: promptModelConfigurations.map(\.id))
                reclaimedKeys = (try? await credentials.reclaimOrphanedSecrets(for: credentialTargets)) ?? 0
            }
            await refreshKeyStatus()
            await refreshPromptKeyStatus()
            syncPromptModelsTextDraft()
            persistenceEnabled = true
            var notices: [String] = []
            if let loadNote = await store.lastLoadNote, !loadNote.isEmpty {
                notices.append(loadNote)
            }
            if let sizeBumpNotice { notices.append(sizeBumpNotice) }
            if reclaimedKeys > 0 {
                notices.append("已找回 \(reclaimedKeys) 个本机 API Key（配置 ID 变更后重新绑定）")
            }
            if removedMissing > 0 { notices.append("清理 \(removedMissing) 张丢失文件") }
            if imported > 0 { notices.append("从磁盘找回 \(imported) 张作品") }
            if removedMissing > 0 || imported > 0 || settings.historyLimit != snapshot.settings.historyLimit
                || reclaimedKeys > 0 || shouldPersistBootstrap
            {
                persist()
            }
            if !notices.isEmpty {
                notice = notices.joined(separator: "，") + "。"
            }
            startUpdateWatching()
        } catch {
            // Keep persistence disabled so defaults cannot overwrite a broken-but-precious file.
            persistenceEnabled = false
            notice = error.localizedDescription
        }
    }

    // MARK: - Update check

    func checkForUpdate(manual: Bool = false) {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        Task { @MainActor in
            defer { isCheckingUpdate = false }
            let result = await UpdateCheckService.shared.check()
            applyUpdateCheckResult(result, fromManual: manual)
        }
    }

    func openUpdateDownload() {
        guard let result = updateCheckResult, let url = preferredUpdateOpenURL(result) else {
            if let fallback = URL(string: "https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/index.html") {
                NSWorkspace.shared.open(fallback)
            }
            return
        }
        NSWorkspace.shared.open(url)
        markUpdateNoticeSeen(result.latest)
    }

    func dismissUpdateBanner() {
        guard let latest = updateCheckResult?.latest else {
            showsUpdateBanner = false
            return
        }
        settings.updateBannerDismissedVersion = latest
        settings.updateNoticeSeenVersion = latest
        showsUpdateBanner = false
        saveSettings()
        refreshMenuBar()
    }

    private func startUpdateWatching() {
        UpdateCheckService.shared.startWatching { [weak self] result in
            self?.applyUpdateCheckResult(result, fromManual: false)
        }
    }

    private func applyUpdateCheckResult(_ result: UpdateCheckResult, fromManual: Bool) {
        updateCheckResult = result
        showsUpdateBanner = shouldShowUpdateBanner(
            status: result.status,
            latest: result.latest,
            dismissedVersion: settings.updateBannerDismissedVersion
        )
        if fromManual {
            notice = result.message
        }
        if shouldNotifyUpdate(
            status: result.status,
            latest: result.latest,
            seenVersion: settings.updateNoticeSeenVersion
        ) {
            postUpdateUserNotification(result)
            markUpdateNoticeSeen(result.latest)
        }
        refreshMenuBar()
    }

    private func markUpdateNoticeSeen(_ latest: String?) {
        guard let latest, !latest.isEmpty else { return }
        if settings.updateNoticeSeenVersion != latest {
            settings.updateNoticeSeenVersion = latest
            saveSettings()
        }
    }

    private func postUpdateUserNotification(_ result: UpdateCheckResult) {
        guard result.status == .updateAvailable, let latest = result.latest else { return }
        let current = result.current
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let status = settings.authorizationStatus
            if status == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            } else if status != .authorized && status != .provisional {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Musepaper 有新版本 \(latest)"
            content.body = "当前 \(current)。打开应用下载页安装（不会静默替换）。"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "musepaper.update.\(latest)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    @discardableResult
    private func scrubMissingArtworkRecords(persistAfter: Bool = true) -> Int {
        let missingIDs = Set(records.filter { $0.imagePath != nil && !$0.hasUsableImageFile }.map(\.id))
        guard !missingIDs.isEmpty else { return 0 }
        for id in missingIDs {
            for index in channels.indices where channels[index].seedArtworkID == id {
                channels[index].seedArtworkID = nil
                channels[index].seedArtworkPath = nil
            }
        }
        records.removeAll { missingIDs.contains($0.id) }
        for index in batches.indices {
            batches[index].recordIDs.removeAll { missingIDs.contains($0) }
            if let selected = batches[index].selectedRecordID, missingIDs.contains(selected) {
                batches[index].selectedRecordID = batches[index].recordIDs.first
            }
        }
        if let selected = selectedCandidateID, missingIDs.contains(selected) {
            selectedCandidateID = activeBatch?.selectedRecordID
        }
        if persistAfter { persist() }
        return missingIDs.count
    }

    /// Pull wallpaper files that still sit on disk but were dropped from snapshot
    /// by the old tiny historyLimit. Also picks up raw files that never got a
    /// wallpaper companion so the catalog matches what still exists on disk.
    private func backfillPromptSidecars() {
        for record in records {
            guard let path = record.imagePath, !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            let final = record.finalPromptText
            guard !final.isEmpty else { continue }
            if looksLikeAssetFilename(final) { continue }
            if ArtworkPromptSidecar.read(nextTo: url) != nil { continue }
            ArtworkPromptSidecar.write(
                finalPrompt: final,
                rawInput: record.request.rawInput,
                negativePrompt: record.request.negativePrompt,
                coreKeywords: artworkCoreKeywords(record),
                nextTo: url
            )
        }
    }

    /// Prefer on-disk sidecar when the in-memory resolvedPrompt looks like a recovery placeholder.
    private func hydratePromptsFromSidecars() {
        for index in records.indices {
            guard let path = records[index].imagePath, !path.isEmpty else { continue }
            guard let payload = ArtworkPromptSidecar.read(nextTo: URL(fileURLWithPath: path)) else { continue }
            let final = payload.finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { continue }
            let current = records[index].request.resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || looksLikeAssetFilename(current) || current == "磁盘恢复" {
                records[index].request.resolvedPrompt = final
            }
            let core = payload.coreKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
            if !core.isEmpty {
                let existingCore = records[index].request.coreKeywords?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existingCore.isEmpty {
                    records[index].request.coreKeywords = core
                }
            }
            let raw = payload.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty,
               (records[index].request.rawInput == "磁盘恢复"
                || records[index].request.rawInput == "磁盘找回"
                || records[index].request.rawInput.isEmpty) {
                records[index].request.rawInput = raw
            }
            if records[index].request.negativePrompt.isEmpty, !payload.negativePrompt.isEmpty {
                records[index].request.negativePrompt = payload.negativePrompt
            }
        }
    }

    @discardableResult
    private func reindexLibraryFromDisk(persistAfter: Bool = true) -> Int {
        let directory = generationOutputDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else {
            refreshDiskLibraryStats(files: [])
            return 0
        }
        let knownPaths = Set(records.compactMap(\.imagePath))
        let knownIDs = Set(records.map(\.id))
        let deletedStems = Set(settings.deletedArtworkStems ?? [])
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            refreshDiskLibraryStats(files: [])
            return 0
        }
        refreshDiskLibraryStats(files: files)

        let wallpaperURLs = files.filter {
            let name = $0.lastPathComponent
            return name.contains(".wallpaper-") && name.lowercased().hasSuffix(".png")
        }
        let wallpaperStems = Set(wallpaperURLs.map { Self.fileStem(from: $0.lastPathComponent) })
        let rawOnlyURLs = files.filter {
            let name = $0.lastPathComponent
            guard name.lowercased().hasSuffix(".png"), !name.contains(".wallpaper-") else { return false }
            return !wallpaperStems.contains(Self.fileStem(from: name))
        }

        var added: [GenerationRecord] = []
        var seenIDs = knownIDs
        func appendRecord(url: URL, tag: String, summary: String) {
            let name = url.lastPathComponent
            let stem = Self.fileStem(from: name)
            if deletedStems.contains(stem) { return }
            if knownPaths.contains(url.path) { return }
            let recordID = Self.recordID(fromWallpaperFilename: name) ?? UUID()
            if seenIDs.contains(recordID) { return }
            seenIDs.insert(recordID)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let stamped = values?.creationDate ?? values?.contentModificationDate ?? Date()
            let sidecar = ArtworkPromptSidecar.read(nextTo: url)
            let recoveredFinal = sidecar?.finalPrompt.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let recoveredRaw = sidecar?.rawInput.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let recoveredCore = sidecar?.coreKeywords.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let request = GenerationRequest(
                id: UUID(),
                rawInput: recoveredRaw.isEmpty ? "磁盘恢复" : recoveredRaw,
                resolvedPrompt: recoveredFinal.isEmpty ? name : recoveredFinal,
                negativePrompt: sidecar?.negativePrompt ?? "",
                display: selectedDisplay,
                createdAt: stamped,
                referenceImagePaths: nil,
                batchID: nil,
                seriesID: nil,
                variationSeed: nil,
                coreKeywords: recoveredCore.isEmpty ? nil : recoveredCore
            )
            added.append(GenerationRecord(
                id: recordID,
                request: request,
                state: .ready,
                imagePath: url.path,
                isFavorite: false,
                feedback: nil,
                errorMessage: nil,
                updatedAt: stamped,
                tags: [tag],
                tagSummary: recoveredFinal.isEmpty ? summary : "已从旁路文件恢复最终 Prompt"
            ))
        }

        for url in wallpaperURLs {
            appendRecord(url: url, tag: "磁盘恢复", summary: "从 Pictures/Musepaper 重新收入作品集")
        }
        for url in rawOnlyURLs {
            appendRecord(url: url, tag: "原图", summary: "未适配壁纸版，已按原图收入")
        }

        guard !added.isEmpty else { return 0 }
        records.append(contentsOf: added)
        records.sort { $0.updatedAt > $1.updatedAt }
        if persistAfter { persist() }
        return added.count
    }

    private func refreshDiskLibraryStats(files: [URL]? = nil) {
        let listed: [URL]
        if let files {
            listed = files
        } else if FileManager.default.fileExists(atPath: generationOutputDirectory.path),
                  let fresh = try? FileManager.default.contentsOfDirectory(
                    at: generationOutputDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                  ) {
            listed = fresh
        } else {
            listed = []
        }
        let png = listed.filter { $0.pathExtension.lowercased() == "png" }
        diskWallpaperCount = png.filter { $0.lastPathComponent.contains(".wallpaper-") }.count
        diskRawCount = png.filter { !$0.lastPathComponent.contains(".wallpaper-") }.count
        diskTotalFileCount = png.count
    }

    private static func fileStem(from name: String) -> String {
        if let range = name.range(of: ".wallpaper-") {
            return String(name[..<range.lowerBound])
        }
        if name.hasSuffix(".prompt.json") {
            return String(name.dropLast(".prompt.json".count))
        }
        return (name as NSString).deletingPathExtension
    }

    private static func recordID(fromWallpaperFilename name: String) -> UUID? {
        let stem = fileStem(from: name)
        guard stem.count >= 36 else { return nil }
        return UUID(uuidString: String(stem.prefix(36)))
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplays()
                self?.refreshDesktopControls()
            }
        }
    }

    private func resolvedDesktopDisplayID(_ explicit: String?) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        return DisplayService.displayID(containing: NSEvent.mouseLocation)
    }

    private func usableWallpaperRecord(_ id: UUID) -> GenerationRecord? {
        records.first { $0.id == id && !$0.isTrashed && $0.hasUsableImageFile }
    }

    private func rememberAppliedAssignments(_ assignments: [(displayID: String, artworkID: UUID)]) {
        guard let last = assignments.last else { return }
        var map = settings.lastAppliedArtworkIDsByDisplay ?? [:]
        for item in assignments {
            map[item.displayID] = item.artworkID
        }
        settings.lastAppliedArtworkIDsByDisplay = map
        settings.lastAppliedArtworkID = last.artworkID
    }

    private func resolveCurrentWallpaperRecord() -> GenerationRecord? {
        resolveWallpaperRecord(on: resolvedDesktopDisplayID(nil))
    }

    /// Resolve the artwork on one screen. Never fall back to another screen's cursor.
    private func resolveWallpaperRecord(on displayID: String) -> GenerationRecord? {
        if let id = settings.lastAppliedArtworkIDsByDisplay?[displayID],
           let match = usableWallpaperRecord(id) {
            return match
        }
        if let running = owningPlaylist(for: displayID),
           let id = running.lastArtworkIDsByDisplay?[displayID],
           let match = usableWallpaperRecord(id) {
            return match
        }
        if let desktopPath = wallpaper.currentPaths()[displayID] {
            let standardized = URL(fileURLWithPath: desktopPath).standardizedFileURL.path
            if let match = records.first(where: { record in
                guard !record.isTrashed, let path = record.imagePath else { return false }
                return URL(fileURLWithPath: path).standardizedFileURL.path == standardized
            }) {
                return match
            }
        }
        if let id = settings.lastAppliedArtworkID, let match = usableWallpaperRecord(id) {
            let map = settings.lastAppliedArtworkIDsByDisplay ?? [:]
            let ownedByOther = map.contains { $0.key != displayID && $0.value == id }
            if !ownedByOther, map[displayID] == nil {
                return match
            }
        }
        return nil
    }

    private func isLikedDesktopWallpaper(_ record: GenerationRecord) -> Bool {
        record.isFavorite || record.resolvedTags.contains(DesktopControlOverlay.likedTag)
    }

    private func refreshDesktopControls() {
        let likedByDisplay = Dictionary(uniqueKeysWithValues: displayProfiles.map { profile in
            (profile.id, resolveWallpaperRecord(on: profile.id).map(isLikedDesktopWallpaper) ?? false)
        })
        desktopControls.update(
            enabled: settings.desktopControlsEnabled ?? true,
            likedByDisplay: likedByDisplay,
            onLike: { [weak self] id in self?.likeCurrentDesktopWallpaper(displayID: id) },
            onNext: { [weak self] id in self?.playNextDesktopWallpaper(displayID: id) },
            onDelete: { [weak self] id in self?.deleteCurrentDesktopWallpaper(displayID: id) }
        )
        refreshLivingWallpaper()
        refreshDesktopPresence()
        refreshMenuBar()
    }

    private func owningPlaylist(for displayID: String) -> WallpaperPlaylist? {
        WallpaperPlaylist.owner(
            of: displayID,
            among: playlists,
            available: displayProfiles.map(\.id)
        )
    }

    private func leadingOwningPlaylist() -> WallpaperPlaylist? {
        for profile in displayProfiles {
            if let owner = owningPlaylist(for: profile.id) { return owner }
        }
        return rankedPlaylists.first { $0.enabled }
    }

    private func refreshLivingWallpaper() {
        let globalEnabled = settings.livingWallpaperEnabled ?? true
        let globalStyle = settings.livingWallpaperStyle ?? .kenBurns
        let config: (enabled: Bool, style: LivingWallpaperStyle)
        if let running = leadingOwningPlaylist() {
            config = running.resolvedAtmosphere.resolved(
                globalEnabled: globalEnabled,
                globalStyle: globalStyle
            )
        } else {
            config = (globalEnabled, globalStyle.resolvedMotion)
        }
        livingWallpaper.update(enabled: config.enabled, style: config.style)
    }

    private func refreshDesktopPresence() {
        let clockOn = settings.desktopClockEnabled ?? true
        let weatherOn = settings.desktopWeatherEnabled ?? true
        let face = settings.desktopClockFace ?? .desktop
        let unit = settings.desktopWeatherUnit ?? .celsius
        desktopClock.update(
            enabled: clockOn,
            face: face,
            weatherEnabled: weatherOn,
            weatherUnit: unit,
            weatherCity: settings.desktopWeatherCity ?? ""
        )
        // Weather is merged into the clock panel.
        desktopWeather.hide()
    }

    func setDesktopClockEnabled(_ enabled: Bool) {
        settings.desktopClockEnabled = enabled
        saveSettings()
        refreshDesktopPresence()
    }

    func setDesktopClockFace(_ face: DesktopClockFace) {
        settings.desktopClockFace = face
        saveSettings()
        refreshDesktopPresence()
    }

    func setDesktopWeatherEnabled(_ enabled: Bool) {
        settings.desktopWeatherEnabled = enabled
        saveSettings()
        refreshDesktopPresence()
    }

    func setDesktopWeatherUnit(_ unit: WeatherTemperatureUnit) {
        settings.desktopWeatherUnit = unit
        saveSettings()
        refreshDesktopPresence()
    }

    func setDesktopWeatherCity(_ city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.desktopWeatherCity = trimmed.isEmpty ? nil : trimmed
        weatherCityDebounceTask?.cancel()
        weatherCityDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            saveSettings()
            refreshDesktopPresence()
        }
    }

    private func persistSoon() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        guard persistenceEnabled else { return }
        // Never write an empty series list — that irreversibly drops user tasks.
        if channels.isEmpty {
            channels = [.sample]
        }
        snapshot.channels = channels
        snapshot.records = records
        snapshot.settings = settings
        if allowPersistingModelConfigurations {
            snapshot.modelConfigurations = modelConfigurations
            snapshot.activeModelConfigurationID = activeModelConfigurationID
            snapshot.verifiedImageRoute = verifiedImageRoute
            snapshot.promptModelConfigurations = promptModelConfigurations
            snapshot.promptAgentRouting = promptAgentRouting
            // Stop rewriting the legacy single-config field once multi-config is in use.
            snapshot.promptModelConfiguration = nil
        }
        snapshot.batches = batches
        snapshot.smartCollections = smartCollections
        snapshot.playlists = playlists
        persistGeneration += 1
        let generation = persistGeneration
        let value = snapshot
        Task {
            guard generation == persistGeneration else { return }
            do {
                try await store.save(value)
            } catch {
                await MainActor.run {
                    notice = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshKeyStatus() async {
        guard let config = activeModelConfiguration else {
            apiKeyConfigured = false; return
        }
        if config.provider == .demo {
            apiKeyConfigured = true; return
        }
        if await credentials.contains(config.id) {
            apiKeyConfigured = true
            return
        }
        // Config IDs can churn after a bad save; reclaim leftover secrets.
        var targets = modelConfigurations.filter { $0.provider != .demo }.map(\.id)
        targets.append(contentsOf: promptModelConfigurations.map(\.id))
        _ = try? await credentials.reclaimOrphanedSecrets(for: targets)
        apiKeyConfigured = await credentials.contains(config.id)
    }

    private func refreshPromptKeyStatus() async {
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        if let active = activePromptModelConfiguration {
            activePromptAPIKeyConfigured = await promptHasUsableAPIKey(active)
        } else {
            activePromptAPIKeyConfigured = false
        }
        let eligibleRefs = promptAgentRouting.eligibleRefs
        let checkConfigs: [PromptModelConfiguration]
        switch promptAgentRouting.mode {
        case .fixed:
            if let active = promptAgentRouting.activeRef,
               let config = promptModelConfigurations.first(where: { $0.id == active.configurationID }) {
                checkConfigs = [config]
            } else {
                checkConfigs = eligibleRefs.compactMap { ref in
                    promptModelConfigurations.first { $0.id == ref.configurationID }
                }
            }
        case .random:
            let refs = eligibleRefs.isEmpty
                ? promptModelConfigurations.flatMap(\.agentModelRefs)
                : eligibleRefs
            var seen = Set<UUID>()
            checkConfigs = refs.compactMap { ref in
                guard seen.insert(ref.configurationID).inserted else { return nil }
                return promptModelConfigurations.first { $0.id == ref.configurationID }
            }
        }
        for config in checkConfigs {
            if await promptHasUsableAPIKey(config) {
                promptAPIKeyConfigured = true
                return
            }
        }
        var targets = modelConfigurations.filter { $0.provider != .demo }.map(\.id)
        targets.append(contentsOf: promptModelConfigurations.map(\.id))
        _ = try? await credentials.reclaimOrphanedSecrets(for: targets)
        if let active = activePromptModelConfiguration {
            activePromptAPIKeyConfigured = await promptHasUsableAPIKey(active)
        }
        for config in checkConfigs {
            if await promptHasUsableAPIKey(config) {
                promptAPIKeyConfigured = true
                return
            }
        }
        promptAPIKeyConfigured = false
    }

    private func promptConfigsSharingCredential(with config: PromptModelConfiguration) -> [PromptModelConfiguration] {
        let key = config.credentialAffinityKey
        guard !key.isEmpty else { return [config] }
        let matched = promptModelConfigurations.filter { $0.credentialAffinityKey == key }
        return matched.isEmpty ? [config] : matched
    }

    private func promptHasUsableAPIKey(_ config: PromptModelConfiguration) async -> Bool {
        (try? await readPromptAPIKey(for: config))?.isEmpty == false
    }

    private func readPromptAPIKey(for config: PromptModelConfiguration) async throws -> String? {
        if let key = try await credentials.read(for: config.id), !key.isEmpty {
            return key
        }
        for sibling in promptConfigsSharingCredential(with: config) where sibling.id != config.id {
            if let key = try await credentials.read(for: sibling.id), !key.isEmpty {
                return key
            }
        }
        return nil
    }

    private func savePromptAPIKey(_ key: String, for config: PromptModelConfiguration) async throws {
        for target in promptConfigsSharingCredential(with: config) {
            try await credentials.save(key, for: target.id)
        }
    }

    private func deletePromptAPIKey(for config: PromptModelConfiguration) async throws {
        for target in promptConfigsSharingCredential(with: config) {
            try await credentials.delete(for: target.id)
        }
    }

    private func promptEnhancementContext(
        seed: Int? = nil,
        deterministic: String? = nil,
        channel: InspirationChannel? = nil,
        idea: String? = nil,
        dimensionCombo: String = ""
    ) -> PromptEnhancementContext {
        let resolvedChannel = (channel ?? selectedChannel).flatMap { $0.isSchemaTemplate ? nil : $0 }
        let raw = composer.userCore(idea: idea ?? draft.input, channel: resolvedChannel)
        var exclusions = [draft.negative, resolvedChannel?.exclude ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "、")
        // Figure and mood themes must not inherit legacy series defaults that ban 人物.
        if composer.allowsVisibleFigure(raw) {
            exclusions = exclusions
                .split(whereSeparator: { "、,，;；/".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { value in
                    let compact = value.replacingOccurrences(of: " ", with: "")
                    return !["人物", "人像", "人", "people", "person", "human"].contains(compact.lowercased())
                }
                .joined(separator: "、")
        }
        return PromptEnhancementContext(
            rawPrompt: raw,
            deterministicPrompt: composer.usableVisual(deterministic ?? finalPrompt) ?? raw,
            channelName: composer.usableVisual(resolvedChannel?.name ?? ""),
            channelEssence: composer.usableVisual(resolvedChannel?.essence ?? ""),
            requiredElements: composer.usableVisual(resolvedChannel?.mustInclude ?? ""),
            excludedElements: exclusions,
            palette: composer.usableVisual(resolvedChannel?.palette ?? ""),
            emptySpace: draft.emptySpace.rawValue,
            displayWidth: selectedDisplay.width,
            displayHeight: selectedDisplay.height,
            referenceImageCount: displayedReferencePaths.count,
            coreKeywords: raw,
            variationAxes: composer.usableVisual(resolvedChannel?.resolvedVariationAxes ?? "") ?? "",
            variationSeed: seed,
            promptStrategy: resolvedChannel?.resolvedPromptStrategy.rawValue,
            dimensionCombo: composer.usableVisual(dimensionCombo) ?? ""
        )
    }

    private func resolvePromptModelConfiguration() async -> PromptModelConfiguration? {
        guard promptAgentRouting.enabled else { return nil }
        promptAgentRouting.ensureConsistency(with: promptModelConfigurations)
        let byID = Dictionary(uniqueKeysWithValues: promptModelConfigurations.map { ($0.id, $0) })
        let pool: [PromptAgentModelRef]
        switch promptAgentRouting.mode {
        case .fixed:
            if let active = promptAgentRouting.activeRef {
                pool = [active]
            } else {
                pool = promptAgentRouting.eligibleRefs
            }
        case .random:
            pool = promptAgentRouting.eligibleRefs.isEmpty
                ? promptModelConfigurations.flatMap(\.agentModelRefs)
                : promptAgentRouting.eligibleRefs
        }
        var keyed: [(PromptModelConfiguration, String)] = []
        for ref in pool {
            guard let config = byID[ref.configurationID] else { continue }
            guard await promptHasUsableAPIKey(config) else { continue }
            keyed.append((config, ref.model))
        }
        guard let pick = (promptAgentRouting.mode == .fixed ? keyed.first : keyed.randomElement()) else {
            return nil
        }
        return pick.0.withSelectedModel(pick.1)
    }

    private func makePromptAgentIfAvailable() async -> PromptAgent? {
        guard let configuration = await resolvePromptModelConfiguration() else { return nil }
        do {
            guard let key = try await readPromptAPIKey(for: configuration), !key.isEmpty else {
                return nil
            }
            let agent = try PromptAgent(configuration: configuration, apiKey: key)
            lastUsedPromptModelName = configuration.selectionLabel(forModel: configuration.model)
            return agent
        } catch {
            promptAgentNotice = error.localizedDescription
            return nil
        }
    }

    private func enrichTags(_ ids: [UUID], task: InspirationChannel?) async {
        guard promptAgentRouting.enabled, promptAPIKeyConfigured else { return }
        guard let agent = await makePromptAgentIfAvailable() else { return }
        let usedName = lastUsedPromptModelName ?? agent.configuration.model
        let gate = AdaptiveConcurrencyGate(
            initial: min(4, ids.count),
            minimum: 1,
            maximum: min(6, max(1, ids.count))
        )

        struct EnrichWork: Sendable {
            let id: UUID
            let tags: [String]
            let summary: String
        }

        do {
            try await withThrowingTaskGroup(of: EnrichWork?.self) { group in
                for id in ids {
                    guard let index = records.firstIndex(where: { $0.id == id }) else { continue }
                    let prompt = records[index].request.resolvedPrompt
                    let path = records[index].imagePath
                    group.addTask {
                        let jpeg: Data? = await Task.detached(priority: .utility) {
                            guard let path, !path.isEmpty else { return nil }
                            return WallpaperImageCache.jpegThumbnail(path: path, maxPixel: 512, quality: 0.55)
                        }.value
                        let tags = try await gate.runWithPressureRetry {
                            try await agent.suggestTags(prompt: prompt, taskName: task?.name, imageJPEG: jpeg)
                        }
                        return EnrichWork(
                            id: id,
                            tags: tags,
                            summary: jpeg == nil
                                ? "由 \(usedName) 自动标注"
                                : "由 \(usedName) 看图标注（压缩预览）"
                        )
                    }
                }
                for try await work in group {
                    guard let work, let index = records.firstIndex(where: { $0.id == work.id }) else { continue }
                    records[index].tags = work.tags
                    records[index].tagSummary = work.summary
                    persist()
                }
            }
        } catch {
            promptAgentNotice = "作品已使用本地标签；AI 标签暂不可用：\(error.localizedDescription)"
        }
    }

    private func artworks(for playlist: WallpaperPlaylist) -> [GenerationRecord] {
        let available = usableArtworks
        switch playlist.source {
        case .all: return available
        case .task: return available.filter { $0.request.seriesID == playlist.sourceID }
        case .collection:
            guard let collection = smartCollections.first(where: { $0.id == playlist.sourceID }) else { return [] }
            return available.filter { collection.includes($0) }
        }
    }

    private func configureAutomations() {
        for channel in channels where channel.resolvedScheduleEnabled {
            syncSeriesTimeline(channel.id)
        }
        scheduler.configure(tasks: channels) { [weak self] taskID in self?.runScheduledGeneration(taskID: taskID) }
        let hasTaskSchedule = channels.contains(where: \.resolvedScheduleEnabled)
        if settings.scheduleEnabled && !hasTaskSchedule {
            scheduler.configure(settings: settings) { [weak self] in self?.runScheduledGeneration() }
        }
        playback.configure(playlists: playlists) { [weak self] playlistID in self?.playPlaylistNow(playlistID) }
        refreshMenuBar()
        refreshDesktopControls()
    }

    private func refreshMenuBar() {
        let upcoming = channels
            .filter(\.resolvedScheduleEnabled)
            .map { task in
                (
                    task: task,
                    date: ScheduleService.nextFireDate(
                        intervalSeconds: task.resolvedScheduleIntervalSeconds,
                        lastProducedAt: effectiveLastProducedAt(for: task)
                    )
                )
            }
            .sorted { $0.date < $1.date }
            .first
        let idea = draft.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = selectedChannel?.name ?? (idea.isEmpty ? nil : "这次的想法")
        let current = resolveCurrentWallpaperRecord()
        let liked = current.map(isLikedDesktopWallpaper) ?? false
        menuBar.update(
            currentTaskName: currentName,
            nextTaskName: upcoming?.task.name,
            nextCaption: upcoming.map {
                ScheduleService.nextFireCaption(
                    intervalSeconds: $0.task.resolvedScheduleIntervalSeconds,
                    lastProducedAt: effectiveLastProducedAt(for: $0.task)
                )
            },
            playlistRunning: playlists.contains(where: \.enabled),
            likedCurrent: liked,
            updateAvailableVersion: updateCheckResult?.status == .updateAvailable ? updateCheckResult?.latest : nil,
            onGenerateNow: { [weak self] in self?.requestGeneration() },
            onLike: { [weak self] in self?.likeCurrentDesktopWallpaper() },
            onNext: { [weak self] in self?.playNextDesktopWallpaper() },
            onDelete: { [weak self] in self?.deleteCurrentDesktopWallpaper() },
            onOpenUpdate: { [weak self] in self?.openUpdateDownload() },
            onCheckUpdate: { [weak self] in self?.checkForUpdate(manual: true) }
        )
    }

    private func pruneHistory() {
        // Wallpaper library should keep a long local history. Old builds capped at 200
        // and quietly dropped thousands of still-present files from the catalog.
        let limit = min(max(settings.historyLimit ?? 10_000, 100), 50_000)
        guard records.count > limit else { return }
        let favorites = records.filter(\.isFavorite)
        let favoriteIDs = Set(favorites.map(\.id))
        let remaining = records.filter { !favoriteIDs.contains($0.id) }.prefix(max(0, limit - favorites.count))
        records = (favorites + remaining).sorted { $0.updatedAt > $1.updatedAt }
        let surviving = Set(records.map(\.id))
        batches = batches.compactMap { batch in
            var updated = batch
            updated.recordIDs = batch.recordIDs.filter { surviving.contains($0) }
            if let selected = updated.selectedRecordID, !surviving.contains(selected) { updated.selectedRecordID = updated.recordIDs.first }
            return updated.recordIDs.isEmpty && updated.state == .ready ? nil : updated
        }
    }
}
