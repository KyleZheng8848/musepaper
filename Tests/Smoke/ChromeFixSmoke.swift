import AppKit
import Foundation

@main
struct ChromeFixSmoke {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw SmokeError.failed(name) }
            checks += 1
        }

        let composer = PromptComposer()
        let draft = PromptDraft(input: "超清晰，4k，壁纸，桌面，千岛之国，悠闲，热带风景")
        let prompt = try composer.resolve(draft: draft, channel: nil, display: .preview)
        try expect(prompt.contains("千岛之国"), "keep-subject")
        try expect(!prompt.contains("电影感光影") && !prompt.contains("景物铺到四边"), "no-framing-essay")
        try expect(!prompt.localizedCaseInsensitiveContains("4k"), "strip-4k")
        try expect(!prompt.contains("超清晰"), "strip-clarity-spec")
        try expect(!prompt.contains("壁纸") && !prompt.contains("桌面"), "strip-wallpaper-desktop")
        try expect(!prompt.contains("Dock") && !prompt.contains("菜单栏") && !prompt.contains("避免："), "no-ui-words")
        let negative = composer.negativePrompt(draft: draft, channel: nil)
        try expect(negative.localizedCaseInsensitiveContains("desktop screenshot"), "neg-screenshot")
        try expect(negative.localizedCaseInsensitiveContains("dock"), "neg-dock")
        try expect(negative.localizedCaseInsensitiveContains("menu bar"), "neg-menubar")
        try expect(negative.contains("说明书") || negative.localizedCaseInsensitiveContains("infographic"), "neg-manual")
        try expect(negative.contains("文字") || negative.localizedCaseInsensitiveContains("text"), "neg-text")

        let essay = composer.enforcePureArtwork("""
        简短系列名，一句审美定义，逗号分隔的不可变核心词
        一个分辨率为 3600x2338 的热带岛屿
        保留主题与审美，不要写留白绘图标
        """)
        try expect(essay.contains("热带岛屿"), "keep-island")
        try expect(!composer.containsInstructionLeak(essay), "essay-cleaned")
        try expect(!essay.contains("简短系列名") && !essay.contains("3600") && !essay.contains("不要写"), "strip-manual")

        var seriesDraft = PromptDraft(input: "超清晰，4k，千岛之国")
        seriesDraft.mode = .inspiration
        let placeholder = InspirationChannel(
            name: "简短系列名", essence: "一句审美定义",
            coreKeywords: "逗号分隔的不可变核心词"
        )
        let seriesPrompt = try composer.resolve(draft: seriesDraft, channel: placeholder, display: .preview, seed: 1)
        try expect(seriesPrompt.contains("千岛之国"), "series-keeps-idea")
        try expect(!seriesPrompt.contains("一句审美定义") && !seriesPrompt.contains("简短系列名"), "series-drops-template")

        let pinned = composer.pinCore("马尔代夫的果冻海", onto: "黄昏时分开阔的热带浅海")
        try expect(pinned.contains("马尔代夫的果冻海"), "pin-core")
        var used = Set<String>()
        let distinguished = composer.distinguish(
            "一句审美定义，分辨率 3600x2338", used: &used, index: 0, seed: 3, core: "马尔代夫的果冻海"
        )
        try expect(distinguished.contains("马尔代夫的果冻海"), "distinguish-keeps-core")
        try expect(!distinguished.contains("开阔的风景"), "distinguish-not-generic")
        var coreDraft = PromptDraft(input: "超级无敌峡湾地貌")
        coreDraft.mode = .inspiration
        let coreChannel = InspirationChannel(
            name: "果冻海", essence: "马尔代夫的果冻海", coreKeywords: "马尔代夫的果冻海"
        )
        let corePrompt = try composer.resolve(draft: coreDraft, channel: coreChannel, display: .preview, seed: 2)
        try expect(corePrompt.contains("超级无敌峡湾地貌"), "weave-uses-typed-idea")
        try expect(!corePrompt.contains("马尔代夫") && !corePrompt.contains("玻璃幕墙"), "weave-no-second-subject")
        for scene in composer.uniqueScenePrompts(idea: "超级无敌峡湾地貌", channel: nil, emptySpace: .right, seedBase: 11, count: 4) {
            try expect(scene.contains("超级无敌峡湾地貌"), "batch-keeps-preset")
        }

        try expect(
            !OpenAIImageProvider.shouldSendNegativePrompt(provider: .openAI, baseURL: "https://api.openai.com/v1"),
            "official-skip-negative"
        )
        try expect(
            OpenAIImageProvider.shouldSendNegativePrompt(provider: .compatible, baseURL: "http://127.0.0.1:8080/v1"),
            "compatible-send-negative"
        )
        try expect(
            OpenAIImageProvider.shouldSendNegativePrompt(provider: .openAI, baseURL: "https://image.example.com/v1"),
            "custom-send-negative"
        )

        let cropper = DesktopChromeCropper()
        let chrome = makeChromeMockup(width: 400, height: 280)
        let chromeInsets = cropper.insets(of: chrome)
        try expect(chromeInsets.top >= 10, "crop-top \(chromeInsets.top)")
        try expect(chromeInsets.bottom >= 24, "crop-bottom \(chromeInsets.bottom)")
        try expect(chromeInsets.left >= 6 && chromeInsets.right >= 6, "crop-sides \(chromeInsets.left)x\(chromeInsets.right)")
        let cropped = cropper.cropIfNeeded(chrome)
        try expect(cropped.size.height < chrome.size.height && cropped.size.width < chrome.size.width, "cropped-smaller")

        let landscape = makeLandscape(width: 400, height: 280)
        try expect(cropper.insets(of: landscape) == ChromeInsets(top: 0, left: 0, bottom: 0, right: 0), "landscape-kept")

        let spec = makeTextSpecSheet(width: 400, height: 280)
        let specInsets = cropper.insets(of: spec)
        try expect(specInsets.top >= 20 && specInsets.bottom >= 20, "crop-text-plates \(specInsets)")
        let bottomOnly = makeBottomTextSheet(width: 400, height: 280)
        let bottomInsets = cropper.insets(of: bottomOnly)
        try expect(bottomInsets.bottom >= 80, "crop-bottom-only \(bottomInsets)")

        let night = makeNightSky(width: 400, height: 280)
        let nightInsets = cropper.insets(of: night)
        try expect(nightInsets.top == 0 && nightInsets.bottom == 0, "night-sky-kept \(nightInsets)")

        print("CHROME_FIX_OK checks=\(checks)")
    }
}

