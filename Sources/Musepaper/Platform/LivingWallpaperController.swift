import AppKit
import Foundation
import QuartzCore

/// Ambient motion styles for the wallpaper band (under apps).
enum LivingWallpaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case random = "随机氛围"
    case kenBurns = "缓缓推镜"
    case breathe = "呼吸缩放"
    case drift = "轻柔平移"
    case glow = "光影流转"
    case cinema = "电影横移"
    case float = "悬浮动感"
    case mist = "薄雾呼吸"
    case tilt = "微微倾侧"
    case spotlight = "追光扫过"
    case orbit = "环绕游移"
    case ripple = "涟漪起伏"
    case zoomPulse = "脉动推进"
    case parallaxWave = "波纹视差"
    case softPan = "对角缓移"
    case bloom = "高光呼吸"
    case sheen = "斜向扫光"
    case pulseDrift = "脉动漂移"
    case noirFlicker = "暗调微闪"

    var id: String { rawValue }

    /// Concrete motions only — used when resolving「随机氛围」.
    static var motionCases: [LivingWallpaperStyle] {
        allCases.filter { $0 != .random }
    }

    static func randomMotion() -> LivingWallpaperStyle {
        motionCases.randomElement() ?? .kenBurns
    }

    var resolvedMotion: LivingWallpaperStyle {
        self == .random ? Self.randomMotion() : self
    }
}

/// Per wallpaper-task atmosphere override.
enum PlaylistAtmosphere: String, Codable, CaseIterable, Identifiable, Sendable {
    case followGlobal = "跟随全局设置"
    case off = "关闭氛围"
    case random = "随机氛围"
    case kenBurns = "缓缓推镜"
    case breathe = "呼吸缩放"
    case drift = "轻柔平移"
    case glow = "光影流转"
    case cinema = "电影横移"
    case float = "悬浮动感"
    case mist = "薄雾呼吸"
    case tilt = "微微倾侧"
    case spotlight = "追光扫过"
    case orbit = "环绕游移"
    case ripple = "涟漪起伏"
    case zoomPulse = "脉动推进"
    case parallaxWave = "波纹视差"
    case softPan = "对角缓移"
    case bloom = "高光呼吸"
    case sheen = "斜向扫光"
    case pulseDrift = "脉动漂移"
    case noirFlicker = "暗调微闪"

    var id: String { rawValue }

    func resolved(globalEnabled: Bool, globalStyle: LivingWallpaperStyle) -> (enabled: Bool, style: LivingWallpaperStyle) {
        switch self {
        case .followGlobal:
            return (globalEnabled, globalStyle.resolvedMotion)
        case .off:
            return (false, .kenBurns)
        case .random:
            return (true, LivingWallpaperStyle.randomMotion())
        default:
            let style = LivingWallpaperStyle(rawValue: rawValue) ?? globalStyle
            return (true, style.resolvedMotion)
        }
    }
}

/// Plays continuous low-amplitude motion over the current desktop image,
/// plus gentle pointer-reactive parallax when the cursor moves across a screen.
/// A second instance with `role == .screensaver` reuses the same motions full-screen.
@MainActor
final class LivingWallpaperController {
    enum Role {
        case desktop
        case screensaver
    }

    private let role: Role
    private var windows: [NSWindow] = []
    private var hostLayers: [CALayer] = []
    private var imageLayers: [CALayer] = []
    private var glowLayers: [CAGradientLayer] = []
    private var style: LivingWallpaperStyle = .kenBurns
    private var motionEnabled = true
    private var assignedPaths: [String: String] = [:]
    private var onDismiss: (() -> Void)?
    private var enabled = false
    private var screenSignature = ""
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var dismissMonitors: [Any] = []
    private var settleWorkItem: DispatchWorkItem?
    private var lastPointer = CGPoint.zero
    private var lastPointerTime: CFTimeInterval = 0
    private var savedPresentation: NSApplication.PresentationOptions = []

    init(role: Role = .desktop) {
        self.role = role
    }

