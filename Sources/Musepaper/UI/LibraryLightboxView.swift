import SwiftUI

struct WallpaperTargetPicker: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var model: StudioViewModel
    var width: CGFloat = 280

    var body: some View {
        HStack(spacing: 6) {
            Text(L10n.tr("贴到")).font(.caption).foregroundStyle(MuseTheme.muted)
                .fixedSize(horizontal: true, vertical: false)
            Picker(L10n.tr("贴到哪块屏幕"), selection: Binding(
                get: { model.wallpaperTargetID },
                set: { model.selectWallpaperTarget($0) }
            )) {
                Text(L10n.tr("贴到全部屏幕")).tag(StudioViewModel.allDisplaysTargetID)
                ForEach(model.displayProfiles) { display in
                    Text(model.wallpaperTargetLabel(for: display)).tag(display.id)
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
        .onAppear { model.refreshDisplays() }
    }
}

struct LibraryLightboxView: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var model: StudioViewModel
    @Binding var artworkID: UUID?
    var onReuse: (UUID) -> Void

    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var showInfo = true

    private var browsingTrash: Bool { model.libraryShowsTrash }
    private var artworks: [GenerationRecord] { model.filteredArtworks }

    private var currentIndex: Int? {
        guard let artworkID else { return nil }
        return artworks.firstIndex(where: { $0.id == artworkID })
    }

    private var current: GenerationRecord? {
        guard let currentIndex else { return nil }
        return artworks[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture { close() }

            if let record = current, let index = currentIndex {
                VStack(spacing: 0) {
                    chromeHeader(record, index: index)
                    HStack(alignment: .top, spacing: 0) {
                        imageStage(record)
                        if showInfo {
                            infoRail(record)
                                .frame(width: 280)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    lightboxFilmstrip
                    chromeFooter(record)
                }
            }
        }
        .onAppear { model.refreshDisplays(); resetView() }
        .onChange(of: artworkID) { _, _ in resetView() }
        .animation(.easeOut(duration: 0.18), value: showInfo)
        .background {
            Group {
                Button(action: { go(-1) }) { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(action: { go(1) }) { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button(action: { go(1) }) { EmptyView() }
                    .keyboardShortcut(.space, modifiers: [])
                Button(action: close) { EmptyView() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button(action: { if let id = artworkID { model.toggleFavorite(id) } }) { EmptyView() }
                    .keyboardShortcut("f", modifiers: [])
                Button(action: { showInfo.toggle() }) { EmptyView() }
                    .keyboardShortcut("i", modifiers: [])
                Button(action: { if let id = artworkID { model.revealArtworkInFinder(id, preferSource: false) } }) { EmptyView() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button(action: trashOrPurgeCurrent) { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: [])
                Button(action: { zoom = min(zoom + 0.25, 4); }) { EmptyView() }
                    .keyboardShortcut("=", modifiers: [.command])
                Button(action: { zoom = max(zoom - 0.25, 1); if zoom == 1 { pan = .zero } }) { EmptyView() }
                    .keyboardShortcut("-", modifiers: [.command])
                Button(action: resetView) { EmptyView() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private func chromeHeader(_ record: GenerationRecord, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if browsingTrash {
                        Text(L10n.tr("回收箱"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(MuseTheme.amber))
                    }
                    Text(model.channels.first(where: { $0.id == record.request.seriesID })?.name ?? L10n.tr("未保存的一次"))
                        .font(.headline)
                        .foregroundStyle(MuseTheme.ink)
                }
                Text("\(StudioViewModel.artworkTimeCaption(record.createdAt)) · \(index + 1) / \(artworks.count) · \(Int(zoom * 100))%")
                    .font(.caption)
                    .foregroundStyle(MuseTheme.muted)
            }
            Spacer()
            Button(showInfo ? L10n.tr("隐藏信息") : L10n.tr("显示信息")) { showInfo.toggle() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MuseTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.10)))
            Button(L10n.tr("关闭")) { close() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MuseTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func imageStage(_ record: GenerationRecord) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                CachedWallpaperImage(path: record.imagePath, role: .lightbox, fill: false)
                    .scaleEffect(zoom)
                    .offset(pan)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = min(max(gestureStartZoom * value, 1), 4)
                                    if zoom <= 1 { pan = .zero }
                                }
                                .onEnded { _ in
                                    gestureStartZoom = zoom
                                },
                            DragGesture()
                                .onChanged { value in
                                    guard zoom > 1 else { return }
                                    pan = value.translation
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        if zoom > 1 {
                            resetView()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { zoom = 2 }
                        }
                    }
                    .onTapGesture {}

                HStack {
                    navButton("chevron.left", enabled: artworks.count > 1) { go(-1) }
                    Spacer()
                    navButton("chevron.right", enabled: artworks.count > 1) { go(1) }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    /// 与作品集网格同源：`filteredArtworks`（标签 / 智能集 / 回收箱筛选一致）。
    private var lightboxFilmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(artworks.enumerated()), id: \.element.id) { index, record in
                        lightboxFilmTile(record, index: index)
                            .frame(width: 104, height: 58)
                            .id(record.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .frame(height: 74)
            .background(Color.black.opacity(0.42))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            .onChange(of: artworkID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                guard let id = artworkID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func lightboxFilmTile(_ record: GenerationRecord, index: Int) -> some View {
        let selected = record.id == artworkID
        return Button {
            artworkID = record.id
        } label: {
            ZStack(alignment: .topLeading) {
                CachedWallpaperImage(path: record.imagePath, role: .candidate)
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? MuseTheme.amber : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(L10n.tr("第 \(index + 1) 张"))
    }

    private func infoRail(_ record: GenerationRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("作品信息")).font(.subheadline.weight(.semibold)).foregroundStyle(MuseTheme.ink)
                labeled(L10n.tr("时间"), StudioViewModel.artworkTimeCaption(record.createdAt))
                if let trashed = record.trashedAt {
                    labeled(L10n.tr("移入回收箱"), StudioViewModel.artworkTimeCaption(trashed))
                }
                let core = model.artworkCoreKeywords(record)
                if !core.isEmpty {
                    labeled(L10n.tr("核心词"), core)
                }
                if !record.finalPromptText.isEmpty {
                    DisclosureGroup {
                        Text(record.finalPromptText)
                            .font(.caption)
                            .foregroundStyle(MuseTheme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(L10n.tr("最终 Prompt"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(MuseTheme.muted)
                    }
                } else {
                    labeled(L10n.tr("最终 Prompt"), L10n.tr("（无）"))
                }
                if !record.resolvedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("标签")).font(.caption2.weight(.bold)).foregroundStyle(MuseTheme.muted)
                        FlowTags(tags: record.resolvedTags)
                    }
                }
                Divider().overlay(Color.white.opacity(0.12))
                Text(L10n.tr("文件")).font(.caption2.weight(.bold)).foregroundStyle(MuseTheme.muted)
                Button {
                    model.revealArtworkInFinder(record.id, preferSource: false)
                } label: {
                    Label(L10n.tr("在 Finder 显示壁纸"), systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                if model.hasDistinctSourceImage(record) {
                    Button {
                        model.revealArtworkInFinder(record.id, preferSource: true)
                    } label: {
                        Label(L10n.tr("在 Finder 显示原图"), systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(L10n.tr("这张没有单独原图文件（壁纸即源文件）。"))
                        .font(.caption2)
                        .foregroundStyle(MuseTheme.muted)
                }
                Text(L10n.tr("快捷键：←→/空格翻页 · F 收藏 · I 信息 · ⌘R Finder · Delete 删除 · ⌘±/0 缩放"))
                    .font(.caption2)
                    .foregroundStyle(MuseTheme.muted)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color.black.opacity(0.45))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(MuseTheme.muted)
            Text(value)
                .font(.caption)
                .foregroundStyle(MuseTheme.ink)
                .textSelection(.enabled)
        }
    }

    private func chromeFooter(_ record: GenerationRecord) -> some View {
        HStack(spacing: 10) {
            if !browsingTrash {
                WallpaperTargetPicker(model: model, width: 220)
            }
            Spacer()
            Button(record.isFavorite ? L10n.tr("取消收藏") : L10n.tr("收藏")) {
                model.toggleFavorite(record.id)
            }
            .buttonStyle(.bordered)
            if !browsingTrash {
                Button(L10n.tr("再出")) { onReuse(record.id) }
                    .buttonStyle(.bordered)
                Button(L10n.tr("重打标签")) { model.retagArtwork(record.id) }
                    .buttonStyle(.bordered)
                    .disabled(model.isRetagging)
                Button {
                    model.revealArtworkInFinder(record.id, preferSource: model.hasDistinctSourceImage(record))
                } label: {
                    Label(L10n.tr("源文件"), systemImage: "doc.viewfinder")
                }
                .buttonStyle(.bordered)
                Button(L10n.tr("删除"), role: .destructive) { trashOrPurgeCurrent() }
                    .buttonStyle(.bordered)
                Button {
                    model.applyArtwork(record.id)
                } label: {
                    Label(L10n.tr("设为壁纸"), systemImage: "display")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(L10n.tr("还原")) {
                    let id = record.id
                    advanceAfterRemoval(of: id)
                    model.restoreFromTrash(id)
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.tr("永久删除"), role: .destructive) { trashOrPurgeCurrent() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func navButton(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MuseTheme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.28)
    }

    private func go(_ step: Int) {
        guard !artworks.isEmpty else { return }
        let index = currentIndex ?? 0
        artworkID = artworks[(index + step + artworks.count) % artworks.count].id
    }

    private func trashOrPurgeCurrent() {
        guard let id = artworkID else { return }
        advanceAfterRemoval(of: id)
        if browsingTrash {
            model.purgeFromTrash(id)
        } else {
            model.moveToTrash(id)
        }
    }

    private func advanceAfterRemoval(of id: UUID) {
        guard let index = artworks.firstIndex(where: { $0.id == id }) else {
            artworkID = nil
            return
        }
        let nextID: UUID?
        if artworks.count <= 1 {
            nextID = nil
        } else if index + 1 < artworks.count {
            nextID = artworks[index + 1].id
        } else {
            nextID = artworks[index - 1].id
        }
        artworkID = nextID
    }

    private func resetView() {
        zoom = 1
        gestureStartZoom = 1
        pan = .zero
    }

    private func close() {
        artworkID = nil
    }
}
