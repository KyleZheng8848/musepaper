import Combine
import Foundation

/// Persist language separately from artwork snapshots, so switching never rewrites creative content.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, simplifiedChinese = "zh-Hans", english = "en"

    static let preferenceKey = "musepaper.interfaceLanguage"
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: L10n.tr("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if code == "zh" || code.hasPrefix("zh-") { return .simplifiedChinese }
            if code == "en" || code.hasPrefix("en-") { return .english }
        }
        return .english
    }

    var locale: Locale { Locale(identifier: resolved().rawValue) }
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }
}

extension Notification.Name {
    static let musepaperLanguageChanged = Notification.Name("musepaper.languageChanged")
}

@MainActor
final class LanguagePreferences: ObservableObject {
    static let shared = LanguagePreferences()

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: AppLanguage.preferenceKey)
            NotificationCenter.default.post(name: .musepaperLanguageChanged, object: nil)
        }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage(rawValue: defaults.string(forKey: AppLanguage.preferenceKey) ?? "") ?? .system
    }

    func refreshSystemLanguage() {
        guard selection == .system else { return }
        objectWillChange.send()
        NotificationCenter.default.post(name: .musepaperLanguageChanged, object: nil)
    }
}
