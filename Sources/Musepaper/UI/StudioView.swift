import AppKit
import SwiftUI

struct StudioView: View {
    private enum Page { case create, library, playlists, settings }

    @StateObject var model = StudioViewModel()
    @State private var page: Page = .create
    @State private var showingCollectionEditor = false
    @State private var playlistEditorTarget: PlaylistEditorTarget?
    @State private var showingScheduleFor: UUID?
    @State private var showingReferencePicker = false
    @State private var lightboxArtworkID: UUID?
    @State private var imageAPIExpanded = true
    @State private var agentAPIExpanded = true
    @State private var desktopChromeExpanded = false
    @State private var libraryTagsExpanded = false
    @State private var renamingSeriesID: UUID?
    @State private var seriesRenameDraft = ""
    @FocusState private var seriesRenameFocused: Bool
    @FocusState private var composerFocused: Bool

    /// Hard vertical contract for 生图 — never rely on layoutPriority alone.
    /// Dock + film are fixed; preview gets whatever remains. This prevents the
    /// infinity-sized preview from shoving prompt/actions off-screen again.
    private enum CreationLayout {
        static let dockHeight: CGFloat = 108
        static let bannerHeight: CGFloat = 26
        static let filmHeight: CGFloat = 78
        static let filmTileWidth: CGFloat = 102
        static let promptHeight: CGFloat = 34
        static let actionHeight: CGFloat = 34
        static let controlRowHeight: CGFloat = 28
    }