    func update(
        enabled: Bool,
        style: LivingWallpaperStyle,
        motionEnabled: Bool = true,
        imagePathsByDisplay: [String: String] = [:],
        onDismiss: (() -> Void)? = nil
    ) {
        guard !Self.isRunningTests else { return }
        self.style = style.resolvedMotion
        self.motionEnabled = motionEnabled
        self.assignedPaths = imagePathsByDisplay
        self.onDismiss = onDismiss
        if !enabled {
            self.enabled = false
            hide()
            return
        }
        let signature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width)x\($0.frame.height)"
        }.joined(separator: "|")
        let needsRebuild = !self.enabled || signature != screenSignature || windows.isEmpty
        self.enabled = true
        self.screenSignature = signature
        if needsRebuild {
            rebuild()
        } else {
            refreshImages()
            restartMotion()
        }
        if role == .desktop {
            startPointerTracking()
        } else {
            startDismissTracking()
        }
    }

    func hide() {
        stopPointerTracking()
        stopDismissTracking()
        restorePresentation()
        settleWorkItem?.cancel()
        settleWorkItem = nil
        for window in windows {
            window.contentView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        hostLayers.removeAll()
        imageLayers.removeAll()
        glowLayers.removeAll()
        screenSignature = ""
    }

    private func rebuild() {
        hide()
        enabled = true
        if role == .screensaver {
            applyScreensaverPresentation()
        }
        for screen in NSScreen.screens {
            let frame = screen.frame
            let window: NSWindow
            if role == .screensaver {
                let saver = SaverWindow(
                    contentRect: frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                saver.onDismiss = { [weak self] in self?.onDismiss?() }
                window = saver
            } else {
                window = BandWindow(
                    contentRect: frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
            }
            window.isOpaque = true
            window.backgroundColor = .black
            window.level = role == .screensaver ? Self.screensaverLevel : Self.livingLevel
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            // Desktop must stay below Finder icons. Screensaver sits above every app.
            window.ignoresMouseEvents = role == .desktop
            window.acceptsMouseMovedEvents = role == .screensaver
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.sharingType = .readOnly
            window.animationBehavior = .none

            let root: NSView = role == .screensaver
                ? NSView(frame: NSRect(origin: .zero, size: frame.size))
                : PassThroughView(frame: NSRect(origin: .zero, size: frame.size))
            root.wantsLayer = true
            root.layer?.masksToBounds = true
            root.layer?.backgroundColor = NSColor.black.cgColor

            let host = CALayer()
            host.frame = root.bounds
            host.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            host.position = CGPoint(x: root.bounds.midX, y: root.bounds.midY)
            root.layer?.addSublayer(host)

            let imageLayer = CALayer()
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.frame = host.bounds
            imageLayer.contents = currentCGImage(on: screen)
            host.addSublayer(imageLayer)

            let glow = CAGradientLayer()
            glow.colors = [
                NSColor.clear.cgColor,
                NSColor.white.withAlphaComponent(0.12).cgColor,
                NSColor.clear.cgColor
            ]
            glow.startPoint = CGPoint(x: 0, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 0.5)
            glow.frame = CGRect(x: -frame.width, y: 0, width: frame.width * 0.55, height: frame.height)
            glow.opacity = 0
            host.addSublayer(glow)

            window.contentView = root
            window.setFrame(frame, display: true)
            if role == .screensaver {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFront(nil)
            }
            windows.append(window)
            hostLayers.append(host)
            imageLayers.append(imageLayer)
            glowLayers.append(glow)
        }
        restartMotion()
        if role == .desktop {
            startPointerTracking()
        } else {
            startDismissTracking()
        }
    }

    private func refreshImages() {
        for (index, screen) in NSScreen.screens.enumerated() where index < imageLayers.count {
            imageLayers[index].contents = currentCGImage(on: screen)
        }
    }

    private func restartMotion() {
        for (index, layer) in imageLayers.enumerated() {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            if let host = layer.superlayer {
                layer.frame = host.bounds
                layer.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
            }
            if motionEnabled {
                LivingMotion.apply(
                    styleRaw: style.rawValue,
                    to: layer,
                    glow: index < glowLayers.count ? glowLayers[index] : nil,
                    gain: motionGain
                )
            }
        }
        for host in hostLayers {
            host.removeAllAnimations()
            host.transform = CATransform3DIdentity
        }
    }

    private var motionGain: CGFloat { role == .screensaver ? 1.75 : 1 }

    // MARK: - Pointer feedback

    private func startPointerTracking() {
        stopPointerTracking()
        guard enabled else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePointerMove() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor in self?.handlePointerMove() }
            return event
        }
        handlePointerMove()
    }

    private func stopPointerTracking() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func handlePointerMove() {
        guard enabled, !windows.isEmpty else { return }
        let loc = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        let dt = max(now - lastPointerTime, 0.001)
        let speed = hypot(loc.x - lastPointer.x, loc.y - lastPointer.y) / dt
        lastPointer = loc
        lastPointerTime = now

        for (index, window) in windows.enumerated() {
            let frame = window.screen?.frame ?? window.frame
            guard frame.contains(loc) else {
                settlePointer(on: index, animated: true)
                continue
            }
            let nx = ((loc.x - frame.minX) / max(frame.width, 1)) * 2 - 1
            let ny = ((loc.y - frame.minY) / max(frame.height, 1)) * 2 - 1
            applyPointerFeedback(
                index: index,
                nx: min(max(nx, -1), 1),
                ny: min(max(ny, -1), 1),
                size: frame.size,
                speed: speed
            )
        }

        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settleAllPointers()
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func applyPointerFeedback(
        index: Int,
        nx: CGFloat,
        ny: CGFloat,
        size: CGSize,
        speed: CGFloat
    ) {
        guard index < hostLayers.count else { return }
        let host = hostLayers[index]
        let maxShift = min(size.width, size.height) * 0.018
        let tx = nx * maxShift
        let ty = ny * maxShift
        let boost = min(speed / 1800, 1)
        let scale: CGFloat = 1.012 + boost * 0.02

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 1400
        transform = CATransform3DTranslate(transform, tx, ty, 0)
        transform = CATransform3DRotate(transform, nx * -0.018, 0, 1, 0)
        transform = CATransform3DRotate(transform, ny * 0.012, 1, 0, 0)
        transform = CATransform3DRotate(transform, nx * -0.006, 0, 0, 1)
        transform = CATransform3DScale(transform, scale, scale, 1)
        host.transform = transform
        CATransaction.commit()
    }

    private func settleAllPointers() {
        for index in hostLayers.indices {
            settlePointer(on: index, animated: true)
        }
    }

    private func settlePointer(on index: Int, animated: Bool) {
        guard index < hostLayers.count else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.9 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        hostLayers[index].transform = CATransform3DIdentity
        if index < imageLayers.count {
            imageLayers[index].opacity = 1
        }
        CATransaction.commit()
    }


    private func currentCGImage(on screen: NSScreen) -> CGImage? {
        if let id = DisplayService.displayID(for: screen),
           let path = assignedPaths[id],
           let image = cgImage(at: path) {
            return image
        }
        if role == .screensaver, let path = assignedPaths.values.first, let image = cgImage(at: path) {
            return image
        }
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return cgImage(at: url.path)
    }

    private func cgImage(at path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    private func startDismissTracking() {
        stopDismissTracking()
        guard role == .screensaver, enabled else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.onDismiss?() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel],
            handler: handler
        ) {
            dismissMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel],
            handler: { [weak self] event in
                Task { @MainActor in self?.onDismiss?() }
                return event
            }
        ) {
            dismissMonitors.append(local)
        }
    }

    private func stopDismissTracking() {
        for monitor in dismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dismissMonitors.removeAll()
    }

    private func applyScreensaverPresentation() {
        savedPresentation = NSApp.presentationOptions
        NSApp.presentationOptions.insert([.hideDock, .autoHideMenuBar])
    }

    private func restorePresentation() {
        guard role == .screensaver else { return }
        NSApp.presentationOptions = savedPresentation
    }

    /// Strictly under Finder desktop icons so icons / right-click keep working.
    private static var livingLevel: NSWindow.Level {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        return NSWindow.Level(rawValue: min(desktop + 1, icons - 1))
    }

    private static var screensaverLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private final class BandWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class SaverWindow: NSWindow {
        var onDismiss: (() -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func keyDown(with event: NSEvent) { onDismiss?() }
        override func mouseDown(with event: NSEvent) { onDismiss?() }
        override func rightMouseDown(with event: NSEvent) { onDismiss?() }
        override func mouseMoved(with event: NSEvent) { onDismiss?() }
        override func scrollWheel(with event: NSEvent) { onDismiss?() }
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
