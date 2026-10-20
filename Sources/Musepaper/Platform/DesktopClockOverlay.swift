import AppKit
import CoreText

/// Selectable desktop clock face styles.
enum DesktopClockFace: String, Codable, CaseIterable, Identifiable, Sendable {
    case desktop = "桌面标准"
    case minimal = "极简数字"
    case glass = "玻璃胶囊"
    case ring = "圆环表盘"
    case editorial = "杂志衬线"
    case mono = "等宽终端"
    case aurora = "极光底光"
    case poster = "海报刊头"
    case badge = "顶栏胶囊"
    case dayHero = "大号日期"
    case noir = "暗夜卡片"
    case horizon = "地平线"

    var id: String { rawValue }
}

/// Centered desktop clock / date — optional weather row under the date.
@MainActor
final class DesktopClockOverlay {
    private var windows: [NSWindow] = []
    private var timeLabels: [NSTextField] = []
    private var dateLabels: [NSTextField] = []
    private var weatherLabels: [NSTextField] = []
    private var weatherTempLabels: [NSTextField] = []
    private var weatherIcons: [NSImageView] = []
    private var weatherRows: [NSView] = []
    private var weatherDividers: [NSView] = []
    private var stacks: [NSView] = []
    private var chromeViews: [NSView] = []
    private var ringLayers: [CAShapeLayer] = []
    private var enabled = false
    private var face: DesktopClockFace = .desktop
    private var weatherEnabled = false
    private var weatherUnit: WeatherTemperatureUnit = .celsius
    private var weatherCity = ""
    private var screenSignature = ""
    private var clockTimer: Timer?
    private var weatherTimer: Timer?
    private var latestWeather: WeatherSnapshot?
    private var weatherStatus = "天气加载中…"
    private let weatherService = WeatherService()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE · M月d日"
        return f
    }()

    func update(
        enabled: Bool,
        face: DesktopClockFace,
        weatherEnabled: Bool = false,
        weatherUnit: WeatherTemperatureUnit = .celsius,
        weatherCity: String = ""
    ) {
        guard !Self.isRunningTests else { return }
        let showClock = enabled
        let showWeather = weatherEnabled
        let shouldShow = showClock || showWeather
        let faceChanged = self.face != face
        let city = weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let weatherChanged = self.weatherEnabled != showWeather
            || self.weatherUnit != weatherUnit
            || self.weatherCity != city
        self.face = face
        self.weatherEnabled = showWeather
        self.weatherUnit = weatherUnit
        self.weatherCity = city

        if !shouldShow {
            self.enabled = false
            hide()
            return
        }

        let signature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width)x\($0.frame.height)"
        }.joined(separator: "|") + "|w:\(showWeather)|c:\(showClock)|city:\(city)"

        // Clock-only vs clock+weather needs rebuild for layout height.
        if !self.enabled || signature != screenSignature || windows.isEmpty || faceChanged || weatherChanged {
            self.enabled = true
            self.screenSignature = signature
            rebuild(showClock: showClock)
        } else {
            self.enabled = true
            refreshText()
            applyWeather()
        }
        startClock()
        if showWeather {
            startWeatherLoop()
            Task { await self.refreshWeather(force: weatherChanged) }
        } else {
            weatherTimer?.invalidate()
            weatherTimer = nil
        }
    }

    func hide() {
        clockTimer?.invalidate()
        clockTimer = nil
        weatherTimer?.invalidate()
        weatherTimer = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        timeLabels.removeAll()
        dateLabels.removeAll()
        weatherLabels.removeAll()
        weatherTempLabels.removeAll()
        weatherIcons.removeAll()
        weatherRows.removeAll()
        weatherDividers.removeAll()
        stacks.removeAll()
        chromeViews.removeAll()
        ringLayers.removeAll()
        screenSignature = ""
    }

    private func rebuild(showClock: Bool) {
        hide()
        enabled = true
        let showWeather = weatherEnabled
        let city = weatherCity
        screenSignature = NSScreen.screens.map {
            "\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width)x\($0.frame.height)"
        }.joined(separator: "|") + "|w:\(showWeather)|c:\(showClock)|city:\(city)"

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let shortSide = min(screenFrame.width, screenFrame.height)
            let style = FaceStyle.metrics(for: face, shortSide: shortSide)
            // SF Symbols + Chinese descenders need more than pointSize; keep room for divider.
            let weatherRowH = max(36, ceil(style.weatherTempFont.pointSize * 1.55) + 12)
            let weatherGap = max(10, style.dateSpacing * 0.75) + 1 + 12 // above divider + line + below
            let weatherBlock: CGFloat = showWeather ? (weatherGap + weatherRowH) : 0

            // Keep the window tiny — a full-screen click-through layer still breaks
            // Finder desktop right-click / icon interaction on macOS.
            var winW = max(style.timeFont.pointSize * 6.2, style.dateFont.pointSize * 14)
                + style.chromePadX * 2 + 48
            var winH = (showClock
                ? style.timeFont.pointSize * 1.3 + style.dateFont.pointSize * 1.4 + style.dateSpacing
                : 0)
                + weatherBlock + style.chromePadY * 2 + 48
            if showClock, face == .ring {
                let diameter = shortSide * 0.34
                winW = max(winW, diameter + 48)
                winH = max(winH, diameter + 48 + weatherBlock)
            }
            if showClock, face == .dayHero {
                winW = max(winW, style.timeFont.pointSize * 4 + 80)
                winH = max(winH, style.timeFont.pointSize * 1.3 + style.dateFont.pointSize * 2.4 + weatherBlock + 48)
            }
            if showClock, face == .badge {
                winW = max(style.timeFont.pointSize * 5.2, 300) + style.chromePadX * 2
                winH = style.timeFont.pointSize * 1.25 + style.dateFont.pointSize * 1.35 + style.dateSpacing
                    + weatherBlock + style.chromePadY * 2 + 36
            }
            if showClock, face == .aurora || face == .horizon {
                winW = max(winW, style.timeFont.pointSize * 7.2)
                winH = max(winH, style.timeFont.pointSize * 2.2 + weatherBlock + 40)
            }
            if showWeather {
                winW = max(winW, 340)
            }
            if !showClock, showWeather {
                winW = 340
                winH = weatherRowH + style.chromePadY * 2 + 40
            }

            let winFrame: NSRect
            if face == .badge, showClock {
                winFrame = NSRect(
                    x: screenFrame.midX - winW / 2,
                    y: screenFrame.maxY - winH - max(screenFrame.height * 0.06, 48),
                    width: winW,
                    height: winH
                )
            } else {
                winFrame = NSRect(
                    x: screenFrame.midX - winW / 2,
                    y: screenFrame.midY - winH / 2 - screenFrame.height * 0.015,
                    width: winW,
                    height: winH
                )
            }

            let window = OverlayPanel(
                contentRect: winFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.acceptsMouseMovedEvents = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.sharingType = .readOnly
            window.animationBehavior = .none
            window.becomesKeyOnlyIfNeeded = false
            window.worksWhenModal = true
            window.level = Self.clockLevel

            let root = PassThroughView(frame: NSRect(origin: .zero, size: winFrame.size))
            root.wantsLayer = true

            let chrome = NSView(frame: .zero)
            chrome.wantsLayer = true
            chrome.translatesAutoresizingMaskIntoConstraints = false
            applyChromeAppearance(chrome, style: style)

            let stack = NSView(frame: .zero)
            stack.wantsLayer = true
            stack.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            stack.translatesAutoresizingMaskIntoConstraints = false

            let time = makeLabel(font: style.timeFont, color: style.timeColor)
            let date = makeLabel(font: style.dateFont, color: style.dateColor)
            time.translatesAutoresizingMaskIntoConstraints = false
            date.translatesAutoresizingMaskIntoConstraints = false
            time.isHidden = !showClock
            date.isHidden = !showClock

            let weatherRow = NSView(frame: .zero)
            weatherRow.translatesAutoresizingMaskIntoConstraints = false
            weatherRow.isHidden = !showWeather

            let divider = NSView(frame: .zero)
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.wantsLayer = true
            divider.layer?.backgroundColor = style.dateColor.withAlphaComponent(0.28).cgColor
            divider.isHidden = !(showWeather && showClock)

            let weatherIcon = NSImageView(frame: .zero)
            weatherIcon.translatesAutoresizingMaskIntoConstraints = false
            weatherIcon.contentTintColor = style.timeColor.withAlphaComponent(0.92)
            weatherIcon.imageScaling = .scaleProportionallyUpOrDown
            weatherIcon.setContentCompressionResistancePriority(.required, for: .vertical)
            weatherIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

            let weatherTemp = makeLabel(font: style.weatherTempFont, color: style.timeColor.withAlphaComponent(0.95))
            weatherTemp.translatesAutoresizingMaskIntoConstraints = false
            weatherTemp.alignment = .left
            weatherTemp.setContentCompressionResistancePriority(.required, for: .vertical)
            weatherTemp.setContentCompressionResistancePriority(.required, for: .horizontal)

            let weatherMeta = makeLabel(font: style.weatherFont, color: style.dateColor)
            weatherMeta.translatesAutoresizingMaskIntoConstraints = false
            weatherMeta.alignment = .left
            weatherMeta.setContentCompressionResistancePriority(.required, for: .vertical)
            weatherMeta.setContentCompressionResistancePriority(.required, for: .horizontal)

            weatherRow.clipsToBounds = false
            weatherRow.addSubview(weatherIcon)
            weatherRow.addSubview(weatherTemp)
            weatherRow.addSubview(weatherMeta)

            root.addSubview(chrome)
            root.addSubview(stack)
            if showClock {
                stack.addSubview(time)
                stack.addSubview(date)
            }
            if showWeather && showClock {
                stack.addSubview(divider)
            }
            if showWeather {
                stack.addSubview(weatherRow)
            }

            if showClock, face == .ring {
                let ring = CAShapeLayer()
                let diameter = shortSide * 0.34
                ring.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                ring.position = CGPoint(x: winFrame.width / 2, y: winFrame.height / 2 + (showWeather ? 10 : 0))
                ring.fillColor = NSColor.clear.cgColor
                ring.strokeColor = NSColor.white.withAlphaComponent(0.28).cgColor
                ring.lineWidth = 1.2
                ring.path = CGPath(
                    ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1),
                    transform: nil
                )
                root.layer?.addSublayer(ring)
                addRingTicks(to: root.layer, center: ring.position, radius: diameter / 2 - 6)
                ringLayers.append(ring)
            }

            if showClock, face == .aurora {
                let aura = CAGradientLayer()
                aura.colors = [
                    NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.75, alpha: 0.0).cgColor,
                    NSColor(calibratedRed: 0.45, green: 0.55, blue: 1.0, alpha: 0.22).cgColor,
                    NSColor(calibratedRed: 0.85, green: 0.4, blue: 0.95, alpha: 0.0).cgColor
                ]
                aura.startPoint = CGPoint(x: 0, y: 0.5)
                aura.endPoint = CGPoint(x: 1, y: 0.5)
                aura.frame = root.bounds.insetBy(dx: -40, dy: -20)
                aura.opacity = 0.9
                root.layer?.insertSublayer(aura, at: 0)
            }

            if showClock, face == .horizon {
                let line = CALayer()
                line.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
                line.frame = CGRect(x: winFrame.width * 0.28, y: winFrame.height * 0.42, width: winFrame.width * 0.44, height: 1)
                root.layer?.addSublayer(line)
            }

            date.maximumNumberOfLines = face == .dayHero ? 2 : 1
            date.alignment = .center

            var constraints: [NSLayoutConstraint] = [
                stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
                chrome.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                chrome.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
                chrome.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: style.chromePadX * 2),
                chrome.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: style.chromePadY * 2)
            ]

            if showClock {
                constraints += [
                    time.topAnchor.constraint(equalTo: stack.topAnchor),
                    time.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                    time.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor),
                    time.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor),
                    date.topAnchor.constraint(equalTo: time.bottomAnchor, constant: style.dateSpacing),
                    date.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                    date.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor),
                    date.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor)
                ]
                if showWeather {
                    constraints += [
                        divider.topAnchor.constraint(equalTo: date.bottomAnchor, constant: max(10, style.dateSpacing * 0.75)),
                        divider.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                        divider.widthAnchor.constraint(equalToConstant: min(120, winW * 0.28)),
                        divider.heightAnchor.constraint(equalToConstant: 1),
                        weatherRow.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
                        weatherRow.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                        weatherRow.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
                        weatherRow.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor),
                        weatherRow.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor)
                    ]
                } else {
                    constraints.append(date.bottomAnchor.constraint(equalTo: stack.bottomAnchor))
                }
            } else if showWeather {
                constraints += [
                    weatherRow.topAnchor.constraint(equalTo: stack.topAnchor),
                    weatherRow.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
                    weatherRow.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
                    weatherRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                    weatherRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
                ]
            }

            if showWeather {
                let iconSide = max(22, ceil(style.weatherTempFont.pointSize * 1.05))
                constraints += [
                    weatherIcon.leadingAnchor.constraint(equalTo: weatherRow.leadingAnchor),
                    weatherIcon.centerYAnchor.constraint(equalTo: weatherRow.centerYAnchor),
                    weatherIcon.widthAnchor.constraint(equalToConstant: iconSide),
                    weatherIcon.heightAnchor.constraint(equalToConstant: iconSide),
                    weatherTemp.leadingAnchor.constraint(equalTo: weatherIcon.trailingAnchor, constant: 8),
                    weatherTemp.centerYAnchor.constraint(equalTo: weatherRow.centerYAnchor),
                    weatherTemp.firstBaselineAnchor.constraint(equalTo: weatherMeta.firstBaselineAnchor),
                    weatherMeta.leadingAnchor.constraint(equalTo: weatherTemp.trailingAnchor, constant: 10),
                    weatherMeta.centerYAnchor.constraint(equalTo: weatherRow.centerYAnchor),
                    weatherMeta.trailingAnchor.constraint(equalTo: weatherRow.trailingAnchor),
                    weatherRow.heightAnchor.constraint(equalToConstant: weatherRowH)
                ]
            }

            NSLayoutConstraint.activate(constraints)

            window.contentView = root
            // Grow to fitting size so weather glyphs / descenders are never clipped.
            root.layoutSubtreeIfNeeded()
            let fitted = stack.fittingSize
            let pad: CGFloat = 40
            let neededW = max(winFrame.width, ceil(fitted.width) + pad)
            let neededH = max(winFrame.height, ceil(fitted.height) + pad)
            var fittedFrame = winFrame
            if neededW > winFrame.width || neededH > winFrame.height {
                fittedFrame.size.width = neededW
                fittedFrame.size.height = neededH
                fittedFrame.origin.x = screenFrame.midX - neededW / 2
                if face == .badge, showClock {
                    fittedFrame.origin.y = screenFrame.maxY - neededH - max(screenFrame.height * 0.06, 48)
                } else {
                    fittedFrame.origin.y = screenFrame.midY - neededH / 2 - screenFrame.height * 0.015
                }
            }
            window.setFrame(fittedFrame, display: true)
            window.orderFront(nil)
            windows.append(window)
            timeLabels.append(time)
            dateLabels.append(date)
            weatherLabels.append(weatherMeta)
            weatherTempLabels.append(weatherTemp)
            weatherIcons.append(weatherIcon)
            weatherRows.append(weatherRow)
            weatherDividers.append(divider)
            stacks.append(stack)
            chromeViews.append(chrome)
        }
        refreshText()
        applyWeather()
        startClock()
        if showWeather {
            startWeatherLoop()
            Task { await self.refreshWeather(force: false) }
        }
    }

    private func applyChromeAppearance(_ chrome: NSView, style: FaceStyle) {
        guard style.showsChrome else {
            chrome.layer?.backgroundColor = NSColor.clear.cgColor
            chrome.layer?.borderWidth = 0
            return
        }
        chrome.layer?.cornerRadius = style.chromeRadius
        chrome.layer?.backgroundColor = style.chromeFill.cgColor
        chrome.layer?.borderWidth = style.chromeBorderWidth
        chrome.layer?.borderColor = style.chromeBorder.cgColor
        if style.chromeBlur {
            chrome.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            chrome.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        }
    }

    private func addRingTicks(to layer: CALayer?, center: CGPoint, radius: CGFloat) {
        guard let layer else { return }
        for i in 0..<60 {
            let angle = CGFloat(i) / 60 * (.pi * 2) - .pi / 2
            let major = i % 5 == 0
            let inner = radius - (major ? 10 : 5)
            let outer = radius
            let tick = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            tick.path = path
            tick.strokeColor = NSColor.white.withAlphaComponent(major ? 0.38 : 0.16).cgColor
            tick.lineWidth = major ? 1.4 : 0.8
            layer.addSublayer(tick)
        }
    }

    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshText() }
        }
        RunLoop.main.add(clockTimer!, forMode: .common)
        refreshText()
    }

    private func startWeatherLoop() {
        weatherTimer?.invalidate()
        weatherTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshWeather(force: false) }
        }
        if let weatherTimer {
            RunLoop.main.add(weatherTimer, forMode: .common)
        }
    }

    private func refreshWeather(force: Bool) async {
        guard weatherEnabled else { return }
        if force {
            weatherService.invalidateCache()
        }
        do {
            latestWeather = try await weatherService.fetch(
                unit: weatherUnit,
                manualCity: weatherCity.isEmpty ? nil : weatherCity
            )
            weatherStatus = ""
            applyWeather()
        } catch {
            latestWeather = nil
            weatherStatus = (error as? LocalizedError)?.errorDescription ?? "天气暂不可用"
            applyWeather()
        }
    }

    private func applyWeather() {
        guard weatherEnabled else { return }
        if let latestWeather {
            let temp = latestWeather.temperatureText(unit: weatherUnit)
            let meta = "\(latestWeather.conditionText) · \(latestWeather.placeLabel)"
            for label in weatherTempLabels { label.stringValue = temp }
            for label in weatherLabels { label.stringValue = meta }
            for (idx, icon) in weatherIcons.enumerated() {
                let image = NSImage(
                    systemSymbolName: latestWeather.symbolName,
                    accessibilityDescription: latestWeather.conditionText
                )
                let point = weatherTempLabels.indices.contains(idx)
                    ? max(15, weatherTempLabels[idx].font?.pointSize ?? 16)
                    : 16
                let config = NSImage.SymbolConfiguration(pointSize: point, weight: .medium)
                icon.image = image?.withSymbolConfiguration(config)
            }
        } else {
            for label in weatherTempLabels { label.stringValue = "--°" }
            for label in weatherLabels { label.stringValue = weatherStatus.isEmpty ? "天气加载中…" : weatherStatus }
            for (idx, icon) in weatherIcons.enumerated() {
                let point = weatherTempLabels.indices.contains(idx)
                    ? max(15, weatherTempLabels[idx].font?.pointSize ?? 16)
                    : 16
                let config = NSImage.SymbolConfiguration(pointSize: point, weight: .medium)
                icon.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "天气")?
                    .withSymbolConfiguration(config)
            }
        }
    }

    private func refreshText() {
        let now = Date()
        let time = timeFormatter.string(from: now)
        let date: String
        switch face {
        case .poster:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 · EEEE"
            date = f.string(from: now)
        case .badge:
            let short = DateFormatter()
            short.locale = Locale(identifier: "zh_CN")
            short.dateFormat = "M/d EEE"
            date = short.string(from: now)
        case .dayHero:
            let day = DateFormatter()
            day.locale = Locale(identifier: "zh_CN")
            day.dateFormat = "d"
            let rest = DateFormatter()
            rest.locale = Locale(identifier: "zh_CN")
            rest.dateFormat = "M月 · EEEE"
            // Time row shows HH:mm:ss; date row shows big day via special format in label — keep readable.
            date = "\(day.string(from: now))日\n\(rest.string(from: now))"
        case .horizon:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "EEEE  ·  M月d日"
            date = f.string(from: now)
        default:
            date = dateFormatter.string(from: now)
        }
        for label in timeLabels { label.stringValue = time }
        for label in dateLabels { label.stringValue = date }
    }

    private func makeLabel(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.shadow = makeShadow(intensity: 0.55)
        return label
    }

    private func makeShadow(intensity: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5 * intensity)
        shadow.shadowBlurRadius = 16 + intensity * 8
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    /// Above wallpaper chrome, still under normal app windows. Clock never
    /// captures hits (`ignoresMouseEvents` + pass-through root view).
    private static var clockLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private final class OverlayPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Ensures nested views cannot reclaim mouse even if ignoresMouseEvents flaps.
    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: - Face metrics / fonts