    var body: some View {
        ZStack {
            MuseBackdrop()
            VStack(spacing: 0) {
                topBar
                if model.showsUpdateBanner, let update = model.updateCheckResult, update.status == .updateAvailable {
                    updateBanner(update)
                }
                HStack(spacing: 0) {
                    if page == .create {
                        seriesRail
                    }
                    Group {
                        switch page {
                        case .create: creationPage
                        case .library: libraryPage
                        case .playlists: playlistsPage
                        case .settings: settingsPage
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if lightboxArtworkID != nil {
                LibraryLightboxView(model: model, artworkID: $lightboxArtworkID) { id in
                    model.useArtworkAsReference(id)
                    lightboxArtworkID = nil
                    page = .create
                }
            }
            CandidateShortcutMonitor(
                enabled: page == .create && lightboxArtworkID == nil && model.activeCandidates.count > 1,
                onLeft: { model.selectAdjacentCandidate(-1) },
                onRight: { model.selectAdjacentCandidate(1) }
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(minWidth: 1100, minHeight: 800)
        .preferredColorScheme(.dark)
        .tint(MuseTheme.amber)
        .sheet(isPresented: $showingCollectionEditor) {
            CollectionEditor(tasks: model.channels, availableTags: model.allArtworkTags) { model.saveCollection($0) }
        }
        .sheet(item: $playlistEditorTarget) { target in
            PlaylistEditor(
                playlist: target.playlist,
                tasks: model.channels,
                collections: model.smartCollections,
                displays: model.displayProfiles
            ) { playlist in
                model.savePlaylist(playlist)
                playlistEditorTarget = nil
            }
            .onAppear { model.refreshDisplays() }
        }
        .sheet(isPresented: Binding(
            get: { showingScheduleFor != nil },
            set: { if !$0 { showingScheduleFor = nil } }
        )) {
            ScheduleEditorSheet(
                channelID: showingScheduleFor,
                model: model,
                onDone: { showingScheduleFor = nil }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .musepaperOpenSettings)) { _ in
            page = .settings
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(MuseTheme.amber)
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 10, weight: .black)).foregroundStyle(.black))
                Text("Musepaper")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(MuseTheme.ink)
            }

            HStack(spacing: 2) {
                topTab("生图", target: .create)
                topTab("自动换壁纸", target: .playlists)
                topTab("作品集", target: .library)
                topTab("设置", target: .settings)
            }

            Spacer(minLength: 12)

            if model.updateCheckResult?.status == .updateAvailable, let latest = model.updateCheckResult?.latest {
                Button {
                    model.openUpdateDownload()
                } label: {
                    Text("↑ 更新 \(latest)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(MuseTheme.amber))
                }
                .buttonStyle(.plain)
                .help("有新版本，点击下载本机芯片对应安装包")
                .contextMenu {
                    Button("打开设置 · 关于") { page = .settings }
                    Button("稍后提醒") { model.dismissUpdateBanner() }
                }
            }

            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                page = .settings
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.connectionBadgeIsReady ? MuseTheme.moss : MuseTheme.amber)
                        .frame(width: 7, height: 7)
                    Text(model.connectionBadgeTitle)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(MuseTheme.muted)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().stroke(MuseTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("连接状态 · 点此打开设置")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .zIndex(2)
        .background(MuseTheme.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MuseTheme.border).frame(height: 1)
        }
    }

    private func updateBanner(_ update: UpdateCheckResult) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("有新版本 \(update.latest ?? "")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuseTheme.ink)
                Text("当前 \(update.current) · 浏览器下载后按芯片安装（不会静默替换）")
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.muted)
                if !update.highlights.isEmpty {
                    Text(update.highlights.prefix(3).map { "· \($0)" }.joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(MuseTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button("更新") { model.openUpdateDownload() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("详情") { page = .settings }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("稍后") { model.dismissUpdateBanner() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MuseTheme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MuseTheme.amber.opacity(0.45)).frame(height: 1)
        }
    }

    private func topTab(_ title: String, target: Page) -> some View {
        Button(title) {
            NSApp.keyWindow?.makeFirstResponder(nil)
            page = target
        }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: page == target ? .semibold : .medium))
            .foregroundStyle(page == target ? MuseTheme.ink : MuseTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(page == target ? MuseTheme.amber : .clear)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
    }

    // MARK: - Creation

    private var creationPage: some View {
        GeometryReader { geo in
            let bannerH = creationWorkbenchBanner == nil ? 0 : CreationLayout.bannerHeight
            let filmH = model.hasActiveResults ? CreationLayout.filmHeight : 0
            let dockH = CreationLayout.dockHeight + bannerH
            let previewH = max(160, geo.size.height - filmH - dockH)

            VStack(spacing: 0) {
                largeImagePane
                    .frame(width: geo.size.width, height: previewH)
                    .clipped()

                if model.hasActiveResults {
                    candidateFilmstrip
                        .padding(.horizontal, 12)
                        .frame(width: geo.size.width, height: filmH)
                        .background(Color.black.opacity(0.32))
                }

                workbench
                    .frame(width: geo.size.width, height: dockH, alignment: .top)
                    .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var creationWorkbenchBanner: String? {
        if !model.canGenerate, !model.isCreationBusy {
            return model.generationBlockReason
        }
        if model.creatingTaskFromComposer, let reason = model.generationBlockReason, !model.isCreationBusy {
            return reason
        }
        if !model.isCreationBusy, let notice = model.notice, model.shouldSurfaceCreationNotice {
            return notice
        }
        return nil
    }

    private var seriesRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("系列")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(MuseTheme.muted)
                Spacer(minLength: 0)
                Button {
                    model.beginNewSeries()
                    page = .create
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MuseTheme.ink)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("新开一个系列：写下画面，再点出图")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    newIdeaButton
                    ForEach(model.channels) { channel in
                        moodButton(
                            id: channel.id,
                            title: channel.name,
                            subtitle: seriesSubtitle(channel),
                            icon: channel.resolvedScheduleEnabled ? "clock.badge.checkmark" : "scope"
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MuseTheme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(MuseTheme.border).frame(width: 1) }
    }

    private var newIdeaButton: some View {
        let selected = model.selectedChannelID == nil
        return Button {
            model.startNewIdea()
            page = .create
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? MuseTheme.amber : MuseTheme.muted)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("新系列")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MuseTheme.ink)
                        .lineLimit(1)
                    Text("写一句再出图")
                        .font(.system(size: 10))
                        .foregroundStyle(MuseTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? MuseTheme.amber.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? MuseTheme.amber.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("新开一个系列：写下画面，再点出图")
    }

    private func seriesSubtitle(_ channel: InspirationChannel) -> String {
        let count = model.seriesArtworkCount(channel)
        if channel.resolvedScheduleEnabled {
            return count > 0 ? "定时 · \(count) 张" : "定时"
        }
        return count > 0 ? "\(count) 张" : "还没出图"
    }

    private func beginSeriesRename(_ channel: InspirationChannel) {
        model.selectChannel(channel.id)
        page = .create
        renamingSeriesID = channel.id
        seriesRenameDraft = channel.name
        seriesRenameFocused = true
    }

    private func commitSeriesRename() {
        guard let id = renamingSeriesID else { return }
        model.renameChannel(id, to: seriesRenameDraft)
        renamingSeriesID = nil
        seriesRenameFocused = false
    }

    private func moodButton(id: UUID?, title: String, subtitle: String, icon: String) -> some View {
        let selected = model.selectedChannelID == id
        let channel = id.flatMap { taskID in model.channels.first { $0.id == taskID } }
        let renaming = id != nil && renamingSeriesID == id
        return Button {
            if renaming { return }
            model.selectChannel(id)
            page = .create
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(selected ? MuseTheme.amber : MuseTheme.muted)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    if renaming {
                        TextField("系列名", text: $seriesRenameDraft)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MuseTheme.ink)
                            .textFieldStyle(.plain)
                            .focused($seriesRenameFocused)
                            .onSubmit { commitSeriesRename() }
                            .onChange(of: seriesRenameFocused) { _, focused in
                                if !focused { commitSeriesRename() }
                            }
                    } else {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MuseTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MuseTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let channel, channel.resolvedScheduleEnabled, !renaming {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MuseTheme.amber.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? MuseTheme.amber.opacity(0.14) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(MuseTheme.amber)
                        .frame(width: 3, height: 22)
                        .padding(.leading, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(renaming ? "回车保存名字" : title)
        .contextMenu {
            if let channel {
                Button("改名字") { beginSeriesRename(channel) }
                Button("自动出图") {
                    model.selectChannel(channel.id)
                    showingScheduleFor = channel.id
                }
                Button("删除这个系列", role: .destructive) { model.deleteChannel(channel.id) }
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard let channel else { return }
            beginSeriesRename(channel)
        })
    }

    private var workbench: some View {
        VStack(spacing: 0) {
            if let banner = creationWorkbenchBanner {
                Text(banner)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MuseTheme.amber)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: CreationLayout.bannerHeight)
                    .background(MuseTheme.amber.opacity(0.10))
            }

            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        if model.draft.input.isEmpty {
                            Text(composerPlaceholder)
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(MuseTheme.muted)
                                .padding(.horizontal, 10)
                                .lineLimit(1)
                        }
                        TextField("", text: $model.draft.input)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(MuseTheme.ink)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .focused($composerFocused)
                            .onChange(of: model.draft.input) { _, _ in
                                model.draftInputDidChange()
                            }
                            .onChange(of: model.shouldFocusComposer) { _, focus in
                                guard focus else { return }
                                composerFocused = true
                                model.shouldFocusComposer = false
                            }
                    }
                    .frame(height: CreationLayout.promptHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MuseTheme.field)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MuseTheme.border, lineWidth: 1)
                    )

                    generateButton
                        .frame(width: 132, height: CreationLayout.actionHeight)

                    if !model.activeCandidates.isEmpty {
                        Button { model.applySelectedCandidate() } label: {
                            Text("设为壁纸")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .frame(width: 100, height: CreationLayout.actionHeight)
                        .disabled(!model.canApplySelected)
                    }
                }

                HStack(spacing: 8) {
                    Picker("文生图模型", selection: Binding(
                        get: { model.activeModelConfigurationID ?? model.modelConfigurations.first?.id ?? UUID() },
                        set: { model.selectModelConfiguration($0) }
                    )) {
                        ForEach(model.modelConfigurations) { configuration in
                            Text(model.imageModelPickerTitle(for: configuration)).tag(configuration.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 190, alignment: .leading)

                    CompactCountField(
                        value: model.batchSize,
                        onChange: { model.setBatchSize($0) }
                    )

                    if model.activeModelConfiguration?.provider != .demo {
                        Picker("尺寸", selection: Binding(
                            get: { model.activeModelConfiguration?.size ?? .qwenLandscapeHD },
                            set: { model.setActiveImageSize($0) }
                        )) {
                            ForEach(GeneratedImageSize.menuOrdered) { Text($0.menuLabel).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170, alignment: .leading)

                        Picker("质量", selection: Binding(
                            get: { model.activeModelConfiguration?.quality ?? .high },
                            set: { model.setActiveImageQuality($0) }
                        )) {
                            ForEach(ImageQuality.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 72, alignment: .leading)

                        Toggle("Agent", isOn: Binding(
                            get: { model.promptAgentRouting.enabled },
                            set: { model.setPromptAgentEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.caption.weight(.semibold))
                    }

                    Toggle("参考图", isOn: Binding(
                        get: { model.useReferenceImages },
                        set: { model.setUseReferenceImages($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption.weight(.semibold))

                    if model.useReferenceImages {
                        ForEach(model.displayedReferencePaths.prefix(2), id: \.self) { path in
                            CachedWallpaperImage(path: path, role: .thumbnail)
                                .frame(width: 26, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Button("换") { showingReferencePicker = true }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MuseTheme.amber)
                    }

                    if let channel = model.selectedChannel {
                        scheduleChip(channel)
                    }

                    WallpaperTargetPicker(model: model, width: 120)

                    Spacer(minLength: 6)

                    if !model.activeCandidates.isEmpty {
                        Button {
                            model.regenerateSelectedCandidate()
                        } label: {
                            Text(model.isGenerating && model.generationTotal == 1 ? "重出中…" : "重新生成")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MuseTheme.muted)
                        .disabled(!model.canRegenerateSelected)

                        if model.canApplySelected {
                            Button("按这张再出") { model.continueFromSelected() }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MuseTheme.muted)
                                .disabled(model.isCreationBusy)
                        }
                    }

                    Button(model.activeCandidates.isEmpty ? "撤回桌面" : "撤回") { model.restorePrevious() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(MuseTheme.muted)
                }
                .frame(height: CreationLayout.controlRowHeight)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MuseTheme.sidebar)
        .overlay(alignment: .top) {
            Rectangle().fill(MuseTheme.border).frame(height: 1)
        }
        .sheet(isPresented: $showingReferencePicker) { ReferencePicker(model: model) }
    }

    private func scheduleChip(_ channel: InspirationChannel) -> some View {
        Button {
            showingScheduleFor = channel.id
        } label: {
            HStack(spacing: 4) {
                Image(systemName: channel.resolvedScheduleEnabled ? "clock.fill" : "clock")
                    .font(.caption2.weight(.bold))
                Text(channel.resolvedScheduleEnabled ? model.scheduleSummary(for: channel) : "定时")
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(channel.resolvedScheduleEnabled ? MuseTheme.amber : MuseTheme.muted)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                Capsule().fill(channel.resolvedScheduleEnabled ? MuseTheme.amber.opacity(0.14) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private var composerPlaceholder: String {
        if model.isBlankSeriesSession { return "写下想看的画面，例如：温暖的春天的悠闲午后" }
        return "这就是这个系列的灵感词，改了会自动记住"
    }

    private func requestGeneration() {
        model.requestGeneration()
    }

    private var largeImagePane: some View {
        ZStack {
            Group {
                if let url = model.latestImageURL {
                    CachedWallpaperImage(path: url.path, role: .preview, fill: true)
                } else {
                    WallpaperPlaceholder()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if model.latestImageURL == nil {
                creationStageBanner()
                    .padding(.horizontal, 28)
            }

            if model.activeCandidates.count > 1 {
                HStack {
                    candidateNavChevron(systemName: "chevron.left", enabled: model.canSelectPreviousCandidate) {
                        model.selectAdjacentCandidate(-1)
                    }
                    Spacer(minLength: 0)
                    candidateNavChevron(systemName: "chevron.right", enabled: model.canSelectNextCandidate) {
                        model.selectAdjacentCandidate(1)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45))
        .onTapGesture(count: 2) {
            if model.canApplySelected { model.applySelectedCandidate() }
        }
        .help(model.canApplySelected ? "双击设为壁纸 · ⌥⌘← ⌥⌘→ 切换候选" : model.creationStageDetail)
    }

    private func candidateNavChevron(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Color.white.opacity(0.92) : Color.white.opacity(0.28))
                .frame(width: 36, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(enabled ? 0.42 : 0.18))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func creationStageBanner() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(MuseTheme.amber.opacity(0.85))
            Text(model.creationStageTitle)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Color.white.opacity(0.92))
            Text(model.creationStageDetail)
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
        }
    }

    private var candidateFilmstrip: some View {
        HStack(spacing: 8) {
            filmstripEdgeControls(leading: true)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 倒序：新图在左，生成中的占位也挂在最前。
                        if model.isCreationBusy {
                            ForEach(0..<min(loadingPlaceholderCount, 3), id: \.self) { slot in
                                loadingTile
                                    .frame(width: CreationLayout.filmTileWidth, height: CreationLayout.filmHeight - 12)
                                    .id("loading-\(slot)")
                            }
                        }
                        ForEach(Array(model.activeCandidates.enumerated()), id: \.element.id) { index, record in
                            candidateTile(record, index: index)
                                .frame(width: CreationLayout.filmTileWidth, height: CreationLayout.filmHeight - 12)
                                .id(record.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .onChange(of: model.selectedCandidateID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: model.activeCandidates.count) { _, _ in
                    guard let id = model.selectedCandidateID ?? model.activeCandidates.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            filmstripEdgeControls(leading: false)
        }
    }

    private func filmstripEdgeControls(leading: Bool) -> some View {
        VStack(spacing: 4) {
            if leading {
                Button {
                    model.selectFirstCandidate()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canSelectPreviousCandidate ? MuseTheme.ink : MuseTheme.muted)
                .disabled(!model.canSelectPreviousCandidate)
                .help("最新一张")

                Button {
                    model.selectAdjacentCandidate(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canSelectPreviousCandidate ? MuseTheme.amber : MuseTheme.muted)
                .disabled(!model.canSelectPreviousCandidate)
                .help("更新一张 · ⌥⌘←")
            } else {
                Button {
                    model.selectAdjacentCandidate(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canSelectNextCandidate ? MuseTheme.amber : MuseTheme.muted)
                .disabled(!model.canSelectNextCandidate)
                .help("更早一张 · ⌥⌘→")

                Button {
                    model.selectLastCandidate()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canSelectNextCandidate ? MuseTheme.ink : MuseTheme.muted)
                .disabled(!model.canSelectNextCandidate)
                .help("最早一张")
            }

            if !model.candidatePositionCaption.isEmpty, leading == false {
                Text(model.candidatePositionCaption)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MuseTheme.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: leading ? 28 : 56)
    }

    private var generateButton: some View {
        Group {
            if model.isCreationBusy {
                Button(action: { model.cancelCreation() }) {
                    Label(model.stopActionTitle, systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button(action: requestGeneration) {
                    Label(model.generateActionTitle, systemImage: "sparkles")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var loadingPlaceholderCount: Int {
        guard model.isCreationBusy else { return 0 }
        let target = max(model.generationTotal, model.batchSize)
        return max(0, target - model.currentBatchReadyCount)
    }

    private func candidateTile(_ record: GenerationRecord, index: Int) -> some View {
        Button { model.selectCandidate(record.id) } label: {
            ZStack(alignment: .topLeading) {
                CachedWallpaperImage(path: record.imagePath, role: .candidate)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(5)
                    .background(.black.opacity(0.65))
                    .clipShape(Circle())
                    .padding(5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        model.selectedCandidateID == record.id ? MuseTheme.amber : MuseTheme.border,
                        lineWidth: model.selectedCandidateID == record.id ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            model.selectCandidate(record.id)
            if model.canApplySelected { model.applySelectedCandidate() }
        })
        .contextMenu {
            Button("设为壁纸") {
                model.selectCandidate(record.id)
                model.applySelectedCandidate()
            }
            .disabled(record.imagePath == nil)
            Button("重新生成") {
                model.selectCandidate(record.id)
                model.regenerateSelectedCandidate()
            }
            Button("删除这张", role: .destructive) { model.deleteRecord(record.id) }
        }
    }

    private var loadingTile: some View {
        ZStack {
            Color.white.opacity(0.035)
            ProgressView().controlSize(.small)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MuseTheme.border))
    }

    // MARK: - Library

    private var libraryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    pageHeader(
                        model.libraryShowsTrash ? "回收箱" : "作品集",
                        subtitle: model.libraryShowsTrash
                            ? "还原回作品集，或永久删除。永久删除会清掉磁盘文件。"
                            : "点开大图浏览。删除会进回收箱，可还原。"
                    )
                    Spacer()
                    if !model.libraryShowsTrash {
                        WallpaperTargetPicker(model: model, width: 160)
                    }
                    if model.libraryShowsTrash {
                        Button("清空回收箱", role: .destructive) { model.emptyTrash() }
                            .disabled(model.trashedArtworks.isEmpty)
                    } else {
                        Button { showingCollectionEditor = true } label: { Label("做一组筛选", systemImage: "folder.badge.plus") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                collectionShelf
                if !model.libraryShowsTrash, !model.allArtworkTags.isEmpty { tagFilterShelf }
                HStack {
                    Text(model.libraryCountCaption)
                        .font(.caption.weight(.semibold)).foregroundStyle(MuseTheme.muted)
                    if !model.libraryShowsTrash {
                        Picker("排序", selection: Binding(
                            get: { model.librarySortOrder },
                            set: { model.setLibrarySortOrder($0) }
                        )) {
                            ForEach(LibrarySortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .help("按创作时间排序")
                    }
                    Spacer()
                    if model.isRetagging {
                        Text("重打标签 \(model.retagDone)/\(model.retagTotal)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MuseTheme.amber)
                        Button("停止") { model.cancelRetag() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    } else if !model.libraryShowsTrash, !model.selectedLibraryTags.isEmpty, !model.filteredArtworks.isEmpty {
                        Button {
                            model.retagFilteredArtworks()
                        } label: {
                            Label("重打标签 (\(model.filteredArtworks.count))", systemImage: "tag")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .help("对当前筛选出的作品重新打标签；Agent 开启时优先用 AI，否则本地规则")
                    }
                    if !model.selectedLibraryTags.isEmpty {
                        Button("清除标签筛选") { model.selectedLibraryTags.removeAll() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .museHitMinHeight(MuseHit.chip)
                            .foregroundStyle(MuseTheme.amber)
                    }
                }
                if model.filteredArtworks.isEmpty {
                    if model.libraryShowsTrash {
                        emptyTrash
                    } else {
                        emptyLibrary
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(model.filteredArtworks) { artworkCard($0) }
                    }
                }
            }.padding(30)
        }
    }

    private var collectionShelf: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                Button {
                    model.showLibraryTrash(false)
                    model.activeCollectionID = nil
                } label: {
                    Label("全部图", systemImage: "photo.on.rectangle.angled")
                        .padding(.horizontal, 13).frame(height: 38)
                        .background(Capsule().fill(!model.libraryShowsTrash && model.activeCollectionID == nil ? MuseTheme.amber : MuseTheme.panel))
                        .foregroundStyle(!model.libraryShowsTrash && model.activeCollectionID == nil ? .black : MuseTheme.ink)
                }.buttonStyle(.plain)
                ForEach(model.smartCollections) { collection in
                    Button {
                        model.showLibraryTrash(false)
                        model.activeCollectionID = collection.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles.rectangle.stack")
                            Text(collection.name)
                            Text("\(model.artworkCount(for: collection))").foregroundStyle(model.activeCollectionID == collection.id ? Color.black.opacity(0.55) : MuseTheme.muted)
                        }
                        .padding(.horizontal, 13).frame(height: 38)
                        .background(Capsule().fill(!model.libraryShowsTrash && model.activeCollectionID == collection.id ? MuseTheme.amber : MuseTheme.panel))
                        .foregroundStyle(!model.libraryShowsTrash && model.activeCollectionID == collection.id ? .black : MuseTheme.ink)
                    }.buttonStyle(.plain).contextMenu { Button("删除作品集", role: .destructive) { model.deleteCollection(collection.id) } }
                }
                Button { model.showLibraryTrash(true) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                        Text("回收箱")
                        if !model.trashedArtworks.isEmpty {
                            Text("\(model.trashedArtworks.count)")
                                .foregroundStyle(model.libraryShowsTrash ? Color.black.opacity(0.55) : MuseTheme.muted)
                        }
                    }
                    .padding(.horizontal, 13).frame(height: 38)
                    .background(Capsule().fill(model.libraryShowsTrash ? MuseTheme.amber : MuseTheme.panel))
                    .foregroundStyle(model.libraryShowsTrash ? .black : MuseTheme.ink)
                }.buttonStyle(.plain)
            }
        }.scrollIndicators(.hidden).font(.caption.weight(.semibold))
    }

    private var tagFilterShelf: some View {
        let tags = libraryTagsExpanded
            ? model.allArtworkTags
            : Array(model.allArtworkTags.prefix(36))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("AI TAGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(MuseTheme.muted)
                if !model.selectedLibraryTags.isEmpty {
                    Text("已选 \(model.selectedLibraryTags.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MuseTheme.moss)
                }
                Spacer(minLength: 0)
                if model.allArtworkTags.count > 36 {
                    Button(libraryTagsExpanded ? "收起" : "全部 \(model.allArtworkTags.count)") {
                        libraryTagsExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MuseTheme.amber)
                }
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tags, id: \.self) { tag in
                    let on = model.selectedLibraryTags.contains(tag)
                    Button {
                        model.toggleLibraryTag(tag)
                    } label: {
                        Text("#\(tag)")
                            .font(.system(size: MuseHit.tagFont, weight: .semibold))
                            .foregroundStyle(on ? .black : MuseTheme.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(on ? MuseTheme.moss : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tag)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MuseTheme.border, lineWidth: 1)
        )
    }

    private var emptyLibrary: some View {
        VStack(spacing: 13) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 36, weight: .light)).foregroundStyle(MuseTheme.amber)
            Text("还没有图").font(.title3.weight(.semibold)).foregroundStyle(MuseTheme.ink)
            Text("去生图页出一组，就会出现在这里。").font(.callout).foregroundStyle(MuseTheme.muted)
            Button("去生图") { page = .create }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, minHeight: 360).musePanel(radius: 22)
    }

    private var emptyTrash: some View {
        VStack(spacing: 13) {
            Image(systemName: "trash").font(.system(size: 36, weight: .light)).foregroundStyle(MuseTheme.muted)
            Text("回收箱是空的").font(.title3.weight(.semibold)).foregroundStyle(MuseTheme.ink)
            Text("删除的作品会先到这里，可还原或永久删除。").font(.callout).foregroundStyle(MuseTheme.muted)
            Button("回作品集") { model.showLibraryTrash(false) }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, minHeight: 360).musePanel(radius: 22)
    }

    private func artworkCard(_ record: GenerationRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.refreshDisplays()
                lightboxArtworkID = record.id
            } label: {
                CachedWallpaperImage(path: record.imagePath, role: .thumbnail)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if record.isTrashed {
                            Image(systemName: "trash.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                                .padding(8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("放大查看")
            Text(model.channels.first(where: { $0.id == record.request.seriesID })?.name ?? "未保存的一次")
                .font(.caption.weight(.semibold)).foregroundStyle(MuseTheme.ink)
            Text(StudioViewModel.artworkTimeCaption(record.createdAt))
                .font(.caption2)
                .foregroundStyle(MuseTheme.muted)
            let core = model.artworkCoreKeywords(record)
            if !core.isEmpty {
                Text(core)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MuseTheme.ink)
                    .lineLimit(2)
            }
            if !record.finalPromptText.isEmpty {
                DisclosureGroup {
                    Text(record.finalPromptText)
                        .font(.caption)
                        .foregroundStyle(MuseTheme.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("最终 Prompt")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MuseTheme.muted)
                }
            }
            FlowTags(tags: record.resolvedTags)
            if model.libraryShowsTrash {
                HStack(spacing: 8) {
                    Button("还原") { model.restoreFromTrash(record.id) }
                        .buttonStyle(.bordered)
                    Button("源文件") { model.revealArtworkInFinder(record.id, preferSource: true) }
                        .buttonStyle(.plain)
                        .foregroundStyle(MuseTheme.ink)
                    Spacer(minLength: 0)
                    Button("永久删除", role: .destructive) { model.purgeFromTrash(record.id) }
                        .buttonStyle(.plain)
                }
                .font(.caption.weight(.semibold))
                .museHitMinHeight(MuseHit.chip)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        model.applyArtwork(record.id)
                    } label: {
                        Text("设为壁纸")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    HStack(spacing: 10) {
                        Button(record.isFavorite ? "已收藏" : "收藏") { model.toggleFavorite(record.id) }
                            .buttonStyle(.plain)
                            .foregroundStyle(MuseTheme.ink)
                        Button("再出") {
                            model.useArtworkAsReference(record.id)
                            page = .create
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MuseTheme.ink)
                        Button("重打标签") { model.retagArtwork(record.id) }
                            .buttonStyle(.plain)
                            .foregroundStyle(MuseTheme.amber)
                            .disabled(model.isRetagging)
                        Spacer(minLength: 0)
                        Button("源文件") {
                            model.revealArtworkInFinder(record.id, preferSource: model.hasDistinctSourceImage(record))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(MuseTheme.muted)
                        Button("删除", role: .destructive) { model.deleteRecord(record.id) }
                            .buttonStyle(.plain)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }.padding(12).musePanel(radius: 16)
    }

    // MARK: - Playlists

    private var playlistsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    pageHeader("自动换壁纸", subtitle: "从已有的图里轮流换桌面。多条同时开着时，第 1 优先先管重叠的屏。")
                    Spacer()
                    Button {
                        playlistEditorTarget = .create
                    } label: { Label("加一条换壁纸规则", systemImage: "plus") }.buttonStyle(.borderedProminent)
                }
                if model.playlists.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "play.square.stack").font(.system(size: 38, weight: .light)).foregroundStyle(MuseTheme.amber)
                        Text("让桌面自己换图").font(.title3.weight(.semibold)).foregroundStyle(MuseTheme.ink)
                        Text("选一个系列或一组筛选，打开开关后才会按间隔换桌面。")
                            .font(.callout).foregroundStyle(MuseTheme.muted)
                    }.frame(maxWidth: .infinity, minHeight: 340).musePanel(radius: 22)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 16)], spacing: 16) {
                        ForEach(model.rankedPlaylists) { playlist in playlistCard(playlist) }
                    }
                }
            }.padding(30)
        }
    }

    private func playlistCard(_ playlist: WallpaperPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: playlist.enabled ? "play.fill" : "pause.fill")
                    .foregroundStyle(playlist.enabled ? MuseTheme.moss : MuseTheme.muted)
                Text(playlist.name).font(.headline).foregroundStyle(MuseTheme.ink)
                if playlist.isPreset {
                    Text("预设")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MuseTheme.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(MuseTheme.amber.opacity(0.14)))
                }
                Spacer()
                Text(playlist.enabled ? "运行中" : "已暂停").font(.caption2).foregroundStyle(playlist.enabled ? MuseTheme.moss : MuseTheme.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(model.playlistSourceName(playlist), systemImage: playlist.source == .task ? "scope" : "sparkles.rectangle.stack")
                Text("\(playlist.priorityCaption(among: model.playlists)) · \(model.playlistArtworkCount(playlist)) 张 · \(playlist.order.rawValue) · \(playlist.intervalCaption)")
                Text(playlist.ownershipCaption(among: model.playlists, displays: model.displayProfiles))
                Text("氛围 · \(playlist.resolvedAtmosphere.rawValue)")
            }.font(.caption).foregroundStyle(MuseTheme.muted)
            Toggle(playlist.enabled ? "正在自动换" : "先别换", isOn: Binding(
                get: { playlist.enabled },
                set: { model.setPlaylistEnabled(playlist.id, enabled: $0) }
            ))
            HStack {
                Button("现在换一张") { model.playPlaylistNow(playlist.id, respectPriority: false) }
                    .buttonStyle(.borderedProminent)
                Button("提高优先") { model.movePlaylistPriority(playlist.id, higher: true) }
                    .disabled(!model.canRaisePlaylistPriority(playlist.id))
                Button("降低优先") { model.movePlaylistPriority(playlist.id, higher: false) }
                    .disabled(!model.canLowerPlaylistPriority(playlist.id))
                Spacer()
                Button("编辑") { playlistEditorTarget = .edit(playlist) }
                if playlist.isPreset {
                    Button("暂停") {
                        model.setPlaylistEnabled(playlist.id, enabled: false)
                    }
                    .disabled(!playlist.enabled)
                    .help("预设任务不能删除，只能暂停")
                } else {
                    Button(role: .destructive) { model.deletePlaylist(playlist.id) } label: { Image(systemName: "trash") }
                }
            }.buttonStyle(.plain)
        }.padding(18).musePanel(radius: 18, strong: true)
    }

    // MARK: - Settings

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader("设置", subtitle: "先连上图片模型就能出图。桌面装饰可按需再开。")
                MuseSettingsDisclosure(title: "文生图 API", isExpanded: $imageAPIExpanded) {
                    imageModelSettings
                }
                MuseSettingsDisclosure(title: "Agent 与大模型 API", isExpanded: $agentAPIExpanded) {
                    promptAgentSettings
                }
                MuseSettingsDisclosure(title: "桌面装饰（时钟 / 天气 / 氛围）", isExpanded: $desktopChromeExpanded) {
                    wallpaperTransitionCard
                }
                launchAtLoginCard
                versionCard
            }.padding(30).frame(maxWidth: 850, alignment: .leading)
        }
    }

    private var wallpaperTransitionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("换图仍是一次落定。氛围含缓动与鼠标视差；时钟与天气合在同一块面板。若图标或右键异常，先关掉氛围。")
                .font(.caption).foregroundStyle(MuseTheme.muted)

            Toggle(
                "壁纸氛围动效（含鼠标反馈）",
                isOn: Binding(
                    get: { model.settings.livingWallpaperEnabled ?? true },
                    set: {
                        model.settings.livingWallpaperEnabled = $0
                        model.saveSettings()
                    }
                )
            )
            if model.settings.livingWallpaperEnabled ?? true {
                Picker("默认风格", selection: Binding(
                    get: { model.settings.livingWallpaperStyle ?? .kenBurns },
                    set: {
                        model.settings.livingWallpaperStyle = $0
                        model.saveSettings()
                    }
                )) {
                    ForEach(LivingWallpaperStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Divider().opacity(0.35)
            Toggle(
                "桌面时钟",
                isOn: Binding(
                    get: { model.settings.desktopClockEnabled ?? true },
                    set: { model.setDesktopClockEnabled($0) }
                )
            )
            if model.settings.desktopClockEnabled ?? true {
                Picker("表盘", selection: Binding(
                    get: { model.settings.desktopClockFace ?? .desktop },
                    set: { model.setDesktopClockFace($0) }
                )) {
                    ForEach(DesktopClockFace.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Toggle(
                "在时钟下方显示天气温度",
                isOn: Binding(
                    get: { model.settings.desktopWeatherEnabled ?? true },
                    set: { model.setDesktopWeatherEnabled($0) }
                )
            )
            if model.settings.desktopWeatherEnabled ?? true {
                Picker("温度单位", selection: Binding(
                    get: { model.settings.desktopWeatherUnit ?? .celsius },
                    set: { model.setDesktopWeatherUnit($0) }
                )) {
                    ForEach(WeatherTemperatureUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                TextField(
                    "天气城市（可选，如杭州）",
                    text: Binding(
                        get: { model.settings.desktopWeatherCity ?? "" },
                        set: { model.setDesktopWeatherCity($0) }
                    )
                )
                Text("自动定位顺序：系统定位 → 国内 IP 城市 → 上次正确位置。机房出口 IP 容易偏城，不准时在上面填「杭州」。")
                    .font(.caption).foregroundStyle(MuseTheme.muted)
            }

            Divider().opacity(0.35)
            Toggle(
                "桌面角落快捷键",
                isOn: Binding(
                    get: { model.settings.desktopControlsEnabled ?? true },
                    set: {
                        model.settings.desktopControlsEnabled = $0
                        model.saveSettings()
                    }
                )
            )
            Text("右下角：喜欢、删除（进回收箱并换下一张）、下一张。菜单栏也可操作。")
                .font(.caption).foregroundStyle(MuseTheme.muted)
        }
        .padding(.top, 6)
    }

    private var launchAtLoginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开机启动").font(.headline).foregroundStyle(MuseTheme.ink)
            Toggle(
                "登录 Mac 时自动打开 Musepaper",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            Text("方便自动换壁纸、桌面时钟和角落快捷键在后台继续工作。建议把 App 装在「应用程序」里再打开此开关。")
                .font(.caption).foregroundStyle(MuseTheme.muted)
            if model.launchAtLoginNeedsApproval {
                HStack(spacing: 10) {
                    Text("等待系统批准登录项。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MuseTheme.amber)
                    Button("打开登录项设置") { LoginLaunchService.openLoginItemsSettings() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .musePanel(radius: 17, strong: true)
    }

    private var imageModelSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("当前连接", selection: Binding(get: { model.activeModelConfigurationID ?? UUID() }, set: { model.selectModelConfiguration($0) })) {
                ForEach(model.modelConfigurations) { Text($0.name).tag($0.id) }
            }
            if let current = model.activeModelConfiguration {
                let config = Binding<ModelConfiguration>(get: { model.activeModelConfiguration ?? current }, set: { model.updateActiveModelConfiguration($0) })
                Picker("服务类型", selection: config.provider) { ForEach(ProviderKind.allCases) { Text($0.rawValue).tag($0) } }
                if config.wrappedValue.provider != .demo {
                    TextField("连接名称", text: config.name)
                    TextField("Base URL", text: config.baseURL)
                    TextField("图片模型（文生图名，不要填 Hy3）", text: config.model)
                    Text("换电脑只拷 app，AK 不会跟着走。保存并测试会真出一张图；成功会写「连接成功」。AntChat/Qwen 请用 1664×928 或 2048×1152，1536×1024 拉到 Retina 大屏会明显发糊。「质量」仅官方 OpenAI 生效。")
                        .font(.caption2)
                        .foregroundStyle(MuseTheme.muted)
                    SecureField(model.apiKeyConfigured ? "AK 已保存；留空不修改" : "API Key / AK", text: $model.apiKeyDraft)
                    Text("尺寸、质量在生图页调整。AntChat/Qwen 建议 2048×1152；「质量」仅官方 OpenAI 生效。")
                        .font(.caption2)
                        .foregroundStyle(MuseTheme.muted)
                }
                HStack {
                    Button("新增连接") { model.addModelConfiguration() }
                    Spacer()
                    Button("保存") { model.saveModelConfiguration() }
                    Button(model.isTestingConnection ? "测试中…" : "保存并测试") { model.saveAndTestModelConnection() }.buttonStyle(.borderedProminent).disabled(model.isTestingConnection)
                }
                if let notice = model.connectionNotice {
                    Text(notice)
                        .font(.caption.weight(notice.hasPrefix("连接成功") ? .semibold : .regular))
                        .foregroundStyle(notice.hasPrefix("连接成功") ? MuseTheme.moss : MuseTheme.muted)
                }
            }
        }.padding(.top, 14)
    }

    private var promptAgentSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("一个厂商连接 = Base URL + AK；模型名写成列表。Agent 选用时按「厂商:模型」选择或随机。")
                .font(.caption).foregroundStyle(MuseTheme.muted)

            Text("厂商连接").font(.subheadline.weight(.semibold)).foregroundStyle(MuseTheme.ink)
            Picker("当前厂商", selection: Binding(
                get: {
                    model.activePromptModelConfiguration?.id
                        ?? model.promptModelConfigurations.first?.id
                        ?? UUID()
                },
                set: { model.selectPromptModelConfiguration($0) }
            )) {
                ForEach(model.promptModelConfigurations) { config in
                    Text(config.vendorName).tag(config.id)
                }
            }
            if let current = model.activePromptModelConfiguration {
                let config = Binding<PromptModelConfiguration>(
                    get: { model.activePromptModelConfiguration ?? current },
                    set: { model.updateActivePromptModelConfiguration($0) }
                )
                TextField("厂商名称", text: config.name)
                TextField("Base URL", text: config.baseURL)
                Picker("接口格式", selection: config.apiFormat) {
                    ForEach(PromptAPIFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                SecureField(model.activePromptAPIKeyConfigured ? "AK 已保存；留空不修改" : "API Key / AK", text: $model.promptAPIKeyDraft)

                Text("模型列表").font(.caption.weight(.semibold)).foregroundStyle(MuseTheme.muted)
                Text("一行一个模型名，共用上面这把 AK。")
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.muted)
                TextEditor(text: $model.promptModelsTextDraft)
                    .font(.body.monospaced())
                    .frame(minHeight: 88, maxHeight: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MuseTheme.border, lineWidth: 1))
                    .onAppear { model.syncPromptModelsTextDraft() }

                HStack {
                    Button("新增厂商") { model.addPromptModelConfiguration() }
                    Button("删除厂商", role: .destructive) { model.deleteActivePromptModelConfiguration() }
                        .disabled(model.promptModelConfigurations.count <= 1)
                    Spacer()
                    Button("复用图片模型 AK") { model.reuseImageAPIKeyForPromptModel() }.disabled(!model.apiKeyConfigured)
                    Button("保存") { model.savePromptModelConfiguration() }
                    Button(model.isTestingPromptModel ? "测试中…" : "保存并测试") { model.saveAndTestPromptModel() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isTestingPromptModel)
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            Text("Agent 选用").font(.subheadline.weight(.semibold)).foregroundStyle(MuseTheme.ink)
            Text("当前：\(model.promptAgentRouting.enabled ? "已启用" : "未启用") · \(model.promptAgentRouting.mode.rawValue)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.promptAgentRouting.enabled ? MuseTheme.moss : MuseTheme.muted)
            Picker("选用方式", selection: Binding(
                get: { model.promptAgentRouting.mode },
                set: { model.setPromptAgentMode($0) }
            )) {
                ForEach(PromptAgentModelMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.promptAgentRouting.mode == .fixed {
                Picker("固定使用", selection: Binding(
                    get: { model.promptAgentRouting.activeRef?.id ?? "" },
                    set: { id in
                        if let option = model.promptAgentSelectionOptions.first(where: { $0.ref.id == id }) {
                            model.selectPromptAgentRef(option.ref)
                        }
                    }
                )) {
                    ForEach(model.promptAgentSelectionOptions, id: \.ref.id) { option in
                        Text(option.label).tag(option.ref.id)
                    }
                }
            } else {
                Text("勾选参与随机的「厂商:模型」；每次 Agent 调用抽一个。")
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.muted)
                ForEach(model.promptAgentSelectionOptions, id: \.ref.id) { option in
                    Toggle(isOn: Binding(
                        get: { model.promptAgentRouting.eligibleRefs.contains(option.ref) },
                        set: { model.setPromptModelEligible(option.ref, eligible: $0) }
                    )) {
                        Text(option.label).foregroundStyle(MuseTheme.ink)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            if let notice = model.promptAgentNotice {
                Text(notice).font(.caption).foregroundStyle(MuseTheme.muted)
            }
        }.padding(.top, 14)
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于 Musepaper").font(.headline).foregroundStyle(MuseTheme.ink)
            SofunAIPublisherView()
                .foregroundStyle(MuseTheme.ink)
            Link("GitHub 开源主页", destination: AppIdentity.repositoryURL)
                .font(.caption)
                .foregroundStyle(MuseTheme.amber)
            Divider().overlay(MuseTheme.border)
            Text("当前版本").font(.headline).foregroundStyle(MuseTheme.ink)
            Text(AppVersion.display)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(MuseTheme.amber)
            if let latest = AppChangelog.latest {
                Text("\(latest.version) · \(latest.date)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MuseTheme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(latest.highlights, id: \.self) { line in
                        Text("· \(line)")
                            .font(.caption)
                            .foregroundStyle(MuseTheme.muted)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(model.isCheckingUpdate ? "检查中…" : "检查更新") {
                    model.checkForUpdate(manual: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isCheckingUpdate)
                if model.updateCheckResult?.status == .updateAvailable {
                    Button("下载更新") { model.openUpdateDownload() }
                        .buttonStyle(.bordered)
                    Button("打开下载页") { model.openUpdateDownload() }
                        .buttonStyle(.plain)
                }
            }
            if let update = model.updateCheckResult {
                Text(update.message)
                    .font(.caption.weight(update.status == .updateAvailable ? .semibold : .regular))
                    .foregroundStyle(update.status == .updateAvailable ? MuseTheme.amber : MuseTheme.muted)
            }
            Text("启动后会自动检查 OSS 上的最新版；有新版时顶栏与菜单栏会提示。安装请用 DMG 里的「安装并打开」。")
                .font(.caption2)
                .foregroundStyle(MuseTheme.muted)
        }
        .padding(18)
        .musePanel(radius: 17, strong: true)
    }

    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 31, weight: .medium, design: .serif)).foregroundStyle(MuseTheme.ink)
            Text(subtitle).font(.callout).foregroundStyle(MuseTheme.muted)
        }
    }
}

private extension View {
    func museSettingsSection() -> some View {
        self.font(.headline).foregroundStyle(MuseTheme.ink).padding(18).musePanel(radius: 17)
    }
}

/// Full-row expandable settings block — label text is as clickable as the chevron.
private struct MuseSettingsDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MuseTheme.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(MuseTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: MuseHit.tab, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "收起" : "展开")

            if isExpanded {
                content()
                    .font(.body)
                    .foregroundStyle(MuseTheme.ink)
            }
        }
        .padding(18)
        .musePanel(radius: 17)
    }
}

private struct MoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let id: UUID
    private let existing: InspirationChannel?
    @State private var idea: String
    @State private var name: String
    @State private var essence: String
    @State private var coreKeywords: String
    @State private var variationAxes: String
    @State private var palette: String
    @State private var exclusions: String
    @State private var promptStrategy: PromptStrategy
    @State private var scheduleEnabled: Bool
    @State private var scheduleHour: Int
    @State private var scheduleIntervalSeconds: Int
    @State private var scheduledCandidateCount: Int
    @State private var showAdvanced = false
    @State private var isExpanding = false
    @State private var error: String?
    let canUseAI: Bool
    let onExpand: (String) async throws -> WallpaperBlueprintSuggestion
    let onSave: (InspirationChannel, Bool) -> Void

    init(channel: InspirationChannel?, canUseAI: Bool, onExpand: @escaping (String) async throws -> WallpaperBlueprintSuggestion, onSave: @escaping (InspirationChannel, Bool) -> Void) {
        existing = channel
        id = channel?.id ?? UUID()
        _idea = State(initialValue: channel?.essence ?? "")
        _name = State(initialValue: channel?.name ?? "")
        _essence = State(initialValue: channel?.essence ?? "")
        _coreKeywords = State(initialValue: channel?.resolvedCoreKeywords ?? "")
        _variationAxes = State(initialValue: channel?.resolvedVariationAxes ?? "")
        _palette = State(initialValue: channel?.palette ?? "")
        _exclusions = State(initialValue: channel?.exclude ?? "文字、水印、徽标、边框")
        _promptStrategy = State(initialValue: channel?.resolvedPromptStrategy ?? .hybrid)
        _scheduleEnabled = State(initialValue: channel?.resolvedScheduleEnabled ?? false)
        _scheduleHour = State(initialValue: channel?.resolvedScheduleHour ?? 8)
        _scheduleIntervalSeconds = State(initialValue: channel?.resolvedScheduleIntervalSeconds ?? InspirationChannel.defaultIntervalSeconds)
        _scheduledCandidateCount = State(initialValue: channel?.resolvedScheduledCandidateCount ?? 4)
        self.canUseAI = canUseAI; self.onExpand = onExpand; self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("改这个系列").font(.system(size: 28, weight: .medium, design: .serif))
                Text("改感觉或打开自动出图。自动出图只往图库加图，不会换桌面。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            TextEditor(text: $idea).font(.system(size: 18, design: .serif)).frame(height: 92).padding(10).musePanel(radius: 13)
                .overlay(alignment: .topLeading) { if idea.isEmpty { Text("例如：潮湿、安静、有巨大空间感的未来上海").foregroundStyle(.secondary).padding(17).allowsHitTesting(false) } }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("自动出图（只进图库，不换桌面）", isOn: $scheduleEnabled)
                if scheduleEnabled {
                    IntervalControl(
                        seconds: scheduleIntervalSeconds,
                        nextCaption: "下次 \(ScheduleService.nextFireCaption(intervalSeconds: scheduleIntervalSeconds, lastProducedAt: existing?.lastProducedAt))",
                        onChange: { scheduleIntervalSeconds = $0 }
                    )
                    CountControl(value: scheduledCandidateCount, caption: "每次 \(scheduledCandidateCount) 张") {
                        scheduledCandidateCount = $0
                    }
                }
            }.padding(15).musePanel(radius: 14)

            DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Button { expand() } label: { Label(isExpanding ? "正在整理…" : "让 AI 拆开保持项和变化项", systemImage: "sparkles") }
                        .disabled(!canUseAI || idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExpanding)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Picker("探索方式", selection: $promptStrategy) {
                        ForEach(PromptStrategy.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("名称", text: $name); TextField("整体气质", text: $essence)
                    TextField("必须保持的视觉内核", text: $coreKeywords); TextField("允许变化的维度", text: $variationAxes)
                    TextField("色板", text: $palette); TextField("禁止元素", text: $exclusions)
                }.padding(.top, 10)
            }
            Spacer()
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("只保存") { commit(generateNow: false) }.disabled(!canSave)
                Button("保存并生成") { commit(generateNow: true) }
                    .buttonStyle(.borderedProminent).disabled(!canSave)
            }
        }.padding(26).frame(width: 520, height: 460)
    }

    private var promptStrategyDescription: String {
        switch promptStrategy {
        case .explore: "围绕主题内核主动寻找新的场景、天气、时段和镜头表达。"
        case .enhance: "忠实保留你写的 Prompt，只补足构图、光线、材质与壁纸约束。"
        case .hybrid: "既保持主题身份，也允许 Agent 在变化轴内探索新的表现。"
        }
    }

    private var canSave: Bool {
        !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit(generateNow: Bool) {
        let prompt = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = InspirationChannel(
            id: id, name: name, essence: prompt.isEmpty ? essence : prompt,
            mustInclude: existing?.mustInclude ?? "",
            exclude: exclusions, palette: palette, variation: existing?.variation ?? 0.55,
            requiresApproval: existing?.requiresApproval ?? true,
            coreKeywords: coreKeywords, variationAxes: variationAxes,
            defaultCandidateCount: existing?.resolvedCandidateCount ?? 4,
            referenceImagePaths: existing?.resolvedReferenceImagePaths ?? [],
            promptStrategy: promptStrategy, scheduleEnabled: scheduleEnabled,
            scheduleHour: scheduleHour, scheduledCandidateCount: scheduledCandidateCount,
            scheduleIntervalSeconds: scheduleIntervalSeconds,
            seedArtworkPath: existing?.seedArtworkPath, seedArtworkID: existing?.seedArtworkID,
            lastProducedAt: existing?.lastProducedAt
        ).completingMissingFields(idea: idea)
        onSave(channel, generateNow)
        dismiss()
    }

    private func expand() {
        isExpanding = true; error = nil
        Task {
            do {
                let result = try await onExpand(idea)
                name = result.name; essence = result.essence; coreKeywords = result.coreKeywords
                variationAxes = result.variationAxes; palette = result.palette; exclusions = result.exclusions
            } catch { self.error = error.localizedDescription }
            isExpanding = false
        }
    }
}

private struct ScheduleEditorSheet: View {
    let channelID: UUID?
    @ObservedObject var model: StudioViewModel
    var onDone: () -> Void

    private var live: InspirationChannel? {
        guard let channelID else { return nil }
        return model.channels.first(where: { $0.id == channelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动出图").font(.title2.weight(.semibold))
                    Text(live?.name ?? "未选择任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("完成") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            if let live {
                Toggle("打开自动出图", isOn: Binding(
                    get: { live.resolvedScheduleEnabled },
                    set: { model.setTaskSchedule(live.id, enabled: $0) }
                ))
                .font(.body)

                if live.resolvedScheduleEnabled {
                    IntervalControl(
                        seconds: live.resolvedScheduleIntervalSeconds,
                        nextCaption: model.scheduleSummary(for: live),
                        onChange: { model.setTaskSchedule(live.id, intervalSeconds: $0) }
                    )
                    HStack(spacing: 8) {
                        Text("每次")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(MuseTheme.ink)
                        CompactCountField(
                            value: live.resolvedScheduledCandidateCount,
                            onChange: { model.setTaskSchedule(live.id, count: $0) }
                        )
                    }
                    Text("只写入作品集，不会自动换桌面。Musepaper 需要保持打开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("打开后按间隔自动出图，结果进作品集。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("任务已不存在。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 380, height: 280)
    }
}

private struct ReferencePicker: View {
    @ObservedObject var model: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("选一张参考图").font(.headline)
            Text("点哪张，下一组就按哪张的感觉出。")
                .font(.caption).foregroundStyle(.secondary)
            if model.referencePickerArtworks.isEmpty {
                Text("还没有图。先出一组，或从电脑选一张。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(Array(model.referencePickerArtworks.prefix(24))) { record in
                            if let path = record.imagePath {
                                Button { model.toggleReference(path: path) } label: {
                                    ZStack(alignment: .topTrailing) {
                                        CachedWallpaperImage(path: path, role: .thumbnail)
                                        if model.displayedReferencePaths.contains(path) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(MuseTheme.amber)
                                                .padding(5)
                                        }
                                    }
                                    .frame(width: 88, height: 56).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                        model.displayedReferencePaths.contains(path) ? MuseTheme.amber : MuseTheme.border,
                                        lineWidth: model.displayedReferencePaths.contains(path) ? 2 : 1
                                    ))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            HStack {
                Button("从电脑选图") { model.chooseReferenceFiles() }
                Spacer()
                Button("关掉参考图") { model.setUseReferenceImages(false) }
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(Array(tags.prefix(8)), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: MuseHit.tagFont, weight: .medium))
                    .foregroundStyle(MuseTheme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.055)))
            }
            if tags.count > 8 {
                Text("+\(tags.count - 8)")
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct CollectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var taskIDs: Set<UUID> = []
    @State private var tags: Set<String> = []
    @State private var excludedTags: Set<String> = []
    @State private var favoritesOnly = false
    @State private var tagQuery = ""
    @State private var pickingExclude = false
    let tasks: [InspirationChannel]
    let availableTags: [String]
    let onSave: (SmartCollection) -> Void

    private var filteredTags: [String] {
        let query = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = query.isEmpty
            ? availableTags
            : availableTags.filter { $0.lowercased().contains(query) }
        return Array(base.prefix(36))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("做一组筛选").font(.system(size: 24, weight: .medium, design: .serif))
                Text("保存筛选规则，不复制图片。新作品符合条件会自动进来。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("名称，例如：安静的蓝色夜景", text: $name)
                .textFieldStyle(.roundedBorder)

            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("来源任务").font(.caption.weight(.bold)).foregroundStyle(MuseTheme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tasks) { task in
                                let on = taskIDs.contains(task.id)
                                Button(task.name) {
                                    if on { taskIDs.remove(task.id) } else { taskIDs.insert(task.id) }
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Capsule().fill(on ? MuseTheme.amber : Color.white.opacity(0.06)))
                                .foregroundStyle(on ? .black : MuseTheme.ink)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("标签").font(.caption.weight(.bold)).foregroundStyle(MuseTheme.muted)
                    Spacer()
                    Picker("模式", selection: $pickingExclude) {
                        Text("要包含").tag(false)
                        Text("要排除").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                if !tags.isEmpty || !excludedTags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(Array(tags).sorted(), id: \.self) { tag in
                            Button("#\(tag)") { tags.remove(tag) }
                                .buttonStyle(.plain)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(MuseTheme.moss))
                                .foregroundStyle(.black)
                        }
                        ForEach(Array(excludedTags).sorted(), id: \.self) { tag in
                            Button("−#\(tag)") { excludedTags.remove(tag) }
                                .buttonStyle(.plain)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.red.opacity(0.35)))
                                .foregroundStyle(MuseTheme.ink)
                        }
                    }
                }
                TextField("搜索标签", text: $tagQuery)
                    .textFieldStyle(.roundedBorder)
                if availableTags.isEmpty {
                    Text("还没有 AI 标签，先出几张图。").font(.caption).foregroundStyle(.secondary)
                } else if filteredTags.isEmpty {
                    Text("没有匹配的标签").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                            ForEach(filteredTags, id: \.self) { tag in
                                tagChip(tag)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    if availableTags.count > filteredTags.count, tagQuery.isEmpty {
                        Text("只显示常用 \(filteredTags.count) 个，搜索可找其余标签。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Toggle("只包含收藏", isOn: $favoritesOnly)
                    .font(.caption)
            }
            .padding(12)
            .musePanel(radius: 12)

            Spacer(minLength: 0)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建作品集") {
                    onSave(SmartCollection(
                        name: name, taskIDs: Array(taskIDs),
                        includeTags: Array(tags), excludeTags: Array(excludedTags),
                        favoritesOnly: favoritesOnly
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480, height: 560)
    }

    private func tagChip(_ tag: String) -> some View {
        let included = tags.contains(tag)
        let excluded = excludedTags.contains(tag)
        let active = pickingExclude ? excluded : included
        return Button("#\(tag)") {
            if pickingExclude {
                if excluded {
                    excludedTags.remove(tag)
                } else {
                    tags.remove(tag)
                    excludedTags.insert(tag)
                }
            } else if included {
                tags.remove(tag)
            } else {
                excludedTags.remove(tag)
                tags.insert(tag)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(
            pickingExclude
                ? (active ? Color.red.opacity(0.35) : Color.white.opacity(0.06))
                : (active ? MuseTheme.moss : Color.white.opacity(0.06))
        ))
        .foregroundStyle(active && !pickingExclude ? .black : MuseTheme.ink)
    }
}

private enum PlaylistEditorTarget: Identifiable {
    case create
    case edit(WallpaperPlaylist)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let playlist): return playlist.id.uuidString
        }
    }

    var playlist: WallpaperPlaylist? {
        if case .edit(let playlist) = self { return playlist }
        return nil
    }
}

private struct PlaylistEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let id: UUID
    private let isEditing: Bool
    @State private var name: String
    @State private var source: PlaylistSource
    @State private var sourceID: UUID?
    @State private var order: PlaylistOrder
    @State private var intervalSeconds: Int
    @State private var enabled: Bool
    @State private var atmosphere: PlaylistAtmosphere
    @State private var targetAllDisplays: Bool
    @State private var selectedDisplayIDs: Set<String>
    private let lastArtworkID: UUID?
    private let lastArtworkIDsByDisplay: [String: UUID]?
    private let existingPriority: Int?
    let tasks: [InspirationChannel]
    let collections: [SmartCollection]
    let displays: [DisplayProfile]
    let onSave: (WallpaperPlaylist) -> Void

    init(
        playlist: WallpaperPlaylist?, tasks: [InspirationChannel], collections: [SmartCollection],
        displays: [DisplayProfile],
        onSave: @escaping (WallpaperPlaylist) -> Void
    ) {
        let existing = playlist
        id = existing?.id ?? UUID()
        isEditing = existing != nil
        _name = State(initialValue: existing?.name ?? "")
        _source = State(initialValue: existing?.source ?? .all)
        _sourceID = State(initialValue: existing?.sourceID)
        _order = State(initialValue: existing?.order ?? .shuffle)
        _intervalSeconds = State(initialValue: existing?.intervalSeconds ?? WallpaperPlaylist.defaultIntervalSeconds)
        _enabled = State(initialValue: existing?.enabled ?? false)
        _atmosphere = State(initialValue: existing?.resolvedAtmosphere ?? .followGlobal)
        existingPriority = existing?.priority
        let targets = existing?.targetDisplayIDs ?? []
        _targetAllDisplays = State(initialValue: targets.isEmpty)
        _selectedDisplayIDs = State(initialValue: Set(targets))
        lastArtworkID = existing?.lastArtworkID
        lastArtworkIDsByDisplay = existing?.lastArtworkIDsByDisplay
        self.tasks = tasks
        self.collections = collections
        self.displays = displays
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isEditing ? "编辑换壁纸" : "自动换壁纸")
                    .font(.system(size: 27, weight: .medium, design: .serif))
                Text("从已经有的图里轮流换桌面，不会去出新图。多条同时开着时，优先高的先管重叠的屏。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("给这条规则起个名", text: $name)
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("用哪些图", selection: $source) {
                            ForEach(PlaylistSource.allCases) { source in
                                Text(source == .all ? "全部图" : source == .task ? "某个系列" : "一组筛选").tag(source)
                            }
                        }.pickerStyle(.segmented)
                        if source == .task {
                            Picker("哪个系列", selection: optionalSourceBinding(defaultID: tasks.first?.id)) {
                                ForEach(tasks) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } else if source == .collection {
                            Picker("哪组筛选", selection: optionalSourceBinding(defaultID: collections.first?.id)) {
                                ForEach(collections) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                    }.padding(15).musePanel(radius: 14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("贴到哪些屏幕").font(.subheadline.weight(.semibold))
                        Text("可选多块屏；到点时各屏尽量换不同的图。")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("全部已连接屏幕", isOn: $targetAllDisplays)
                        if !targetAllDisplays {
                            if displays.isEmpty {
                                Text("还没有检测到屏幕。").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ForEach(displays) { display in
                                    Toggle(isOn: Binding(
                                        get: { selectedDisplayIDs.contains(display.id) },
                                        set: { on in
                                            if on { selectedDisplayIDs.insert(display.id) }
                                            else { selectedDisplayIDs.remove(display.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(display.name)
                                            Text("\(display.width)×\(display.height) · \(display.id)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(15)
                    .musePanel(radius: 14)

                    Picker("播放顺序", selection: $order) { ForEach(PlaylistOrder.allCases) { Text($0.rawValue).tag($0) } }
                    IntervalControl(
                        seconds: intervalSeconds,
                        nextCaption: "到点自动换下一张",
                        minSeconds: WallpaperPlaylist.minIntervalSeconds,
                        maxSeconds: WallpaperPlaylist.maxIntervalSeconds
                    ) { intervalSeconds = $0 }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("氛围动效").font(.subheadline.weight(.semibold))
                        Text("作用于这条任务管到的桌面；随机氛围会在每次换图时重抽一种。")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("氛围", selection: $atmosphere) {
                            ForEach(PlaylistAtmosphere.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(15)
                    .musePanel(radius: 14)
                    Toggle("保存后马上开始换", isOn: $enabled)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
            }

            Divider().opacity(0.28)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 620)
        .onChange(of: source) { _, newSource in
            switch newSource {
            case .all:
                sourceID = nil
            case .task:
                if sourceID == nil || !tasks.contains(where: { $0.id == sourceID }) {
                    sourceID = tasks.first?.id
                }
            case .collection:
                if sourceID == nil || !collections.contains(where: { $0.id == sourceID }) {
                    sourceID = collections.first?.id
                }
            }
        }
        .onChange(of: targetAllDisplays) { _, on in
            if on { selectedDisplayIDs.removeAll() }
            else if selectedDisplayIDs.isEmpty, let first = displays.first {
                selectedDisplayIDs = [first.id]
            }
        }
    }

    private var resolvedTargetDisplayIDs: [String]? {
        if targetAllDisplays { return nil }
        let ids = displays.map(\.id).filter { selectedDisplayIDs.contains($0) }
        return ids.isEmpty ? nil : ids
    }

    private func optionalSourceBinding(defaultID: UUID?) -> Binding<UUID?> {
        Binding(get: { sourceID ?? defaultID }, set: { sourceID = $0 })
    }

    private func commit() {
        onSave(
            WallpaperPlaylist(
                id: id, name: name, source: source,
                sourceID: resolvedSourceID, order: order,
                intervalSeconds: intervalSeconds, enabled: enabled,
                lastArtworkID: lastArtworkID,
                lastArtworkIDsByDisplay: lastArtworkIDsByDisplay,
                targetDisplayIDs: resolvedTargetDisplayIDs,
                atmosphere: atmosphere,
                priority: existingPriority
            )
        )
        dismiss()
    }

    private var canSave: Bool {
        let named = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sourceOK = source == .all || sourceID != nil || (source == .task ? tasks.first != nil : collections.first != nil)
        let displayOK = targetAllDisplays || !selectedDisplayIDs.isEmpty || displays.isEmpty
        return named && sourceOK && displayOK
    }

    private var resolvedSourceID: UUID? {
        switch source {
        case .all: nil
        case .task: sourceID ?? tasks.first?.id
        case .collection: sourceID ?? collections.first?.id
        }
    }
}

private struct IntervalControl: View {
    let seconds: Int
    let nextCaption: String
    var minSeconds: Int = InspirationChannel.minIntervalSeconds
    var maxSeconds: Int = InspirationChannel.maxIntervalSeconds
    let onChange: (Int) -> Void
    @State private var unit: InspirationChannel.IntervalUnit
    @State private var typedAmount = ""

    init(
        seconds: Int,
        nextCaption: String,
        minSeconds: Int = InspirationChannel.minIntervalSeconds,
        maxSeconds: Int = InspirationChannel.maxIntervalSeconds,
        onChange: @escaping (Int) -> Void
    ) {
        self.seconds = seconds
        self.nextCaption = nextCaption
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.onChange = onChange
        let clamped = min(max(seconds, minSeconds), maxSeconds)
        let initialUnit: InspirationChannel.IntervalUnit
        if clamped % 86400 == 0 {
            initialUnit = .days
        } else if clamped % 3600 == 0 {
            initialUnit = .hours
        } else if clamped % 60 == 0 {
            initialUnit = .minutes
        } else {
            initialUnit = .seconds
        }
        _unit = State(initialValue: initialUnit)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, minSeconds), maxSeconds)
    }

    private func preferredUnit(for seconds: Int) -> InspirationChannel.IntervalUnit {
        let value = clamp(seconds)
        if value % 86400 == 0 { return .days }
        if value % 3600 == 0 { return .hours }
        if value % 60 == 0 { return .minutes }
        return .seconds
    }

    private var amount: Int {
        max(1, clamp(seconds) / unit.stepSeconds)
    }

    private func seconds(amount: Int, unit: InspirationChannel.IntervalUnit) -> Int {
        clamp(max(1, amount) * unit.stepSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("每").font(.caption.weight(.semibold)).foregroundStyle(MuseTheme.muted)
                TextField("数量", text: Binding(
                    get: { typedAmount.isEmpty ? "\(amount)" : typedAmount },
                    set: { typedAmount = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .onSubmit { commitTypedAmount() }
                Picker("单位", selection: Binding(
                    get: { unit },
                    set: { newUnit in
                        let currentAmount = Int(typedAmount) ?? amount
                        typedAmount = ""
                        unit = newUnit
                        onChange(seconds(amount: currentAmount, unit: newUnit))
                    }
                )) {
                    ForEach(InspirationChannel.IntervalUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)
                Stepper("", value: Binding(
                    get: { amount },
                    set: { newAmount in
                        typedAmount = ""
                        onChange(seconds(amount: newAmount, unit: unit))
                    }
                ), in: 1...max(1, maxSeconds / unit.stepSeconds))
                .labelsHidden()
            }
            if let summary = summaryLine {
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MuseTheme.ink)
                    .lineLimit(2)
            }
            if showsShortIntervalWarning {
                Text("间隔过短会频繁换图，更耗电；一般建议 30 秒以上。")
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.amber)
            }
        }
        .onChange(of: seconds) { _, newValue in
            if seconds(amount: amount, unit: unit) != clamp(newValue) {
                unit = preferredUnit(for: newValue)
            }
            if typedAmount.isEmpty == false, Int(typedAmount) == amount {
                typedAmount = ""
            }
        }
        .onChange(of: typedAmount) { _, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed), value > 0 else { return }
            onChange(seconds(amount: value, unit: unit))
        }
    }

    private var summaryLine: String? {
        let cadence = InspirationChannel.cadenceLabel(
            seconds: clamp(seconds),
            minSeconds: minSeconds,
            maxSeconds: maxSeconds
        )
        let trimmed = nextCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return cadence }
        if trimmed.hasPrefix("下次") {
            return trimmed
        }
        return "\(trimmed) · \(cadence)"
    }

    private var showsShortIntervalWarning: Bool {
        minSeconds <= 1 && clamp(seconds) < 5
    }

    private func commitTypedAmount() {
        let trimmed = typedAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(trimmed) ?? amount
        typedAmount = ""
        onChange(seconds(amount: value, unit: unit))
    }
}

private struct CompactCountField: View {
    let value: Int
    let onChange: (Int) -> Void
    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("张数", text: Binding(
                get: { typed.isEmpty ? "\(value)" : typed },
                set: { typed = $0.filter(\.isNumber) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 52)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { commitTyped() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commitTyped() }
            }
            Text("张")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MuseTheme.muted)
            Stepper("", value: Binding(
                get: { value },
                set: {
                    typed = ""
                    onChange(InspirationChannel.clampedCount($0))
                }
            ), in: InspirationChannel.candidateCountRange)
            .labelsHidden()
            .controlSize(.mini)
        }
        .help("直接输入想出的张数")
        .onChange(of: value) { _, _ in
            if typed.isEmpty == false, Int(typed) == value { typed = "" }
        }
    }

    private func commitTyped() {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if let next = Int(trimmed) {
            onChange(InspirationChannel.clampedCount(next))
        }
        typed = ""
    }
}

private struct CountControl: View {
    let value: Int
    let caption: String
    let onChange: (Int) -> Void
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("张数").font(.caption2.weight(.bold)).foregroundStyle(MuseTheme.muted)
            HStack(spacing: 8) {
                TextField("张", text: Binding(
                    get: { typed.isEmpty ? "\(value)" : typed },
                    set: { typed = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 44)
                .onSubmit { commitTyped() }
                Text(caption)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MuseTheme.ink)
                    .lineLimit(1)
                Stepper("", value: Binding(
                    get: { value },
                    set: { onChange(InspirationChannel.clampedCount($0)); typed = "" }
                ), in: InspirationChannel.candidateCountRange)
                .labelsHidden()
            }
            HStack(spacing: 6) {
                ForEach(InspirationChannel.countPresets, id: \.self) { option in
                    Button("\(option)") {
                        typed = ""
                        onChange(option)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(option == value ? MuseTheme.amber : Color.white.opacity(0.06)))
                    .foregroundStyle(option == value ? Color.black : MuseTheme.muted)
                }
            }
        }
        .onChange(of: value) { _, _ in
            if typed.isEmpty == false, Int(typed) == value { typed = "" }
        }
    }

    private func commitTyped() {
        if let next = Int(typed.trimmingCharacters(in: .whitespacesAndNewlines)) {
            onChange(InspirationChannel.clampedCount(next))
        }
        typed = ""
    }
}

/// ⌥⌘← / ⌥⌘→ 切胶片。不用隐形 Button+裸方向键：那会抢走输入框光标，还会把窗口焦点吞掉导致顶栏点不动。
private struct CandidateShortcutMonitor: NSViewRepresentable {
    var enabled: Bool
    var onLeft: () -> Void
    var onRight: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.apply(enabled: enabled, onLeft: onLeft, onRight: onRight)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.apply(enabled: enabled, onLeft: onLeft, onRight: onRight)
    }

    final class MonitorView: NSView {
        var enabled = false
        var onLeft: () -> Void = {}
        var onRight: () -> Void = {}
        nonisolated(unsafe) private var monitor: Any?

        override var acceptsFirstResponder: Bool { false }

        func apply(enabled: Bool, onLeft: @escaping () -> Void, onRight: @escaping () -> Void) {
            self.enabled = enabled
            self.onLeft = onLeft
            self.onRight = onRight
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                uninstall()
            } else {
                install()
            }
        }

        private func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled, self.window?.isKeyWindow == true else { return event }
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard mods.contains(.option), mods.contains(.command), !mods.contains(.control) else {
                    return event
                }
                switch event.keyCode {
                case 123:
                    self.onLeft()
                    return nil
                case 124:
                    self.onRight()
                    return nil
                default:
                    return event
                }
            }
        }

        private func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
