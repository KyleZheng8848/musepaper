import AppKit

/// Tiny desktop-corner controls: sit above wallpaper/icons, below every app window.
@MainActor
final class DesktopControlOverlay {
    static let likedTag = ArtworkTagger.userLikedTag

    private var controlWindows: [NSWindow] = []
    private var likeButtons: [NSButton] = []
    private var onLike: ((String) -> Void)?
    private var onNext: ((String) -> Void)?
    private var onDelete: ((String) -> Void)?
    private var likedByDisplay: [String: Bool] = [:]
    private var enabled = false
    private var screenSignature = ""

    func update(
        enabled: Bool,
        likedByDisplay: [String: Bool],
        onLike: @escaping (String) -> Void,
        onNext: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void
    ) {
        guard !Self.isRunningTests else { return }
        self.onLike = onLike
        self.onNext = onNext
        self.onDelete = onDelete
        DesktopControlProxy.shared.onLike = { [weak self] id in self?.onLike?(id) }
        DesktopControlProxy.shared.onNext = { [weak self] id in self?.onNext?(id) }
        DesktopControlProxy.shared.onDelete = { [weak self] id in self?.onDelete?(id) }

        if !enabled {
            self.enabled = false
            hide()
            return
        }

        let signature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width),\($0.frame.height),\($0.visibleFrame.minY)"
        }.joined(separator: "|")

        if !self.enabled || signature != screenSignature || controlWindows.isEmpty {
            self.enabled = true
            self.likedByDisplay = likedByDisplay
            self.screenSignature = signature
            rebuild()
            return
        }

        if self.likedByDisplay != likedByDisplay {
            self.likedByDisplay = likedByDisplay
            refreshLikeAppearance()
        }
    }

    func refreshLanguage() {
        if enabled { rebuild() }
    }

    func hide() {
        tearDownWindows()
        enabled = false
        screenSignature = ""
    }

    private func tearDownWindows() {
        controlWindows.forEach { $0.orderOut(nil); $0.close() }
        controlWindows.removeAll()
        likeButtons.removeAll()
    }

    private func rebuild() {
        // Keep screenSignature from update(); clearing it here forced a rebuild on every refresh.
        tearDownWindows()
        enabled = true
        for (screenIndex, screen) in NSScreen.screens.enumerated() {
            let displayID = DisplayService.displayID(index: screenIndex)
            let liked = likedByDisplay[displayID] ?? false
            let visible = screen.visibleFrame
            let size = NSSize(width: 48, height: 48)
            let margin: CGFloat = 18
            let gap: CGFloat = 10
            // Right-to-left cluster: next (corner) ← delete ← like
            let specs: [(symbol: String, tooltip: String, accent: Bool, action: Selector)] = [
                ("forward.fill", L10n.tr("只换这块屏的下一张"), false, #selector(DesktopControlProxy.next)),
                ("trash", L10n.tr("把这块屏的壁纸移入回收箱并换下一张"), false, #selector(DesktopControlProxy.delete)),
                (likedSymbol(liked), likedTooltip(liked), liked, #selector(DesktopControlProxy.like)),
            ]

            for (index, spec) in specs.enumerated() {
                let origin = NSPoint(
                    x: visible.maxX - margin - size.width - CGFloat(index) * (size.width + gap),
                    y: visible.minY + margin
                )
                let button = makeButton(
                    size: size,
                    symbol: spec.symbol,
                    tooltip: spec.tooltip,
                    accent: spec.accent,
                    action: spec.action,
                    displayID: displayID
                )
                let window = makeWindow(frame: NSRect(origin: origin, size: size), content: button)
                controlWindows.append(window)
                if spec.action == #selector(DesktopControlProxy.like) {
                    likeButtons.append(button)
                }
            }
        }
    }

    private func refreshLikeAppearance() {
        for button in likeButtons {
            let liked = likedByDisplay[button.identifier?.rawValue ?? ""] ?? false
            applyChrome(to: button, symbol: likedSymbol(liked), tooltip: likedTooltip(liked), accent: liked)
        }
    }

    private func likedSymbol(_ liked: Bool) -> String { liked ? "heart.fill" : "heart" }
    private func likedTooltip(_ liked: Bool) -> String { liked ? L10n.tr("取消喜欢这块屏的壁纸") : L10n.tr("喜欢这块屏的壁纸（加入标签）") }

    private func makeWindow(frame: NSRect, content: NSView) -> NSWindow {
        // Tiny panel only — never full-screen. Full-screen layers above
        // WallpaperAgent break desktop icons / right-click on modern macOS.
        let window = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.sharingType = .readOnly
        // Do NOT set isFloatingPanel — it forces level .floating (above apps).
        window.becomesKeyOnlyIfNeeded = true
        window.worksWhenModal = true
        window.level = Self.controlLevel
        window.contentView = content
        window.setFrame(frame, display: true)
        window.orderFront(nil)
        return window
    }

    private func makeButton(
        size: NSSize,
        symbol: String,
        tooltip: String,
        accent: Bool,
        action: Selector,
        displayID: String
    ) -> NSButton {
        let button = PressFeedbackButton(frame: NSRect(origin: .zero, size: size))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = size.height / 2
        button.layer?.borderWidth = 1
        button.identifier = NSUserInterfaceItemIdentifier(displayID)
        applyChrome(to: button, symbol: symbol, tooltip: tooltip, accent: accent)
        button.target = DesktopControlProxy.shared
        button.action = action
        button.setButtonType(.momentaryChange)
        return button
    }

    private func applyChrome(
        to button: NSButton,
        symbol: String,
        tooltip: String,
        accent: Bool
    ) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
        }
        button.toolTip = tooltip
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        button.contentTintColor = accent
            ? NSColor(calibratedRed: 1, green: 0.45, blue: 0.55, alpha: 1)
            : .white
    }

    /// Above desktop icons, still under normal app windows.
    private static var controlLevel: NSWindow.Level {
        // Widen before arithmetic — CGWindowLevel is Int32 near Int.min.
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class PressFeedbackButton: NSButton {
        override func mouseDown(with event: NSEvent) {
            animatePress(true)
            super.mouseDown(with: event)
            animatePress(false)
        }

        private func animatePress(_ down: Bool) {
            guard let layer else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            layer.setAffineTransform(down ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity)
            layer.backgroundColor = NSColor.black.withAlphaComponent(down ? 0.72 : 0.42).cgColor
            layer.borderColor = NSColor.white.withAlphaComponent(down ? 0.42 : 0.18).cgColor
            CATransaction.commit()
        }
    }
}

@MainActor
private final class DesktopControlProxy: NSObject {
    static let shared = DesktopControlProxy()
    var onLike: ((String) -> Void)?
    var onNext: ((String) -> Void)?
    var onDelete: ((String) -> Void)?

    @objc func like(_ sender: Any?) { onLike?(displayID(from: sender)) }
    @objc func next(_ sender: Any?) { onNext?(displayID(from: sender)) }
    @objc func delete(_ sender: Any?) { onDelete?(displayID(from: sender)) }

    private func displayID(from sender: Any?) -> String {
        if let raw = (sender as? NSView)?.identifier?.rawValue, raw.hasPrefix("screen-") {
            return raw
        }
        return DisplayService.displayID(containing: NSEvent.mouseLocation)
    }
}