private struct FaceStyle {
    var timeFont: NSFont
    var dateFont: NSFont
    var weatherTempFont: NSFont
    var weatherFont: NSFont
    var timeColor: NSColor
    var dateColor: NSColor
    var dateSpacing: CGFloat
    var showsChrome: Bool
    var chromePadX: CGFloat
    var chromePadY: CGFloat
    var chromeRadius: CGFloat
    var chromeFill: NSColor
    var chromeBorder: NSColor
    var chromeBorderWidth: CGFloat
    var chromeBlur: Bool

    static func metrics(for face: DesktopClockFace, shortSide: CGFloat) -> FaceStyle {
        let ink = NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.88, alpha: 1)
        let muted = NSColor.white.withAlphaComponent(0.58)

        func pack(
            time: NSFont,
            date: NSFont,
            spacing: CGFloat,
            chrome: Bool = false,
            padX: CGFloat = 0,
            padY: CGFloat = 0,
            radius: CGFloat = 0,
            fill: NSColor = .clear,
            border: NSColor = .clear,
            borderW: CGFloat = 0,
            blur: Bool = false,
            timeAlpha: CGFloat = 0.96,
            dateAlpha: CGFloat = 0.62
        ) -> FaceStyle {
            FaceStyle(
                timeFont: time,
                dateFont: date,
                weatherTempFont: Fonts.matching(date, size: max(16, date.pointSize * 1.2), weight: .medium),
                weatherFont: Fonts.matching(date, size: max(13, date.pointSize * 0.98), weight: .regular),
                timeColor: ink.withAlphaComponent(timeAlpha),
                dateColor: muted.withAlphaComponent(dateAlpha / 0.58),
                dateSpacing: spacing,
                showsChrome: chrome,
                chromePadX: padX, chromePadY: padY, chromeRadius: radius,
                chromeFill: fill, chromeBorder: border, chromeBorderWidth: borderW, chromeBlur: blur
            )
        }

