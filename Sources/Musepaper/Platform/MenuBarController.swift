import AppKit

extension Notification.Name {
    static let musepaperOpenMainWindow = Notification.Name("musepaper.openMainWindow")
    static let musepaperOpenSettings = Notification.Name("musepaper.openSettings")
    static let musepaperOpenAbout = Notification.Name("musepaper.openAbout")
}

@MainActor
final class MenuBarController {
    private var item: NSStatusItem?

    func update(
        currentTaskName: String?,
        nextTaskName: String?,
        nextCaption: String?,
        playlistRunning: Bool,
        likedCurrent: Bool,
        updateAvailableVersion: String? = nil,
        onGenerateNow: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenUpdate: @escaping () -> Void = {},
        onCheckUpdate: @escaping () -> Void = {}
    ) {
        guard !Self.isRunningTests else { return }
        if item == nil {
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            created.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Musepaper")
            created.button?.image?.isTemplate = true
            item = created
        }
        let menu = NSMenu()
        if let currentTaskName {
            let generate = NSMenuItem(title: L10n.tr("用「\(currentTaskName)」现在生成"), action: #selector(Proxy.generateNow), keyEquivalent: "")
            generate.target = Proxy.shared
            menu.addItem(generate)
        } else {
            menu.addItem(Self.item(L10n.tr("打开窗口写一句，或先选一个任务")))
        }
        if let nextTaskName, let nextCaption {
            menu.addItem(Self.item(L10n.tr("下次自动生成：\(nextTaskName) · \(nextCaption)")))
        }
        if playlistRunning {
            menu.addItem(Self.item(L10n.tr("壁纸轮播进行中")))
        }

        menu.addItem(.separator())
        let like = NSMenuItem(
            title: likedCurrent ? L10n.tr("取消喜欢当前壁纸") : L10n.tr("喜欢当前壁纸"),
            action: #selector(Proxy.like),
            keyEquivalent: ""
        )
        like.target = Proxy.shared
        menu.addItem(like)
        let next = NSMenuItem(title: L10n.tr("下一张壁纸"), action: #selector(Proxy.next), keyEquivalent: "")
        next.target = Proxy.shared
        menu.addItem(next)
        let trash = NSMenuItem(title: L10n.tr("当前这块屏的壁纸移入回收箱并换下一张"), action: #selector(Proxy.delete), keyEquivalent: "")
        trash.target = Proxy.shared
        menu.addItem(trash)

        menu.addItem(.separator())
        if let version = updateAvailableVersion {
            menu.addItem(Self.item(L10n.tr("↑ 有新版本 \(version)")))
            let download = NSMenuItem(title: L10n.tr("下载更新…"), action: #selector(Proxy.openUpdate), keyEquivalent: "")
            download.target = Proxy.shared
            menu.addItem(download)
            let page = NSMenuItem(title: L10n.tr("打开下载页…"), action: #selector(Proxy.openUpdate), keyEquivalent: "")
            page.target = Proxy.shared
            menu.addItem(page)
            menu.addItem(.separator())
        }
        menu.addItem(Self.item("Musepaper \(AppVersion.display)"))
        let check = NSMenuItem(title: L10n.tr("检查更新"), action: #selector(Proxy.checkUpdate), keyEquivalent: "")
        check.target = Proxy.shared
        menu.addItem(check)
        let open = NSMenuItem(title: L10n.tr("打开 Musepaper"), action: #selector(Proxy.openWindow), keyEquivalent: "")
        open.target = Proxy.shared
        menu.addItem(open)
        let about = NSMenuItem(title: L10n.tr("关于 SofunAI"), action: #selector(Proxy.openAbout), keyEquivalent: "")
        about.target = Proxy.shared
        menu.addItem(about)
        let quit = NSMenuItem(title: L10n.tr("退出"), action: #selector(Proxy.quit), keyEquivalent: "q")
        quit.target = Proxy.shared
        menu.addItem(quit)

        Proxy.shared.onGenerateNow = onGenerateNow
        Proxy.shared.onLike = onLike
        Proxy.shared.onNext = onNext
        Proxy.shared.onDelete = onDelete
        Proxy.shared.onOpenUpdate = onOpenUpdate
        Proxy.shared.onCheckUpdate = onCheckUpdate
        item?.menu = menu
        if let version = updateAvailableVersion {
            item?.button?.toolTip = L10n.tr("Musepaper \(AppVersion.display) · 有新版本 \(version)")
        } else if let nextCaption {
            item?.button?.toolTip = L10n.tr("Musepaper \(AppVersion.display) · 下次自动生成 \(nextCaption)")
        } else if playlistRunning {
            item?.button?.toolTip = L10n.tr("Musepaper \(AppVersion.display) · 轮播进行中")
        } else {
            item?.button?.toolTip = "Musepaper \(AppVersion.display)"
        }
    }

    func hide() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.item = nil
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func item(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

@MainActor
private final class Proxy: NSObject {
    static let shared = Proxy()
    var onGenerateNow: (() -> Void)?
    var onLike: (() -> Void)?
    var onNext: (() -> Void)?
    var onDelete: (() -> Void)?
    var onOpenUpdate: (() -> Void)?
    var onCheckUpdate: (() -> Void)?

    @objc func generateNow() {
        onGenerateNow?()
        NotificationCenter.default.post(name: .musepaperOpenMainWindow, object: nil)
    }
    @objc func like() { onLike?() }
    @objc func next() { onNext?() }
    @objc func delete() { onDelete?() }
    @objc func openUpdate() {
        onOpenUpdate?()
        NotificationCenter.default.post(name: .musepaperOpenMainWindow, object: nil)
    }
    @objc func checkUpdate() {
        onCheckUpdate?()
        NotificationCenter.default.post(name: .musepaperOpenSettings, object: nil)
    }
    @objc func openWindow() {
        NotificationCenter.default.post(name: .musepaperOpenMainWindow, object: nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openAbout() {
        NotificationCenter.default.post(name: .musepaperOpenAbout, object: nil)
    }
}
