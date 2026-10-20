import Foundation

/// In-app changelog — keep locked with `CHANGELOG.md` and `Packaging/VERSION`.
struct ChangelogEntry: Identifiable, Equatable, Sendable {
    var version: String
    var date: String
    var highlights: [String]
    var id: String { "\(version)-\(date)" }
}

enum AppChangelog {
    static let entries: [ChangelogEntry] = [
                                                                                                                                                                                                                                                                                                                                                                                ChangelogEntry(
            version: "0.5.39",
            date: "2026-08-28",
            highlights: [
                "心情句按看见什么轮换：人、空场、静物、室内",
                "Agent 补人不再把系列改成人物题",
                "参考图不再逼下一张继续长人"
            ]
        )
    ]

    static var latest: ChangelogEntry? { entries.first }
}