        switch face {
        case .desktop:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.07),
                date: Fonts.dateSans(size: shortSide * 0.018),
                spacing: 10,
                dateAlpha: 0.55
            )
        case .minimal:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.072),
                date: Fonts.dateSans(size: shortSide * 0.018),
                spacing: 12
            )
        case .glass:
            return pack(
                time: Fonts.timeRounded(size: shortSide * 0.066),
                date: Fonts.dateSans(size: shortSide * 0.017),
                spacing: 10,
                chrome: true,
                padX: shortSide * 0.04,
                padY: shortSide * 0.028,
                radius: shortSide * 0.028,
                fill: NSColor.black.withAlphaComponent(0.22),
                border: NSColor.white.withAlphaComponent(0.16),
                borderW: 1,
                blur: true
            )
        case .ring:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.055),
                date: Fonts.dateSans(size: shortSide * 0.015),
                spacing: 8
            )
        case .editorial:
            return pack(
                time: Fonts.timeEditorial(size: shortSide * 0.07),
                date: Fonts.dateSerif(size: shortSide * 0.02),
                spacing: 14
            )
        case .mono:
            return pack(
                time: Fonts.timeMono(size: shortSide * 0.058),
                date: Fonts.dateMono(size: shortSide * 0.016),
                spacing: 10,
                chrome: true,
                padX: shortSide * 0.03,
                padY: shortSide * 0.022,
                radius: 6,
                fill: NSColor.black.withAlphaComponent(0.35),
                border: NSColor.white.withAlphaComponent(0.12),
                borderW: 1
            )
        case .aurora:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.078),
                date: Fonts.dateSans(size: shortSide * 0.018),
                spacing: 12
            )
        case .poster:
            // Masthead: large time + one-line date (not broken vertical stacks).
            return pack(
                time: Fonts.timeEditorial(size: shortSide * 0.068),
                date: Fonts.dateSerif(size: shortSide * 0.02),
                spacing: 12
            )
        case .badge:
            return pack(
                time: Fonts.timeRounded(size: shortSide * 0.028),
                date: Fonts.dateSans(size: shortSide * 0.014),
                spacing: 4,
                chrome: true,
                padX: 18, padY: 10, radius: 18,
                fill: NSColor.black.withAlphaComponent(0.38),
                border: NSColor.white.withAlphaComponent(0.16),
                borderW: 1,
                blur: true
            )
        case .dayHero:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.048),
                date: Fonts.dateSans(size: shortSide * 0.042),
                spacing: 8
            )
        case .noir:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.062),
                date: Fonts.dateSans(size: shortSide * 0.017),
                spacing: 10,
                chrome: true,
                padX: shortSide * 0.045,
                padY: shortSide * 0.032,
                radius: 18,
                fill: NSColor.black.withAlphaComponent(0.48),
                border: NSColor.white.withAlphaComponent(0.12),
                borderW: 1
            )
        case .horizon:
            return pack(
                time: Fonts.timeDisplay(size: shortSide * 0.074),
                date: Fonts.dateSans(size: shortSide * 0.017),
                spacing: 16
            )
        }
    }
}

