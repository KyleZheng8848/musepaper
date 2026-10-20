import Foundation

enum AppVersion {
    /// Marketing version. Keep in lockstep with `Packaging/VERSION`.
    static let marketing = "0.5.63"

    static var build: String {
        let value = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "dev" : trimmed
    }

    static var display: String {
        build == "dev" ? marketing : "\(marketing) · \(build)"
    }

    static var windowTitle: String { "Musepaper \(marketing)" }

    /// Latest release blurb from changelog.
    static var releaseNote: String {
        AppChangelog.latest?.highlights.first ?? "Musepaper \(marketing)"
    }
}
