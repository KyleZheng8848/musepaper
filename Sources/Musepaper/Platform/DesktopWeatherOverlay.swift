import AppKit

/// Small weather / temperature chip on each desktop — click-through, screenshotable.
@MainActor
final class DesktopWeatherOverlay {
    private var windows: [NSWindow] = []
    private var tempLabels: [NSTextField] = []
    private var detailLabels: [NSTextField] = []
    private var iconViews: [NSImageView] = []
    private var enabled = false
    private var unit: WeatherTemperatureUnit = .celsius
    private var screenSignature = ""
    private var refreshTimer: Timer?
    private var latest: WeatherSnapshot?
    private var statusText = L10n.tr("天气加载中…")
    private let service = WeatherService()

    func update(enabled: Bool, unit: WeatherTemperatureUnit) {
        guard !Self.isRunningTests else { return }
        let unitChanged = self.unit != unit
        self.unit = unit
        if !enabled {
            self.enabled = false
            hide()
            return
        }

        let signature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width)x\($0.frame.height)"
        }.joined(separator: "|")

        if !self.enabled || signature != screenSignature || windows.isEmpty {
            self.enabled = true
            self.screenSignature = signature
            rebuild()
        } else {
            self.enabled = true
            if unitChanged { applySnapshot() }
        }
        startRefreshLoop()
        Task { await self.refreshWeather() }
    }

    func hide() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        tempLabels.removeAll()
        detailLabels.removeAll()
        iconViews.removeAll()
        screenSignature = ""
    }

    private func rebuild() {
        hide()
        enabled = true
        screenSignature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width)x\($0.frame.height)"
        }.joined(separator: "|")

        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            // Bottom-left: clear of menu bar, center clock, and bottom-right controls.
            let size = NSSize(width: 176, height: 56)
            let margin: CGFloat = 22
            let origin = NSPoint(
                x: visible.minX + margin,
                y: visible.minY + margin
            )
            let frame = NSRect(origin: origin, size: size)

            let window = OverlayPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.acceptsMouseMovedEvents = false
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.sharingType = .readOnly
            window.becomesKeyOnlyIfNeeded = false
            window.worksWhenModal = true
            window.level = Self.weatherLevel

            let root = PassThroughView(frame: NSRect(origin: .zero, size: size))
            root.wantsLayer = true
            root.layer?.cornerRadius = 14
            root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
            root.layer?.borderWidth = 1
            root.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

            let icon = NSImageView(frame: .zero)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.contentTintColor = .white
            icon.imageScaling = .scaleProportionallyUpOrDown

            let temp = makeLabel(size: 24, weight: .semibold, alpha: 0.96)
            let detail = makeLabel(size: 11, weight: .medium, alpha: 0.7)
            detail.lineBreakMode = .byTruncatingTail
            detail.maximumNumberOfLines = 1

            root.addSubview(icon)
            root.addSubview(temp)
            root.addSubview(detail)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 26),
                icon.heightAnchor.constraint(equalToConstant: 26),
                temp.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                temp.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
                temp.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
                detail.leadingAnchor.constraint(equalTo: temp.leadingAnchor),
                detail.topAnchor.constraint(equalTo: temp.bottomAnchor, constant: 1),
                detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
                detail.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -8)
            ])

            window.contentView = root
            window.setFrame(frame, display: true)
            window.orderFront(nil)
            windows.append(window)
            tempLabels.append(temp)
            detailLabels.append(detail)
            iconViews.append(icon)
        }
        applySnapshot()
        startRefreshLoop()
    }

    private func startRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshWeather() }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func refreshWeather() async {
        do {
            latest = try await service.fetch(unit: unit)
            statusText = ""
            applySnapshot()
        } catch {
            latest = nil
            statusText = (error as? LocalizedError)?.errorDescription ?? L10n.tr("天气暂不可用")
            applySnapshot()
        }
    }

    private func applySnapshot() {
        if let latest {
            let temp = latest.temperatureText(unit: unit)
            let detail = "\(latest.conditionText) · \(latest.placeLabel)"
            let symbol = latest.symbolName
            for label in tempLabels { label.stringValue = temp }
            for label in detailLabels { label.stringValue = detail }
            for icon in iconViews {
                icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: latest.conditionText)
            }
        } else {
            for label in tempLabels { label.stringValue = "--°" }
            for label in detailLabels { label.stringValue = statusText.isEmpty ? L10n.tr("天气加载中…") : statusText }
            for icon in iconViews {
                icon.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: L10n.tr("天气"))
            }
        }
    }

    private func makeLabel(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private static var weatherLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