private enum Fonts {
    static func timeDisplay(size: CGFloat) -> NSFont {
        pick(
            names: [
                "SFProDisplay-Ultralight",
                "SFProDisplay-Thin",
                "AvenirNext-UltraLight",
                "Futura-Light",
                "HelveticaNeue-UltraLight"
            ],
            size: size,
            fallback: system(size: size, weight: .ultraLight, design: .default)
        ).monoDigits(size: size)
    }

    static func timeRounded(size: CGFloat) -> NSFont {
        pick(
            names: ["SFProRounded-Ultralight", "SFProRounded-Thin", "AvenirNext-UltraLight"],
            size: size,
            fallback: system(size: size, weight: .ultraLight, design: .rounded)
        ).monoDigits(size: size)
    }

    static func timeEditorial(size: CGFloat) -> NSFont {
        pick(
            names: [
                "NewYorkExtraLarge-Regular",
                "NewYork-Regular",
                "Didot",
                "BodoniSvtyTwoITCTT-Book",
                "IowanOldStyle-Roman"
            ],
            size: size,
            fallback: system(size: size, weight: .light, design: .serif)
        ).monoDigits(size: size)
    }

    static func timeMono(size: CGFloat) -> NSFont {
        pick(
            names: ["SFMono-Light", "SFMono-Regular", "Menlo-Regular", "AndaleMono"],
            size: size,
            fallback: NSFont.monospacedSystemFont(ofSize: size, weight: .light)
        )
    }

