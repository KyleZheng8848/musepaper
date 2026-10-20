import Foundation

/// Interpolations stay separate from the lookup key, so names, prompts and URLs
/// are preserved verbatim and translators can reorder arguments safely.
struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    static var locale: Locale { AppLanguage.current.locale }
    static var isChinese: Bool { AppLanguage.current.resolved() == .simplifiedChinese }

    private static let resourceBundle: Bundle = {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }()
    private static let englishBundle: Bundle? = {
        resourceBundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    }()

    static func lookup(_ key: String, language: AppLanguage = .current) -> String {
        guard language.resolved() == .english else { return key }
        return englishBundle?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    static func tr(_ text: LocalizedText, language: AppLanguage = .current) -> String {
        render(lookup(text.key, language: language), arguments: text.arguments)
    }

    /// One pass avoids interpreting braces or placeholder-like text inside user input.
    static func render(_ template: String, arguments: [String]) -> String {
        var result = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]),
               arguments.indices.contains(index) {
                result += arguments[index]
                cursor = template.index(after: end)
            } else {
                result.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        return result
    }
}

extension String {
    /// For stable persisted enum values, only at the UI boundary.
    var localized: String { L10n.lookup(self) }
}
