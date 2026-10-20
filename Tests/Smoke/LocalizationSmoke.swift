import AppKit
import SwiftUI

@main
struct LocalizationSmoke {
    @MainActor
    static func main() async throws {
        setenv("XCTestConfigurationFilePath", "localization-smoke", 1)
        let defaults = UserDefaults.standard
        let oldValue = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let oldValue { defaults.set(oldValue, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }

        expect(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-CN"]) == .english, "Respect system language order")
        expect(AppLanguage.system.resolved(preferredLanguages: ["zh_TW", "en-US"]) == .simplifiedChinese, "Recognize Chinese locale variants")
        expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-AU"]) == .english, "Choose the next supported system language")
        expect(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]) == .english, "Unsupported system language falls back to English")
        expect(AppLanguage.system.resolved(preferredLanguages: []) == .english, "Empty system preferences have a fallback")
        expect(AppLanguage.english.resolved(preferredLanguages: ["zh-CN"]) == .english, "Explicit choice overrides the system")

        let suiteName = "musepaper-localization-smoke-\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        defer { isolated.removePersistentDomain(forName: suiteName) }
        let preferences = LanguagePreferences(defaults: isolated)
        expect(preferences.selection == .system, "First launch follows the system")
        preferences.selection = .english
        expect(LanguagePreferences(defaults: isolated).selection == .english, "Restore language across launches")
        preferences.selection = .system
        expect(LanguagePreferences(defaults: isolated).selection == .system, "Follow System is a saved preference")
        isolated.set("unavailable-language", forKey: AppLanguage.preferenceKey)
        expect(LanguagePreferences(defaults: isolated).selection == .system, "Unknown preferences recover safely")

        expect(L10n.tr("生图", language: .english) == "Create", "English catalog is bundled")
        expect(L10n.tr("生图", language: .simplifiedChinese) == "生图", "Chinese source stays intact")
        expect(L10n.tr("未登记的键", language: .english) == "未登记的键", "Missing keys use source text")
        expect(L10n.tr("本批完成 \(2)/\(4)\(" · note")", language: .english) == "Batch completed 2/4 · note", "Interpolate counts and suffixes")
        let customName = "雨夜 {1} — 100% \\\"\nEnglish"
        expect(L10n.tr("用「\(customName)」现在生成", language: .english) == "Generate from “\(customName)” Now", "User content is never translated or parsed as placeholders")
        expect(L10n.render("{1}/{0}", arguments: ["a", "b"]) == "b/a", "Translations can reorder arguments")

        let resources = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MUSEPAPER_LOCALIZATION_RESOURCES"]!)
        let enData = try Data(contentsOf: resources.appendingPathComponent("en.lproj/Localizable.strings"))
        let zhData = try Data(contentsOf: resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings"))
        let en = try PropertyListSerialization.propertyList(from: enData, format: nil) as! [String: String]
        let zh = try PropertyListSerialization.propertyList(from: zhData, format: nil) as! [String: String]
        expect(Set(en.keys) == Set(zh.keys), "Catalog key coverage matches")
        let placeholder = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func placeholders(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                (text as NSString).substring(with: $0.range)
            }.sorted()
        }
        for (key, value) in en {
            expect(placeholders(key) == placeholders(value), "Placeholder mismatch for \(key)")
            expect(zh[key] == key, "Chinese fallback must match its source")
            expect(L10n.lookup(key, language: .english) == value, "Bundled English key missing: \(key)")
        }

        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        expect(MusepaperError.generationFailed("server detail").errorDescription == "Generation failed: server detail", "Localize errors with original provider details")
        expect(InspirationChannel.cadenceLabel(5) == "Every 5 hours", "Localize schedule intervals")
        expect(PlaylistOrder.shuffle.rawValue.localized == "Shuffle", "Localize enum display labels")
        expect(PlaylistOrder.shuffle.rawValue == "随机播放", "Persisted enum values remain stable")
        expect(WeatherSnapshot.condition(for: 95) == "Thunderstorm", "Localize weather conditions")
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let next = ScheduleService.nextFireCaption(intervalSeconds: 90, lastProducedAt: date, from: date, locale: Locale(identifier: "en_US"))
        expect(!next.contains("月") && !next.contains("日"), "English date formatting")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("musepaper-localization-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONStore(fileURL: root.appendingPathComponent("snapshot.json"))
        var snapshot = AppSnapshot()
        snapshot.channels[0].name = "我的系列 My Series"
        snapshot.channels[0].essence = "春天 afternoon {0}"
        snapshot.settings.desktopClockEnabled = false
        snapshot.settings.desktopWeatherEnabled = false
        try await store.save(snapshot)
        let model = StudioViewModel(store: store, generationOutputDirectory: root.appendingPathComponent("images"), credentialStore: CredentialStore(fileURL: root.appendingPathComponent("keys.json")))
        try await Task.sleep(for: .milliseconds(250))
        expect(model.generateActionTitle == "Try Demo", "View model uses English labels")
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.preferenceKey)
        model.refreshInterfaceLanguage()
        expect(model.generateActionTitle == "先用演示出图", "View model switches without recreation")
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.preferenceKey)
        model.refreshInterfaceLanguage()
        expect(model.generateActionTitle == "Try Demo", "Switch back to English")
        let saved = try await store.load()
        expect(saved.channels[0].name == snapshot.channels[0].name && saved.channels[0].essence == snapshot.channels[0].essence, "Language changes preserve saved creative content")
        if let path = ProcessInfo.processInfo.environment["MUSEPAPER_LOCALIZATION_PREVIEW_DIRECTORY"] {
            try await writePreviews(model: model, directory: URL(fileURLWithPath: path))
        }
        expect(L10n.tr("关于 SofunAI", language: .english) == "About SofunAI", "English SofunAI entry")
        expect(L10n.tr("SofunAI 工作室出品并维护", language: .english) == "Published and maintained by SofunAI Studio", "English publisher identity")
        print("LOCALIZATION_SMOKE_OK checks=\(checks) catalog_keys=\(en.count)")
    }

    /// Render native views offscreen using isolated smoke-test data.
    @MainActor
    private static func writePreviews(model: StudioViewModel, directory: URL) async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .simplifiedChinese] {
            LanguagePreferences.shared.selection = language
            let host = NSHostingView(rootView: StudioView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            for page in ["create", "settings"] {
                try await Task.sleep(for: .milliseconds(300))
                if page == "settings" {
                    NotificationCenter.default.post(name: .musepaperOpenSettings, object: nil)
                    try await Task.sleep(for: .milliseconds(300))
                }
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    fatalError("Unable to create native preview")
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = bitmap.representation(using: .png, properties: [:])!
                try data.write(to: directory.appendingPathComponent("\(language.rawValue)-\(page).png"))
            }
            window.close()
            let aboutHost = NSHostingView(rootView: MusepaperAboutView())
            let aboutWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
            aboutWindow.isReleasedWhenClosed = false
            aboutWindow.contentView = aboutHost
            try await Task.sleep(for: .milliseconds(300))
            aboutHost.layoutSubtreeIfNeeded()
            let bitmap = aboutHost.bitmapImageRepForCachingDisplay(in: aboutHost.bounds)!
            aboutHost.cacheDisplay(in: aboutHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(language.rawValue)-about.png"))
            aboutWindow.close()
        }
    }
}