    static func dateSerif(size: CGFloat) -> NSFont {
        pick(
            names: ["NewYork-Regular", "IowanOldStyle-Roman", "Charter-Roman", "Optima-Regular"],
            size: size,
            fallback: system(size: size, weight: .medium, design: .serif)
        )
    }

    static func dateSans(size: CGFloat) -> NSFont {
        system(size: size, weight: .medium, design: .default)
    }

    static func dateMono(size: CGFloat) -> NSFont {
        pick(
            names: ["SFMono-Regular", "Menlo-Regular"],
            size: size,
            fallback: NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        )
    }

    /// Keep weather typography in the same family as the face date font.
    static func matching(_ font: NSFont, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let name = font.fontName.lowercased()
        if name.contains("newyork") || name.contains("didot") || name.contains("iowan")
            || name.contains("charter") || name.contains("optima") || name.contains("bodoni")
            || name.contains("serif") {
            return system(size: size, weight: weight, design: .serif)
        }
        if name.contains("mono") || name.contains("menlo") || name.contains("andale") {
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        if name.contains("rounded") {
            return system(size: size, weight: weight, design: .rounded)
        }
        return system(size: size, weight: weight, design: .default)
    }

    private static func pick(names: [String], size: CGFloat, fallback: NSFont) -> NSFont {
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return fallback
    }

    private static func system(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design),
              let font = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return font
    }
}

private extension NSFont {
    func monoDigits(size: CGFloat) -> NSFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? self
    }
}