private enum SmokeError: Error {
    case failed(String)
}

private func makeChromeMockup(width: Int, height: Int) -> NSImage {
    makeImage(width: width, height: height) { bounds in
        NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.58, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.32, alpha: 1).setFill()
        NSRect(x: 40, y: 70, width: 320, height: 90).fill()
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 10, height: bounds.height).fill()
        NSRect(x: bounds.width - 10, y: 0, width: 10, height: bounds.height).fill()
        NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.102, alpha: 1).setFill()
        NSRect(x: 0, y: bounds.height - 16, width: bounds.width, height: 16).fill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 40).fill()
        let iconColors: [NSColor] = [
            NSColor(calibratedRed: 0.20, green: 0.72, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.38, green: 0.86, blue: 0.40, alpha: 1),
            NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.48, blue: 0.98, alpha: 1)
        ]
        for (index, color) in iconColors.enumerated() {
            color.setFill()
            NSRect(x: 70 + CGFloat(index) * 52, y: 8, width: 22, height: 22).fill()
        }
    }
}

private func makeLandscape(width: Int, height: Int) -> NSImage {
    makeImage(width: width, height: height) { bounds in
        NSGradient(
            starting: NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.28, alpha: 1),
            ending: NSColor(calibratedRed: 0.12, green: 0.48, blue: 0.62, alpha: 1)
        )?.draw(in: bounds, angle: -18)
        NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 30, width: 180, height: 90)).fill()
    }
}

private func makeTextSpecSheet(width: Int, height: Int) -> NSImage {
    makeImage(width: width, height: height) { bounds in
        NSColor(calibratedRed: 0.18, green: 0.62, blue: 0.58, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: bounds.height - 72, width: bounds.width, height: 72).fill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 72).fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        for row in 0..<6 {
            for col in 0..<16 {
                NSRect(x: 14 + CGFloat(col) * 22, y: bounds.height - 18 - CGFloat(row) * 10, width: 9, height: 4).fill()
                NSRect(x: 14 + CGFloat(col) * 22, y: 14 + CGFloat(row) * 10, width: 8, height: 4).fill()
            }
        }
    }
}

private func makeBottomTextSheet(width: Int, height: Int) -> NSImage {
    makeImage(width: width, height: height) { bounds in
        NSColor(calibratedRed: 0.42, green: 0.58, blue: 0.38, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: 150, width: 200, height: 80)).fill()
        NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 120).fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        for row in 0..<10 {
            for col in 0..<16 {
                NSRect(x: 14 + CGFloat(col) * 22, y: 12 + CGFloat(row) * 10, width: 9, height: 4).fill()
            }
        }
    }
}

private func makeNightSky(width: Int, height: Int) -> NSImage {
    makeImage(width: width, height: height) { bounds in
        NSColor(calibratedRed: 0.043, green: 0.094, blue: 0.188, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedRed: 0.10, green: 0.19, blue: 0.31, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 50).fill()
        NSColor.white.setFill()
        var seed = 17
        for _ in 0..<90 {
            seed = seed &* 1103515245 &+ 12345
            let x = CGFloat(abs(seed) % width)
            seed = seed &* 1103515245 &+ 12345
            let y = CGFloat(abs(seed) % height)
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }
    }
}

private func makeImage(width: Int, height: Int, draw: (NSRect) -> Void) -> NSImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}
